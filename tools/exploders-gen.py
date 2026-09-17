#!/usr/bin/env python3
"""exploders-gen.py - the per-map RADIANT EXPLODER table, read OFFLINE out of the T9 dump, written
INTO gunfight_menu.gsc between its two marker lines. READ-ONLY on the dump.

    python tools/exploders-gen.py                       # dump at ../bocw-source-main
    python tools/exploders-gen.py /c/path/to/dump       # or say where it is
    python tools/exploders-gen.py --check               # regenerate to memory, diff, exit 1 if stale

Writes docs/data/map-exploders.json and rewrites the block in
src/gunfight_menu/scripts/gunfight_menu.gsc between

    // [exploders-gen BEGIN]
    // [exploders-gen END]

WHY THIS EXISTS (docs/notes/destructibles.md §7). `tables/bgcache/<map>.csv` lists every
`radiant_exploder` a map zone precaches - the map's authored FX / light / sound triggers - and
`exploder::exploder( id )` fires one by NAME (exploder_shared.gsc:278 -> activate_radiant_exploder
:731 -> activateclientradiantexploder). Every name in the manifests is a HASH, and that is fine:
the call takes a hash (frontend.csc:3881 passes #"hash_..." to it; "" + #"hash" is a stock idiom,
archetype_avogadro.gsc:49). So the per-map list ships as data, no cracking needed. Zero are
universal (core_bootstrap / core_common / mp_common carry none), so the table is purely per map.

Labels: a hash is cracked against every string literal the mp / mp_common / core_common / wz /
killstreaks scripts spell out (FNV1a64 & MASK63, the algorithm tools/crack-hash.py documents),
which names the ones map scripts fire themselves (fxexp_holiday, fxexp_tundra_6v6, the Express
train debris set, WMD's room lights...). The rest stay hash-labelled and are fired by index -
the menu's walker prints the index so a good one can be written down here as a `label`.

The GSC side (gunfight_menu.gsc, DESTRUCTIBLES + RADIANT EXPLODERS): exp_table() dispatches on
the map name to one generated exp_rows_<map>() per map; each row is exp_add( e, key, label ).
Cracked names are passed as the plain STRING (the form every stock map script uses); the
others as the #"hash_..." literal. Rows keep the manifest's order, so an index is stable until
the dump changes.
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEFAULT_DUMP = os.path.join(os.path.dirname(REPO), "bocw-source-main")
OUT_JSON = os.path.join(REPO, "docs", "data", "map-exploders.json")
GSC = os.path.join(REPO, "src", "gunfight_menu", "scripts", "gunfight_menu.gsc")
BEGIN = "// [exploders-gen BEGIN]"
END = "// [exploders-gen END]"

MASK64 = 0xFFFFFFFFFFFFFFFF
MASK63 = 0x7FFFFFFFFFFFFFFF


def hash64(s: str) -> int:
    h = 0xCBF29CE484222325
    for c in s.lower():
        h = ((h ^ ord(c)) * 0x100000001B3) & MASK64
    return h & MASK63


# The string literals stock scripts pass around: harvested once, hashed once. Exploder names
# come from map scripts (scripts/mp/<map>.gsc) and the shared systems.
HARVEST_ROOTS = ["scripts/mp", "scripts/mp_common", "scripts/core_common", "scripts/wz", "scripts/killstreaks"]


def harvest_literals(dump: str) -> dict[int, str]:
    table: dict[int, str] = {}
    lit = re.compile(r'"([A-Za-z0-9_]{3,64})"')
    for root in HARVEST_ROOTS:
        for ext in ("gsc", "csc"):
            for f in glob.glob(os.path.join(dump, root, "**", f"*.{ext}"), recursive=True):
                try:
                    text = open(f, encoding="utf-8", errors="ignore").read()
                except OSError:
                    continue
                for m in lit.finditer(text):
                    s = m.group(1)
                    table.setdefault(hash64(s), s)
    return table


def zone_rows(path: str) -> list[str]:
    rows: list[str] = []
    seen: set[str] = set()
    for line in open(path, encoding="utf-8", errors="ignore"):
        if not line.startswith("radiant_exploder,#"):
            continue
        name = line.strip().split(",#", 1)[1]
        if name and name not in seen:
            seen.add(name)
            rows.append(name)
    return rows


def build(dump: str) -> dict:
    names = harvest_literals(dump)
    maps: dict[str, list[dict]] = {}
    zones = sorted(glob.glob(os.path.join(dump, "tables", "bgcache", "mp_*.csv")) +
                   glob.glob(os.path.join(dump, "tables", "bgcache", "wz_*.csv")))
    universal: set[str] = set()
    for z in ("core_bootstrap", "core_common", "mp_common"):
        universal.update(zone_rows(os.path.join(dump, "tables", "bgcache", f"{z}.csv")))
    cracked = total = 0
    for zpath in zones:
        zone = os.path.basename(zpath)[:-4]
        if zone == "mp_common":
            continue
        rows = []
        for name in zone_rows(zpath):
            if name in universal:
                continue
            total += 1
            if name.startswith("hash_"):
                label = names.get(int(name[5:], 16), "")
                if label:
                    cracked += 1
                rows.append({"key": name, "label": label})
            else:
                cracked += 1
                rows.append({"key": name, "label": name})
        if rows:
            maps[zone] = rows
    return {
        "generated": str(date.today()),
        "source": "bocw-source-main tables/bgcache/<map>.csv radiant_exploder rows; labels cracked against script string literals",
        "universal": sorted(universal),
        "total": total,
        "cracked": cracked,
        "maps": maps,
    }


def gsc_ident(zone: str) -> str:
    return re.sub(r"[^a-z0-9_]", "_", zone.lower())


def gsc_block(data: dict) -> str:
    out = []
    out.append(BEGIN)
    out.append("// GENERATED by tools/exploders-gen.py from tables/bgcache/<map>.csv - do not edit by hand.")
    out.append(f"// {data['total']} radiant exploders over {len(data['maps'])} maps, {data['cracked']} named "
               f"(string form), the rest by #\"hash\" literal in manifest order. {data['generated']}.")
    out.append("function private exp_table()")
    out.append("{")
    out.append("    if ( isdefined( level.gf_exp_table ) )")
    out.append("        return level.gf_exp_table;")
    out.append("")
    out.append("    // sv_mapname: measured a plain string on every map (the census prints it); level.script")
    out.append("    // may be a hash in this VM and a switch on it would match nothing.")
    out.append("    mapname = tolower( getdvarstring( #\"sv_mapname\", \"\" ) );")
    out.append("")
    out.append("    e = [];")
    out.append("")
    out.append("    switch ( mapname )")
    out.append("    {")
    for zone in data["maps"]:
        out.append(f'        case "{zone}": e = exp_rows_{gsc_ident(zone)}(); break;')
    out.append("    }")
    out.append("")
    out.append("    level.gf_exp_table = e;")
    out.append("    return e;")
    out.append("}")
    for zone, rows in data["maps"].items():
        out.append("")
        out.append(f"function private exp_rows_{gsc_ident(zone)}()")
        out.append("{")
        out.append("    e = [];")
        for r in rows:
            if r["label"]:
                out.append(f'    e = exp_add( e, "{r["label"]}", "{r["label"]}" );')
            else:
                out.append(f'    e = exp_add( e, #"{r["key"]}", "" );')
        out.append("    return e;")
        out.append("}")
    out.append(END)
    return "\n".join(out)


def splice(src: str, block: str) -> str:
    a = src.find(BEGIN)
    b = src.find(END)
    if a < 0 or b < 0 or b < a:
        raise SystemExit(f"markers not found in {GSC}: put '{BEGIN}' and '{END}' lines where the table goes")
    b_end = b + len(END)
    nl = "\r\n" if "\r\n" in src else "\n"
    return src[:a] + block.replace("\n", nl) + src[b_end:]


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dump = args[0] if args else DEFAULT_DUMP
    if not os.path.isdir(os.path.join(dump, "tables", "bgcache")):
        print(f"no tables/bgcache under {dump}", file=sys.stderr)
        return 2
    data = build(dump)
    block = gsc_block(data)
    src = open(GSC, encoding="utf-8", newline="").read()
    new = splice(src, block)
    if "--check" in sys.argv:
        stale = new != src
        print("STALE - rerun tools/exploders-gen.py" if stale else "up to date")
        return 1 if stale else 0
    with open(GSC, "w", encoding="utf-8", newline="") as f:
        f.write(new)
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    per = ", ".join(f"{z} {len(r)}" for z, r in sorted(data["maps"].items(), key=lambda kv: -len(kv[1]))[:8])
    print(f"{data['total']} exploders over {len(data['maps'])} maps, {data['cracked']} named; top: {per}")
    print(f"wrote {OUT_JSON} and the block in {GSC}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
