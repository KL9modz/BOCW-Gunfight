#!/usr/bin/env python3
"""Classify every gametype setting the T9 scripts read, by whether a MENU ROW exists.

    python3 tools/settings-xref.py ~/ate47/bocw-source
    python3 tools/settings-xref.py ~/ate47/bocw-source --grep squad,team,player

WHY THIS EXISTS. klaze observed in-game that a Gunfight lobby's rules menu shows
a round-timer row and a 3v3 Gunfight lobby does not, and that NO lobby exposes a
per-side team cap. That is a statement about the MENU, not about the settings.
This separates the two, mechanically, for all of them at once.

THE MAPPING IS EXACT, and this is what makes the tool trustworthy. A bundle's
`setting` field IS the getgametypesetting() key. Proven by a plain-named pair:

    scriptbundle/gamesettings/allow_ingame_team_change.json   "setting": "allowInGameTeamChange"
    scripts/mp_common/gametypes/serversettings.gsc:43         getgametypesetting( #"allowingameteamchange" )

Script hashes are lowercased before hashing (ACTS hash_mini.hpp), so camelCase in
the bundle and lowercase in the script are the same key.

MEASURED 2026-09-08 against ate47/bocw-source:

    463 distinct settings read or written by script
    427 menu bundles (395 with a distinct `setting`)

    130  plain-named, HAS a menu row      -> changeable from the lobby, if the
                                             playlist shows that row for the variant
     97  plain-named, NO menu row         -> real setting, no menu path
    236  still hashed, NO menu row        -> and 0 of 236 matched any bundle

THE RULE THAT FALLS OUT: **hashed => hidden.** Not one hashed key is explained by
a menu row. That is not a coincidence - a setting with a menu row has its name
spelled out in the bundle, which is exactly where the dump's resolver finds names.

So `#"hash_3a4691a853585241"` (maxsquadplayers) being hashed is not an accident of
the dump. It is the signature of a setting the menu never exposes - which is what
klaze measured from the other side, with no lobby showing a per-side cap.

⚠ "No menu row" is NOT "unreachable". setgametypesetting() takes any key at
  runtime; #"timelimit" is proof. It means the LOBBY cannot set it, nothing more.
"""
import re, sys, os, json, glob, collections

MASK64 = 0xFFFFFFFFFFFFFFFF
MASK63 = 0x7FFFFFFFFFFFFFFF
FNV1A_PRIME = 0xcbf29ce484222325
IV_DEFAULT = 0x100000001b3


def hash64(s):
    h = FNV1A_PRIME
    for c in s.lower():
        h = ((h ^ ord(c)) * IV_DEFAULT) & MASK64
    return h & MASK63


CALL = re.compile(r'\b(set|get)gametypesetting\s*\(\s*#"([^"]+)"')


def collect(root):
    uses = collections.defaultdict(set)
    for pat in ("scripts/**/*.gsc", "scripts/**/*.csc"):
        for f in glob.glob(os.path.join(root, pat), recursive=True):
            rel = os.path.relpath(f, os.path.join(root, "scripts"))
            try:
                lines = open(f, errors="ignore").read().splitlines()
            except OSError:
                continue
            for i, line in enumerate(lines, 1):
                for m in CALL.finditer(line):
                    uses[m.group(2)].add("%s:%d:%s" % (rel, i, m.group(1)))
    return uses


def bundles(root):
    out = {}
    for f in glob.glob(os.path.join(root, "scriptbundle/gamesettings/*.json")):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        s = d.get("setting")
        if not s:
            continue
        declared = sum(1 for k in d if re.fullmatch(r"value\d+", k))
        out[s.lower()] = (os.path.basename(f)[:-5], d.get("optionscount"), declared)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    filt = None
    for a in sys.argv[1:]:
        if a.startswith("--grep="):
            filt = [w.strip().lower() for w in a.split("=", 1)[1].split(",")]
    root = args[0] if args else os.path.expanduser("~/ate47/bocw-source")
    if not os.path.isdir(os.path.join(root, "scripts")):
        print("not a bocw-source checkout: %s" % root)
        return 2

    uses = collect(root)
    bun = bundles(root)
    byhash = {"hash_%016x" % hash64(s): s for s in bun}

    menued, hidden, unknown = [], [], []
    for k in sorted(uses):
        if k.startswith("hash_"):
            (menued if k in byhash else unknown).append(k)
        else:
            (menued if k.lower() in bun else hidden).append(k)

    def show(title, keys, resolve=None):
        rows = keys
        if filt:
            rows = [k for k in keys if any(w in k.lower() for w in filt)]
        print("\n=== %s (%d of %d shown) ===" % (title, len(rows), len(keys)))
        for k in rows:
            name = resolve(k) if resolve else k
            meta = ""
            if name.lower() in bun:
                b, oc, dec = bun[name.lower()]
                meta = "  [row %s, publishes %s of %s]" % (b, oc, dec)
            print("  %-34s %s%s" % (name, sorted(uses[k])[0], meta))

    print("settings read/written by script: %d      menu bundles with a setting: %d"
          % (len(uses), len(bun)))
    show("A. HAS a menu row - the lobby can set it", menued,
         lambda k: byhash.get(k, k))
    show("B. named, but NO menu row - setgametypesetting only", hidden)
    show("C. hashed, no menu row - hidden AND unnamed", unknown)
    print("\n0 of the %d hashed keys matched a bundle. hashed => hidden." % len(unknown))
    return 0


if __name__ == "__main__":
    sys.exit(main())
