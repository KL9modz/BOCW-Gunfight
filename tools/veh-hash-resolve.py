"""Vehicle asset inventory + hashed-name resolution BY CONSTRUCTION (2026-09-21).

Every zone's tables/bgcache/<zone>.csv lists its resident vehicle assets as `vehicle,#<name>`;
about half the names are FNV1a-64 hashes (`hash_<hex>`, 63-bit mask, lower-cased input - the
same hash as the script paths). The community index knows none of them (vehicles.md section 6),
but the plain names follow strict patterns, so candidates built from the xmodel table stems
(veh_* -> vehicle_*) x a suffix vocabulary (map tokens, _intro, _mp, _alt, ...) hash-match a good
share. 2026-09-21: 24 of the 56 hashed names in the mp_*/wz_*/core_* zones resolved this way
(9 of the rest belong to wz_doa, Dead Ops - not MP); docs/data/vehicle-assets.json is the output.

    python tools/veh-hash-resolve.py            # inventory + resolution table (mp_/wz_/core_ zones)
    python tools/veh-hash-resolve.py --json out.json

The dump root is C:/bocw/bocw-source-main (tables/bgcache, tables/data/assets).
"""
import glob
import json
import os
import sys

ROOT = r"C:/bocw/bocw-source-main/tables"
ZONE_PREFIXES = ("mp_", "wz_", "core_")

# hashes resolved by hand / earlier work (vehicles.md section 7 hints, veh_master comments)
KNOWN = {
    "536eec4bf6424551": "veh_boct_turret_manned_tripod_mp",
    "4b89aa566bff8383": "vehicle_motorcycle_mil_us_offroad_slow",
    "51c4f4dc2591b475": "vehicle_boct_mil_boat_tactical_raft_gry",
    "985b7e40ee02aa2": "vehicle_t8_soviet_civ_sedan_midsize",
    # found 2026-09-21 by construction from script strings / bundle hints (vehicles.md section 8)
    "4209c5ff3b969c7a": "vehicle_t9_mil_ru_heli_transport_vehicle_drop",
    "5477254cf96259f4": "veh_boct_train",
    "d57fa1b1aacffc7": "veh_ultimate_turret_zm",
    "13c60e71eef46ebb": "vehicle_t9_mil_ru_heli_transport_mp_mall_intro",
    "4dfaa11717f3881": "vehicle_t9_mil_ru_heli_transport_mp_tank_intro",
    "c07fec522db452c": "vehicle_t9_mil_ru_heli_transport_mp_cliffhanger_intro",
    "4c21aec4081d030d": "vehicle_civ_eu_van_kgb_moscow",
}


def fnv1a64(s):
    h = 0xCBF29CE484222325
    for ch in s.lower().encode():
        h ^= ch
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h & 0x7FFFFFFFFFFFFFFF


def load_inventory():
    names, where = set(), {}
    for f in glob.glob(os.path.join(ROOT, "bgcache", "*.csv")):
        zone = os.path.basename(f)[:-4]
        if not zone.startswith(ZONE_PREFIXES):
            continue
        for line in open(f, encoding="utf-8", errors="replace"):
            if line.startswith("vehicle,"):
                n = line.strip().split(",")[1].lstrip("#")
                names.add(n)
                where.setdefault(n, set()).add(zone)
    return names, where


def xmodel_stems():
    xm = set()
    for f in glob.glob(os.path.join(ROOT, "data", "assets", "*.csv")):
        for line in open(f, encoding="utf-8", errors="replace"):
            if line.startswith("xmodel,#veh"):
                xm.add(line.strip().split(",")[1].lstrip("#"))
    # quoted vehicle-ish strings in the scripts are stems too (spawnvehicle args, spawner names)
    import re
    for f in glob.glob(os.path.join(os.path.dirname(ROOT), "scripts", "**", "*.gsc"), recursive=True):
        t = open(f, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r'"((?:vehicle|veh|heli|spawner)[a-z0-9_]*)"', t):
            xm.add(m.group(1))
    stems = set()
    for x in xm:
        parts = x.split("_")
        for k in range(2, len(parts) + 1):
            st = "_".join(parts[:k])
            stems.add(st)
            if st.startswith("veh_"):
                stems.add("vehicle_" + st[4:])
    return stems


def map_tokens():
    toks = set()
    for f in glob.glob(os.path.join(ROOT, "bgcache", "*.csv")):
        zone = os.path.basename(f)[:-4]
        if zone.startswith(("mp_", "wz_")):
            toks.add(zone)
            for t in zone.split("_"):
                if t not in ("mp", "sm", "wz") and len(t) > 2:
                    toks.add(t)
    toks |= {"miami", "moscow", "satellite", "checkmate", "garrison", "amerika", "echelon", "pines", "cartel",
             "crossroads", "armada", "nuketown", "raid", "express", "standoff", "hijacked", "kgb", "cia", "tank",
             "black_sea", "tundra", "duga", "golova", "sanatorium", "alpine", "apocalypse", "amsterdam",
             "collateral", "yamantau", "showroom", "paintball", "zoo", "slums", "rush", "firebase", "drivein",
             "gas_station", "vault", "deptstore", "market", "game_show", "finance", "berlin", "ruka", "forest",
             "perseus", "winter", "snow", "wet", "night", "vista", "dune", "mall", "cliffhanger", "fireteam"}
    return toks


def suffixes():
    suf = {"", "_player", "_alt", "_mp", "_sr", "_pc", "_player_alt", "_obj_sr", "_wz", "_cp", "_zm", "_mp_alt",
           "_ai", "_ai_mp", "_wz_pc", "_low", "_static", "_intro", "_cine", "_cinematic", "_intro_mp",
           "_mp_intro", "_flight", "_gear", "_slow", "_gry", "_dead", "_destroyed", "_prop_hunt", "_ph"}
    for m in map_tokens():
        suf |= {"_" + m, "_mp_" + m, "_" + m + "_mp", "_" + m + "_intro", "_intro_" + m, "_" + m + "_static",
                "_mp_" + m + "_intro", "_kgb_" + m, "_" + m + "_kgb"}
    return suf


def resolve(hashed):
    hits = {h: n for h, n in KNOWN.items() if h in hashed}
    target = set(hashed) - set(hits)
    stems, suf = xmodel_stems(), suffixes()
    for st in stems:
        for sf in suf:
            c = st + sf
            h = "%x" % fnv1a64(c)
            if h in target:
                hits[h] = c
                target.discard(h)
    return hits


def main():
    names, where = load_inventory()
    hashed = {n[5:]: n for n in names if n.startswith("hash_")}
    hits = resolve(hashed)
    plain = sorted(n for n in names if not n.startswith("hash_"))
    rows = []
    for n in plain:
        rows.append({"name": n, "hashed": False, "zones": sorted(where[n])})
    for h in sorted(hashed):
        rows.append({"name": hashed[h], "hashed": True, "resolved": hits.get(h), "zones": sorted(where[hashed[h]])})
    print("vehicle assets in %s zones: %d plain + %d hashed (%d resolved)" % (
        "/".join(ZONE_PREFIXES), len(plain), len(hashed), len(hits)))
    for r in rows:
        tag = r["name"] if not r["hashed"] else "%s = %s" % (r["name"], r["resolved"] or "?")
        print("  %-75s %s" % (tag, ",".join(r["zones"])[:60]))
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        json.dump({"generated": "2026-09-21", "source": "tables/bgcache vehicle rows; hashes resolved by FNV1a construction",
                   "assets": rows}, open(out, "w"), indent=1)
        print("wrote", out)


if __name__ == "__main__":
    main()
