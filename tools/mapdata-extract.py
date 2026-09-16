#!/usr/bin/env python3
"""mapdata-extract.py - the per-map asset table, read OFFLINE out of the T9 dump. READ-ONLY.

    python tools/mapdata-extract.py                      # dump at ../bocw-source-main
    python tools/mapdata-extract.py /c/path/to/dump      # or say where it is
    python tools/mapdata-extract.py --md                 # also print the markdown table

Writes docs/data/map-assets.json next to the repo's notes.

WHY THIS EXISTS. docs/notes/vehicles.md §3 said "the dump cannot answer which maps carry which
vehicles: map .ff contents are not in it". That was wrong by one directory: the dump ships
`tables/bgcache/<zone>.csv` (the bgcache = every asset a zone precaches, one `type,name` row
each) and `tables/data/assets/<zone>.csv` (the zone's full asset manifest). Under MP a map runs
with core_bootstrap + core_common + mp_common + its own zone loaded, so the union of their
`vehicle` rows is the set `isassetloaded( "vehicle", name )` says yes to. MEASURED 2026-09-15:
Standoff's in-game census (gf_dbg_assets) found exactly the four streak vehicles this union
predicts and nothing else. Hashed rows (`#hash_...`) are FNV1a64-masked names the dump could not
resolve; the ones this script names were cracked against vehicle-name vocabulary or found by
their call sites (scriptbundle/scene = the map's intro cinematic vehicle). Unresolved hashes
are still USABLE: `spawnvehicle( #"hash_..." )` is stock syntax (vip.gsc:125).

Props: the Prop Hunt tables (`gamedata/tables/mp/<map>_ph.csv`, docs/notes/static-props.md) are
NOT in the dump; the in-game PROPS census is their only source. What the manifest gives per map
is the resident xmodel pool (the `p9_/p8_/p7_` prop families) - counted here, listed on request.
"""
from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter, OrderedDict
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEFAULT_DUMP = os.path.join(os.path.dirname(REPO), "bocw-source-main")
OUT_JSON = os.path.join(REPO, "docs", "data", "map-assets.json")

# Zones every MP map runs with (the map's own zone is added per map).
COMMON_ZONES = ["core_bootstrap", "core_common", "mp_common"]

# Display names as the menu's Map page spells them (gunfight_menu.gsc map_6v6/map_gf/map_ft rows).
DISPLAY = {
    "mp_amerika": "Amerika", "mp_apocalypse": "Apocalypse", "mp_black_sea": "Armada",
    "mp_cartel": "Cartel", "mp_cliffhanger": "Yamantau", "mp_drivein_rm": "Drive-In",
    "mp_dune": "Collateral", "mp_echelon": "Echelon", "mp_express_rm": "Express",
    "mp_firebase": "Deprogram", "mp_hijacked_rm": "Hijacked", "mp_jungle_rm": "Jungle",
    "mp_kgb": "Checkmate", "mp_mall": "The Pines", "mp_miami": "Miami", "mp_miami_strike": "Miami Strike",
    "mp_moscow": "Moscow", "mp_nuketown6": "Nuketown '84", "mp_paintball_rm": "Rush", "mp_raid_rm": "Raid",
    "mp_russianbase_rm": "WMD", "mp_satellite": "Satellite", "mp_slums_rm": "Slums",
    "mp_sm_amsterdam": "Amsterdam (Gunfight)", "mp_sm_berlin_tunnel": "U-Bahn (Gunfight)",
    "mp_sm_central": "ICBM (Gunfight)", "mp_sm_deptstore": "Showroom (Gunfight)",
    "mp_sm_finance": "KGB (Gunfight)", "mp_sm_game_show": "Game Show (Gunfight)",
    "mp_sm_gas_station": "Diesel (Gunfight / 6v6)", "mp_sm_market": "Mansion (Gunfight)",
    "mp_sm_vault": "Gluboko (Gunfight)", "mp_tank": "Garrison", "mp_tundra": "Crossroads",
    "mp_village_rm": "Standoff", "mp_zoo_rm": "Zoo",
    "wz_doa": "Fireteam zone: doa", "wz_duga": "Fireteam: Duga", "wz_forest": "Fireteam: Ruka",
    "wz_golova": "Fireteam: Golova", "wz_sanatorium": "Fireteam: Sanatorium",
    "wz_ski_slopes": "Fireteam: Alpine", "wz_zoo": "Fireteam zone: zoo",
}

# Hashed vehicle names resolved so far (FNV1a64 & MASK63 of the lowercase name == the hash),
# plus the ones identified by their call site. `label` is for the menu; `kind` sorts the page.
#   drive    - a player-drivable Fireteam / Combined Arms vehicle
#   streak   - scorestreak / support vehicle (spawns, may not be enterable)
#   turret   - manned MG tripod
#   intro    - the map's pre-match cinematic vehicle (scriptbundle/scene/cin_mp_<map>_intro_*)
#   scene    - other cinematic vehicle
#   system   - engine / placeholder (never offer)
NAMED = {
    # cracked
    "437293ae239af1ab": ("exfil helicopter (Fireteam)", "streak"),        # zm_silver_main_quest.gsc:3031 "exfil_heli"
    "3effd1dd89ee3d36": ("Fireteam reinsertion vehicle", "system"),       # script_718a1198c1574851.gsc:234
    "58cc8ce25d32031f": ("exfil chopper (VIP escort)", "streak"),         # vip.gsc:125 exfil_chopper_vehicle
    "4209c5ff3b969c7a": ("vehicle_t9_mil_ru_heli_transport_vehicle_drop", "streak"),
    "28d512b739c9d9c1": ("vehicle_t9_mil_ru_tank_t72", "drive"),
    "6595f5efe62a4ec": ("vehicle_t9_mil_ru_heli_gunship_hind", "drive"),
    "1a60a087a340574b": ("vehicle_t9_mil_ru_apc_heavy", "drive"),
    "7c54a264a26cb1eb": ("vehicle_t9_mil_ru_apc_heavy_open_turret", "drive"),
    "1bdb534f1e8e23f5": ("vehicle_t9_mil_ru_truck_light", "drive"),
    "4b89aa566bff8383": ("vehicle_motorcycle_mil_us_offroad_slow", "drive"),
    "51c4f4dc2591b475": ("vehicle_boct_mil_boat_tactical_raft_gry", "drive"),
    "536eec4bf6424551": ("veh_boct_turret_manned_tripod_mp", "turret"),
    "2fc8835276d8b7a4": ("veh_boct_turret_manned_tripod_span_up_15_down_14_mp", "turret"),
    "3665b873bf14aff4": ("veh_boct_turret_manned_tripod_span_up_15_down_5_mp", "turret"),
    "101e80cf4fc32645": ("veh_boct_turret_manned_tripod_span_lr_75_down_18_mp", "turret"),
    "6a3338f16c953a89": ("veh_boct_turret_manned_tripod_span_lr_75_down_14_mp", "turret"),
    "edcdd6027aeb112": ("veh_boct_turret_manned_tripod_span_lr_47_down_14_mp", "turret"),
    "fae102f13c58e9e": ("veh_boct_turret_manned_tripod_span_lr_47_down_5_mp", "turret"),
    "7bf9ca71584bd31d": ("veh_boct_turret_manned_tripod_safe_exit_tag_enter_driver_mp", "turret"),
    "5477254cf96259f4": ("veh_boct_train", "system"),
    "2a439b0890fe07d8": ("vehicle_t9_mil_ru_heli_transport_zm_platinum", "scene"),
    "d57fa1b1aacffc7": ("veh_ultimate_turret_zm", "system"),
    "985b7e40ee02aa2": ("vehicle_t8_soviet_civ_sedan_midsize", "drive"),
    # by call site: the map's intro cinematic vehicle (scriptbundle/scene/cin_mp_<map>_intro_*)
    "60868aaa45d05ffe": ("intro cinematic vehicle (Checkmate hva / Satellite)", "intro"),
    "550d303ee2de9a65": ("intro cinematic tank (Garrison / Amerika)", "intro"),
    "4dfaa11717f3881": ("intro cinematic vehicle (Garrison hva)", "intro"),
    "1e00d92ee0b1bf4c": ("intro cinematic vehicle (Miami cia)", "intro"),
    "4c21aec4081d030d": ("intro cinematic vehicle (Moscow cia)", "intro"),
    "62d385495a2ba813": ("intro cinematic vehicle (Moscow kgb)", "intro"),
    "13c60e71eef46ebb": ("intro cinematic helicopter (The Pines)", "intro"),
    "5405b8cdc93df2b4": ("intro cinematic APC (The Pines)", "intro"),
    "15e59336c36ee995": ("intro cinematic APC (Amerika)", "intro"),
    "7c74af55b6caaaf5": ("intro cinematic vehicle (Echelon cia)", "intro"),
    "c07fec522db452c": ("intro cinematic vehicle (Yamantau cia)", "intro"),
    "1c5963188cf189df": ("intro cinematic vehicle (Apocalypse cia)", "intro"),
    "20966d639ebe6604": ("intro cinematic vehicle (Cartel north)", "intro"),
    "4bfd80fe09072db3": ("intro cinematic vehicle (Collateral cia)", "intro"),
    "3efa223f4a0bffcd": ("intro cinematic vehicle (Collateral kgb)", "intro"),
    "1f5c1aa7b1348d33": ("intro cinematic vehicle (Crossroads kgb)", "intro"),
    "3463002d802c1a98": ("intro cinematic vehicle (Crossroads)", "intro"),
    "581bb1b0fa4a3139": ("intro cinematic vehicle (Crossroads kgb 2)", "intro"),
    "61b8f8f61f4b9ce7": ("intro cinematic vehicle (Crossroads cia)", "intro"),
    "631691623ad368bd": ("campaign outro cinematic vehicle (hpc/sl)", "scene"),
    "3d2bbfdb89093d91": ("campaign intro cinematic vehicle (hpc)", "scene"),
}

PLAIN_KIND = [
    (re.compile(r"^(defaultvehicle_mp|fake_vehicle|heli_ai_mp|misc_camera|spawner_zombietron.*|veh_missile_turret|veh_ultimate_turret.*|vehicle_straferun_mp)$"), "system"),
    (re.compile(r"^(veh_t8_ac130_gunship_mp|veh_t8_helicopter_gunship_mp.*|veh_t9_mil_us_helicopter_large_chopper_gunner|vehicle_t9_mil_helicopter_care_package|vehicle_t9_mil_ru_air_vtol_forger|vehicle_t9_rcxd_racing.*|vehicle_t9_mil_ru_heli_transport_vehicle_drop)$"), "streak"),
    (re.compile(r"^veh_boct_turret_"), "turret"),
    (re.compile(r"^veh_boct_train$"), "system"),
    (re.compile(r"_intro$"), "scene"),
]


def kind_of(name: str) -> str:
    for rx, k in PLAIN_KIND:
        if rx.search(name):
            return k
    return "drive"


def read_rows(path: str, want_type: str) -> list[str]:
    out: list[str] = []
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or "," not in line:
                continue
            t, _, name = line.partition(",")
            if t == want_type and name.startswith("#"):
                out.append(name[1:])
    return out


def vehicle_entry(raw: str) -> dict:
    if raw.startswith("hash_"):
        hx = raw[5:]
        label, kind = NAMED.get(hx, (f"unresolved vehicle #{hx}", "unknown"))
        return {"key": raw, "label": label, "kind": kind, "hashed": True}
    return {"key": raw, "label": raw, "kind": kind_of(raw), "hashed": False}


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dump = os.path.abspath(args[0]) if args else DEFAULT_DUMP
    bg = os.path.join(dump, "tables", "bgcache")
    manifest = os.path.join(dump, "tables", "data", "assets")
    if not os.path.isdir(bg):
        sys.exit(f"no bgcache tables under {dump}")

    common_veh: list[str] = []
    for z in COMMON_ZONES:
        for v in read_rows(os.path.join(bg, z + ".csv"), "vehicle"):
            if v not in common_veh:
                common_veh.append(v)

    zones = sorted(fn[:-4] for fn in os.listdir(bg)
                   if fn.endswith(".csv") and (fn.startswith("mp_") or fn.startswith("wz_")) and fn != "mp_common.csv")
    maps: "OrderedDict[str, dict]" = OrderedDict()
    for z in zones:
        own = read_rows(os.path.join(bg, z + ".csv"), "vehicle")
        entry = {
            "display": DISPLAY.get(z, z),
            "vehicles_own": [vehicle_entry(v) for v in own],
            "vehicles_resident": [vehicle_entry(v) for v in common_veh + [v for v in own if v not in common_veh]],
        }
        man = os.path.join(manifest, z + ".csv")
        if os.path.exists(man):
            xm = read_rows(man, "xmodel")
            fam = Counter()
            for x in xm:
                m = re.match(r"^(p[0-9]+_[a-z0-9]+)_", x)
                if m:
                    fam[m.group(1)] += 1
            entry["xmodels"] = len(xm)
            entry["xmodels_hashed"] = sum(1 for x in xm if x.startswith("hash_"))
            entry["prop_models"] = sum(1 for x in xm if re.match(r"^p[0-9]+_", x))
            entry["vehicle_models"] = sum(1 for x in xm if x.startswith("veh"))
            entry["prop_families_top"] = [f"{k}={n}" for k, n in fam.most_common(8)]
        maps[z] = entry

    out = {
        "generated": str(date.today()),
        "source": "bocw-source-main tables/bgcache/<zone>.csv (vehicle rows) + tables/data/assets/<zone>.csv (xmodel rows)",
        "model": "resident vehicle assets on a map = vehicle rows of core_bootstrap + core_common + mp_common + the map zone",
        "common_vehicles": [vehicle_entry(v) for v in common_veh],
        "maps": maps,
    }
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print(f"wrote {OUT_JSON}: {len(maps)} zones, {len(common_veh)} common vehicles")

    if "--md" in sys.argv:
        print()
        print("| zone | map | own vehicle assets (kind) | prop xmodels |")
        print("|---|---|---|---|")
        for z, e in maps.items():
            own = ", ".join(f"{v['label']} ({v['kind']})" for v in e["vehicles_own"]) or "-"
            print(f"| `{z}` | {e['display']} | {own} | {e.get('prop_models', '?')} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
