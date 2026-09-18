"""mapdata_scan.py - read the mod's per-map census out of the running game. READ-ONLY.

roster_scan.py's sibling. gunfight_menu.gsc publishes three marked strings once per level
(mapdata_publish, docs/notes/map-data.md), alive in level fields for the whole level:

    GFMAPVEH|<map>|<gametype>|<drivable keys>|<other keys>|END
    GFMAPPROP|<map>|tbl=1|rows=13|<model>:<size>,...|END        (or tbl=0)
    GFMAPSPAWN|<map>|<STARTS tally>|<family note>|END
    GFMAPDEST|<map>|n=<count>|kinds=<k>|<def>x<count>,...|END    (the destructibles, real def names)

Same read-only primitive as the roster (OpenProcess VM_READ + VirtualQueryEx + ReadProcessMemory,
no thread, no write). Every hit is filed into mapdata/<map>.json next to this file, merged over
what was there - so the per-map database (vehicles, Prop Hunt props, spawn keys) fills itself as
maps get played. Stale copies of an older level parse fine and carry their own map name.

    python mapdata_scan.py            # one sweep, print + file whatever is in memory now
    python mapdata_scan.py --loop     # every 20 s
    python mapdata_scan.py --show     # print the files on disk, no game needed
"""
from __future__ import annotations

import ctypes
import json
import os
import re
import sys
import time
from datetime import datetime

import roster_scan as rs

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "mapdata")

MARK_RE = re.compile(rb"GFMAP(VEH|PROP|SPAWN|DEST)\|")
END = b"|END"
MAX_LEN = 6144


def parse(kind: str, body: str) -> tuple[str, dict] | None:
    parts = body.split("|")
    if len(parts) < 2 or not parts[0]:
        return None
    mapname = parts[0]
    if kind == "VEH":
        if len(parts) != 4:
            return None
        return mapname, {"gametype": parts[1],
                         "vehicles_drive": [x for x in parts[2].split(",") if x],
                         "vehicles_other": [x for x in parts[3].split(",") if x]}
    if kind == "PROP":
        if parts[1] == "tbl=0":
            return mapname, {"props": {"table": False, "rows": 0, "list": []}}
        if len(parts) != 4 or not parts[2].startswith("rows="):
            return None
        rows = int(parts[2][5:] or 0)
        items = []
        for cell in parts[3].split(","):
            if not cell:
                continue
            model, _, size = cell.partition(":")
            items.append({"model": model, "size": size})
        return mapname, {"props": {"table": True, "rows": rows, "list": items}}
    if kind == "SPAWN":
        # MEASURED 2026-09-17 (Gas Station): the tally itself carries a pipe -
        # "... NAMED tdm=0/0 ... | GROUPS n=0 a=0() b=0()" - so the body is 4 fields, not 3:
        # everything between the map and the LAST field is the tally, the last field the note.
        if len(parts) < 3:
            return None
        return mapname, {"spawn": {"starts": "|".join(parts[1:-1]).strip(),
                                   "family_note": parts[-1].strip()}}
    if kind == "DEST":
        # The destructibles' .destructibledef names read live - the manifests hash every one
        # (docs/notes/destructibles.md §4), so this channel is where the real names come from.
        if len(parts) != 4 or not parts[1].startswith("n=") or not parts[2].startswith("kinds="):
            return None
        kinds = []
        for cell in parts[3].split(","):
            if not cell or cell == "...":
                continue
            name, _, count = cell.rpartition("x")
            try:
                kinds.append({"def": name, "count": int(count)})
            except ValueError:
                kinds.append({"def": cell, "count": 0})
        return mapname, {"destructibles": {"entities": int(parts[1][2:] or 0),
                                           "kinds": int(parts[2][6:] or 0), "list": kinds}}
    return None


class MapScanner(rs.Scanner):
    """One sweep = every private writable region, exe-range regions first; all hits merged."""

    def sweep(self) -> dict[str, dict]:
        found: dict[str, dict] = {}
        kinds: set[tuple[str, str]] = set()
        step = rs.Scanner._STEP
        buf = (ctypes.c_char * (step + MAX_LEN))()
        mv = memoryview(buf)
        got = ctypes.c_size_t(0)
        regions = list(self._regions())
        if self.module is None:
            self.module = rs.module_range(self.pid)

        def rank(r):
            b, s = r
            if self.module is not None and self.module[0] <= b < self.module[0] + self.module[1]:
                return (0, -s)
            return (1, b)

        regions.sort(key=rank)
        t0 = time.perf_counter()
        for base, size in regions:
            off = 0
            while off < size:
                want = min(step + MAX_LEN, size - off)
                if rs._k32.ReadProcessMemory(self.h, base + off, buf, want, ctypes.byref(got)) and got.value:
                    n = got.value
                    for m in MARK_RE.finditer(mv, 0, n):
                        i = m.start()
                        j = buf.raw.find(END, i, min(n, i + MAX_LEN))
                        if j == -1:
                            continue
                        kind = m.group(1).decode()
                        body = buf.raw[m.end(): j].decode("utf-8", "replace")
                        r = parse(kind, body)
                        if r is None:
                            continue
                        mapname, data = r
                        found.setdefault(mapname, {}).update(data)
                        kinds.add((mapname, kind))
                off += step
            # The pool the mod's strings live in is one region; once it yielded all three
            # kinds for some map there is nothing newer elsewhere.
            if found and all((mp, k) in kinds for mp in found for k in ("VEH", "PROP", "SPAWN")):
                break
        self.last_sweep_s = time.perf_counter() - t0
        return found


def file_results(found: dict[str, dict]) -> list[str]:
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for mapname, data in found.items():
        path = os.path.join(OUT_DIR, f"{mapname}.json")
        cur = {}
        if os.path.exists(path):
            try:
                cur = json.load(open(path, encoding="utf-8"))
            except Exception:
                cur = {}
        cur.update(data)
        cur["map"] = mapname
        cur["captured"] = datetime.now().isoformat(timespec="seconds")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(cur, f, indent=1)
            f.write("\n")
        written.append(path)
    return written


def summary(mapname: str, d: dict) -> str:
    v = d.get("vehicles_drive", [])
    o = d.get("vehicles_other", [])
    p = d.get("props", {})
    s = d.get("spawn", {})
    x = d.get("destructibles", {})
    return (f"{mapname} [{d.get('gametype', '?')}]  drivable: {', '.join(v) or '-'}  |  other: {len(o)}"
            f"  |  props: {'table ' + str(p.get('rows')) + ' rows' if p.get('table') else 'no table'}"
            f"  |  destructibles: {x.get('entities', '?')} ({x.get('kinds', '?')} kinds)"
            f"  |  starts:{s.get('starts', ' ?')}  {s.get('family_note', '')}")


def main() -> int:
    if "--show" in sys.argv:
        if not os.path.isdir(OUT_DIR):
            print("no mapdata/ yet")
            return 0
        for fn in sorted(os.listdir(OUT_DIR)):
            if fn.endswith(".json"):
                d = json.load(open(os.path.join(OUT_DIR, fn), encoding="utf-8"))
                print(summary(d.get("map", fn[:-5]), d))
        return 0

    pid = rs.find_game_pid()
    sc = MapScanner(pid)
    try:
        while True:
            found = sc.sweep()
            if not found:
                print(f"no GFMAP strings in memory ({sc.last_sweep_s:.1f} s) - is the menu injected and a map loaded?")
            else:
                for mp, d in found.items():
                    print(summary(mp, d))
                for path in file_results(found):
                    print("  filed", path)
            if "--loop" not in sys.argv:
                break
            time.sleep(20)
    finally:
        sc.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
