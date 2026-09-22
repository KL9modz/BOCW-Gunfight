#!/usr/bin/env python3
"""props-gen.py - the full spawnable-PROP catalog, read OFFLINE out of the T9 dump. READ-ONLY.

    python tools/props-gen.py                       # dump at ../bocw-source-main
    python tools/props-gen.py /c/path/to/dump       # or say where it is
    python tools/props-gen.py --check               # regenerate to memory, diff, exit 1 if stale

Writes two things:
  1. docs/data/map-props.json  - the SHARED CONTRACT the C# panel (tools/gf-panel) reads: the full
     universal catalog (~338 p9_ xmodels resident on every MP map) plus each map's own prop pool
     (thousands more), with stable indices, labels and a barrel/explodable flag.
  2. the GSC block in src/gunfight_menu/scripts/gunfight_menu.gsc between
        // [props-gen BEGIN]
        // [props-gen END]
     = prop_master(), the UNIVERSAL 338 as an indexed array. The in-game menu renders only a
     FAVORITES subset of this (set from the app); the app spawns any of the 338 by index
     (cmd_propidx) and any per-map model by chunked name (cmd_propname), so the 43k per-map models
     never need to live in the GSC.

WHY THIS EXISTS (docs/notes/static-props.md). A spawnable prop is a plain `script_model` +
setmodel( xmodel ) (prop.gsc:1946). "Which xmodels are resident" is answered offline by the per-zone
manifests: `tables/data/assets/<zone>.csv`, one `type,name` row each, name is `#`-prefixed. Under MP
a map runs core_bootstrap + core_common + mp_common + its own zone, so the union of their
`type == xmodel` rows in the p9_/p8_/p7_ prop families is the resident prop set. The universal three
carry 338 p9_ xmodels; each map zone adds ~1,000 more. Only xmodel rows are spawnable (the same name
also appears as xmodelmesh/xcollision/material/image - not a model you can setmodel).

Barrels: the flag marks drums / jerrycans / fuel cans that read well as explosive barrels. The mod
spawns them with cp_explosive_barrel's core recipe (damage watch -> physicsexplosionsphere +
radiusdamage), server-side, so a joiner sees the blast. The literal red campaign barrel
(p9_rus_barrel_explosive_red_01) is NOT resident on MP maps (campaign/zm zones only), so the flag
picks the barrels that ARE universal.
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
OUT_JSON = os.path.join(REPO, "docs", "data", "map-props.json")
# GSC target; PROPS_GEN_GSC overrides it (used to fill the block in a scratchpad test copy).
GSC = os.environ.get("PROPS_GEN_GSC") or os.path.join(REPO, "src", "gunfight_menu", "scripts", "gunfight_menu.gsc")
BEGIN = "// [props-gen BEGIN]"
END = "// [props-gen END]"

# Zones every MP map runs with (the map's own zone is added per map). Same set mapdata-extract.py uses.
COMMON_ZONES = ["core_bootstrap", "core_common", "mp_common"]

# Prop families: p9_ (T9), p8_ (BO4/WZ carryovers), p7_ (older). Only `type == xmodel` rows spawn.
FAMILIES = ("p9_", "p8_", "p7_")

# A barrel/drum/fuel-can that reads as an explosive barrel. Exclude model PARTS (a lid/bottom is not a
# barrel you spawn) and false hits (barrel cactus, barrel-vault foliage, a boat named barrel_boat).
BARREL_RE = re.compile(r"(barrel|_drum|jerrycan|jerry_can|propane|gas_can|fuel_can|canister|gas_metal)", re.I)
BARREL_NO = re.compile(r"(foliage|cactus|_boat|_btm|_lid|_top|_cap\b|_lids|vault|cannon|gun_barrel)", re.I)

# Models dropped from the catalog entirely (klaze 2026-09-21): "remove debris props" (rubble / scrap /
# glass-shatter / dirt-clod, p*_debris_* / p*_fxp_debris_*) + "remove fluids from props" (fx-particle
# fluid droplets / spills / clumps - p*_fxp_fluid_*) + the 26 character dogtags ("keep 2, 1 friendly 1
# enemy" - kept via EXCLUDE_KEEP below) + p9_heart_name_* valentine hearts ("don't seem to work"). Only
# the spawnable PROP families; exploder FX (fxexp_) and vehicle wreck parts (veh_) are separate, untouched.
EXCLUDE_RE = re.compile(r"debris|fluid|dogtag|heart_name|gib_chunk|decal_scratches|supplydrop.*(harness|fade)", re.I)   # gib chunks, decal scratches, supply-drop harness/fade rigs out (klaze 2026-09-22)

# Kept despite EXCLUDE_RE (klaze "only keep 2 dog tags, 1 friendly 1 enemy"): one enemy + one friendly
# (Adler). Lowercase - matched against the lowercased model name.
EXCLUDE_KEEP = {"p9_dogtags_adler_enemy", "p9_dogtags_adler_friendly"}

# Region/theme tokens that lead a prop name and carry no meaning for a human label.
REGION = {
    "usa", "rus", "ger", "lat", "nic", "cli", "ang", "mal", "nt6", "nt6x", "ship", "kgb", "amk",
    "pai", "hjk", "vlg", "rai", "zoo", "rm", "sm", "wz", "gp", "foliage", "fxanim", "t9", "t8",
}

# Keep the hand-tuned labels the menu already had (static-props.md 8) so the good 49 stay readable;
# everything else is auto-labelled. model -> label.
CURATED = {
    "p9_barrel_metal_rusted_01_prophunt": "Rusted barrel (PH)",
    "p9_krail_concrete_worn_01_prophunt": "Concrete K-rail (PH)",
    "p9_rm_rai_dub_vase_prophunt": "Vase (PH)",
    "p9_ang_satellite_panel_02_prophunt": "Satellite panel (PH)",
    "p9_ang_satellite_panel_03_prophunt": "Satellite panel 3 (PH)",
    "p9_ang_satellite_capsule_plate_02_prophunt": "Capsule plate (PH)",
    "p9_nt6_abandoned_mattress_01_prophunt": "Mattress (PH)",
    "p9_nt6_mannequin_clothes_female_02_dmg_full_prophunt": "Mannequin F2 (PH)",
    "p9_nt6_mannequin_clothes_female_03_dirty_full_prophunt": "Mannequin F3 (PH)",
    "p9_nt6_mannequin_clothes_male_01_dirty_full_prophunt": "Mannequin M1 (PH)",
    "p9_ger_tank_computer_server_diagnostic_01_silver_prophunt": "Server rack (PH)",
    "p9_ger_tank_tank_tread_rolls_01_prophunt": "Tank tread rolls (PH)",
    "p9_usa_bench_01": "Park bench",
    "p9_usa_bicycle_01": "Bicycle",
    "p9_usa_couch_04": "Couch",
    "p9_usa_dumpster_01_full": "Dumpster",
    "p9_usa_mailbox_01": "Mailbox",
    "p9_usa_street_light_01": "Street light",
    "p9_usa_vending_machine_soda_02": "Soda machine",
    "p9_usa_kgb_target_dummy_01": "Target dummy",
    "p9_usa_chair_beach": "Beach chair",
    "p9_usa_surf_longboard_01": "Surfboard",
    "p9_nt6_arcade_game": "Arcade game",
    "p9_nt6_machine_washing_dirty": "Washing machine",
    "p9_nt6_refrigerator_vintage_closed_02": "Vintage fridge",
    "p9_nt6_chair_wood": "Wooden chair",
    "p9_nt6_barricade_tire_01": "Tire barricade",
    "p9_nt6x_win_snowman": "Snowman",
    "p9_mal_arcade_cabinet_08": "Arcade cabinet",
    "p9_mal_rocket_ride_01": "Kiddie rocket ride",
    "p9_mal_scissor_lift_01": "Scissor lift",
    "p9_mal_bean_bag_chair_sml": "Bean bag",
    "p9_rus_amk_telephonebooth_01_closed_v2_wet": "Phone booth",
    "p9_rus_bench_park_long": "Long park bench",
    "p9_rus_oil_drum_01": "Oil drum",
    "p9_rus_computer_server_02": "Computer server",
    "p9_ger_kgb_mount_barrier_concrete_144": "Concrete barrier 144",
    "p9_ger_tank_barrel_metal_01": "Metal barrel",
    "p9_ger_tank_gas_pump_01": "Gas pump",
    "p9_lat_sandbag_cover_02_grime": "Sandbag cover",
    "p9_lat_hedgehog_metal_snow": "Czech hedgehog",
    "p9_usa_large_ammo_crate_01": "Large ammo crate",
    "p9_rm_zoo_hay_bale_sqr": "Hay bale",
    "p9_rm_pai_wooden_spool": "Wooden spool",
    "p9_rm_rai_water_cooler_metal_full": "Water cooler",
    "p9_foliage_tree_palm_coconut_lrg_01": "Palm tree",
    "p9_pot_of_gold_pristine": "Pot of gold",
    "p9_wz_dirty_bomb_01": "Dirty bomb",
    "p9_m114_155mm_artillery_gun_01_pickup": "155mm artillery gun",
    "p9_dogtags_adler_enemy": "Dog tags (enemy)",
    "p9_dogtags_adler_friendly": "Dog tags (friendly)",
}

# The in-game menu's DEFAULT favourites when the app has set none: the curated scenery slice, by
# model. Resolved to prop_master indices at build; anything not resident on a map is skipped there.
DEFAULT_FAVS = [m for m in CURATED]


def zone_props(dump: str, zone: str) -> set[str]:
    """The prop-family xmodel names a zone manifest declares. Names are `#`-prefixed in the file."""
    out: set[str] = set()
    path = os.path.join(dump, "tables", "data", "assets", zone + ".csv")
    try:
        f = open(path, encoding="utf-8", errors="ignore")
    except OSError:
        return out
    with f:
        for line in f:
            row = line.rstrip("\n")
            c = row.find(",")
            if c < 0:
                continue
            if row[:c] != "xmodel":
                continue
            name = row[c + 1:].lstrip("#").strip()
            low = name.lower()
            if low.startswith(FAMILIES) and (not EXCLUDE_RE.search(low) or low in EXCLUDE_KEEP):
                out.add(name)
    return out


def is_barrel(model: str) -> bool:
    return bool(BARREL_RE.search(model)) and not BARREL_NO.search(model)


def humanize(model: str) -> str:
    """p9_usa_vending_machine_soda_02 -> 'Vending machine soda 02'. Strip family + a leading region."""
    s = model
    for fam in FAMILIES:
        if s.lower().startswith(fam):
            s = s[len(fam):]
            break
    parts = s.split("_")
    # drop up to two leading region/theme tokens (usa, rm_rai, sm_gas, ...)
    while len(parts) > 1 and parts[0].lower() in REGION:
        parts.pop(0)
    label = " ".join(parts).strip()
    if not label:
        label = model
    return label[:1].upper() + label[1:]


def label_for(model: str) -> str:
    return CURATED.get(model, humanize(model))


def build(dump: str):
    universal: set[str] = set()
    for z in COMMON_ZONES:
        universal |= zone_props(dump, z)

    uni_sorted = sorted(universal)
    uni = [
        {"i": i, "model": m, "label": label_for(m), "barrel": is_barrel(m)}
        for i, m in enumerate(uni_sorted)
    ]

    # Per-map: the map zone's own props MINUS the universal set (what that map uniquely adds).
    maps: dict[str, list] = {}
    zone_files = sorted(glob.glob(os.path.join(dump, "tables", "data", "assets", "mp_*.csv")))
    zone_files += sorted(glob.glob(os.path.join(dump, "tables", "data", "assets", "wz_*.csv")))
    for zf in zone_files:
        zone = os.path.splitext(os.path.basename(zf))[0]
        if zone in COMMON_ZONES:
            continue
        own = zone_props(dump, zone) - universal
        if not own:
            continue
        rows = [
            {"model": m, "label": label_for(m), "barrel": is_barrel(m)}
            for m in sorted(own)
        ]
        maps[zone] = rows

    return uni, maps


def emit_json(uni, maps) -> str:
    doc = {
        "generated": date.today().isoformat(),
        "note": "Spawnable prop catalog for the gf panel. universal[] index == GSC prop_master() "
                "index == cmd_propidx arg. Per-map models spawn via cmd_propname (chunked name). "
                "barrel==true -> spawn as explosive via cmd_barrelidx / cmd_barrelname.",
        "universal_count": len(uni),
        "universal": uni,
        "maps": maps,
    }
    return json.dumps(doc, indent=1, ensure_ascii=False)


def gsc_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def emit_gsc(uni) -> str:
    """prop_master(): the universal 338 as an indexed array, cached on level. Stable order = the JSON
    universal[] order = cmd_propidx arg. Barrels flagged with the 4th pm() arg."""
    out = [BEGIN]
    out.append(f"// GENERATED by tools/props-gen.py from the T9 dump - DO NOT EDIT BY HAND. {len(uni)} universal props.")
    out.append("// prop_master()[i] == docs/data/map-props.json universal[i] == the app's cmd_propidx arg.")
    out.append("function private prop_master()")
    out.append("{")
    out.append("    if ( isdefined( level.gf_prop_master ) )")
    out.append("        return level.gf_prop_master;")
    out.append("")
    out.append("    m = [];")
    for r in uni:
        model = gsc_escape(r["model"])
        label = gsc_escape(r["label"])
        b = "1" if r["barrel"] else "0"
        out.append(f'    m = pm( m, "{model}", "{label}", {b} );')
    out.append("    level.gf_prop_master = m;")
    out.append("    return m;")
    out.append("}")
    out.append(END)
    return "\n".join(out)


def splice(src: str, block: str) -> str:
    a = src.find(BEGIN)
    b = src.find(END)
    if a < 0 or b < 0:
        raise SystemExit(f"markers not found in {GSC}: put '{BEGIN}' and '{END}' lines where the block goes")
    b_end = b + len(END)
    nl = "\r\n" if "\r\n" in src else "\n"
    return src[:a] + block.replace("\n", nl) + src[b_end:]


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--check"]
    check = "--check" in sys.argv
    dump = args[0] if args else DEFAULT_DUMP
    if not os.path.isdir(dump):
        raise SystemExit(f"dump not found: {dump}")

    uni, maps = build(dump)
    barrels = [r for r in uni if r["barrel"]]
    print(f"universal props: {len(uni)}  (barrels: {len(barrels)})")
    print(f"maps with own props: {len(maps)}  "
          f"(e.g. mp_miami: {len(maps.get('mp_miami', []))}, mp_cartel: {len(maps.get('mp_cartel', []))})")
    print("universal barrels:", ", ".join(r["model"] for r in barrels))

    json_text = emit_json(uni, maps)
    gsc_block = emit_gsc(uni)

    if check:
        cur_json = open(OUT_JSON, encoding="utf-8").read() if os.path.exists(OUT_JSON) else ""
        cur_gsc = open(GSC, encoding="utf-8", newline="").read() if os.path.exists(GSC) else ""
        stale = (cur_json.strip() != json_text.strip()) or (BEGIN in cur_gsc and splice(cur_gsc, gsc_block) != cur_gsc)
        print("STALE - run tools/props-gen.py" if stale else "up to date")
        return 1 if stale else 0

    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as f:
        f.write(json_text)
        f.write("\n")
    print(f"wrote {OUT_JSON}")

    if os.path.exists(GSC) and BEGIN in open(GSC, encoding="utf-8", newline="").read():
        src = open(GSC, encoding="utf-8", newline="").read()
        new = splice(src, gsc_block)
        with open(GSC, "w", encoding="utf-8", newline="") as f:
            f.write(new)
        print(f"rewrote the props-gen block in {GSC}")
    else:
        print(f"NOTE: markers not in {GSC} yet - JSON written; add the block by hand or the markers first")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
