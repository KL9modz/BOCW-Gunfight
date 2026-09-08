#!/usr/bin/env python3
"""Recover the NAME behind a T9 script hash, by generating candidates and hashing them.

    python3 tools/crack-hash.py 3a4691a853585241
    python3 tools/crack-hash.py hash_3a4691a853585241 --words extra1,extra2
    python3 tools/crack-hash.py --hash maxsquadplayers        # forward direction

WHY THIS EXISTS. `.claude/CLAUDE.md` lists the FNV1a64 hashing of the BOCW front
end under confirmed dead ends - "the FNV1a64 wall". That is correct for arbitrary
data. It is NOT correct for a GUESSABLE name: the hash is not salted, so any name
you can think of can be tested in microseconds, and a 63-bit match is proof.

This cracked `getgametypesetting(#"hash_3a4691a853585241")` at globallogic.gsc:230
to **maxsquadplayers** on the first wordlist. See docs/notes/dump-cross-check.md.

⚠ IT ONLY WORKS ON NAMES YOU CAN GUESS. A miss means your wordlist was wrong, not
  that the algorithm is wrong and not that the hash is unbreakable. Report misses
  as "not found with N candidates", never as "unresolvable".

ALGORITHM, from ate47/atian-cod-tools src/core/shared/utils/hash_mini.hpp:
    Hash64(str) = Hash64A(str, FNV1A_PRIME, IV_DEFAULT) & MASK63
    Hash64A: h = start; for c in lower(str): h = (h ^ c) * iv
    FNV1A_PRIME 0xcbf29ce484222325 · IV_DEFAULT 0x100000001b3 · MASK63 63 bits
"""
import itertools, sys

MASK64 = 0xFFFFFFFFFFFFFFFF
MASK63 = 0x7FFFFFFFFFFFFFFF
FNV1A_PRIME = 0xcbf29ce484222325
IV_DEFAULT = 0x100000001b3


def hash64(s):
    h = FNV1A_PRIME
    for c in s.lower():
        h = ((h ^ ord(c)) * IV_DEFAULT) & MASK64
    return h & MASK63


# Vocabulary skewed to gametype-settings and team/lobby field names, which is
# where this project's unresolved hashes live.
HEADS = ["", "max", "min", "num", "use", "show", "allow", "enable", "is", "has", "default"]
STEMS = ["team", "teams", "squad", "party", "player", "players", "client", "clients",
         "round", "rounds", "score", "time", "life", "lives", "spawn", "spawns",
         "zone", "zones", "flag", "objective", "respawn", "overtime", "extratime",
         "gunfight", "control", "dom", "hardpoint", "loadout", "class", "bot", "bots",
         "spectator", "spectators", "map", "gametype", "playlist", "lobby", "match"]
TAILS = ["", "s", "count", "size", "limit", "max", "min", "players", "player", "time",
         "enabled", "allowed", "delay", "num", "perteam", "per_team", "alive", "index"]


def candidates(extra):
    seen = set()
    for h, s, t, sep in itertools.product(HEADS, STEMS, TAILS, ["", "_"]):
        w = (h + sep if h else "") + s + (sep + t if t else "")
        if w and w not in seen:
            seen.add(w)
            yield w
    for w in extra:
        if w and w not in seen:
            seen.add(w)
            yield w


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    extra = []
    forward = False
    for a in sys.argv[1:]:
        if a.startswith("--words="):
            extra = [w.strip() for w in a.split("=", 1)[1].split(",")]
        elif a == "--hash":
            forward = True
    if not args:
        print(__doc__)
        return 2

    if forward:
        for name in args:
            print("%-32s %016x" % (name, hash64(name)))
        return 0

    rc = 0
    for raw in args:
        t = raw.lower().removeprefix("hash_").removeprefix("0x")
        try:
            target = int(t, 16) & MASK63
        except ValueError:
            print("not a hex hash: %s" % raw)
            rc = 2
            continue
        n = 0
        found = []
        for w in candidates(extra):
            n += 1
            if hash64(w) == target:
                found.append(w)
        if found:
            print("%016x  ->  %s" % (target, ", ".join(found)))
            print("            exact 63-bit match; a collision here is not a realistic possibility")
        else:
            print("%016x  ->  NOT FOUND in %d candidates" % (target, n))
            print("            That means the wordlist was wrong. It does NOT mean the")
            print("            hash is unresolvable - add guesses with --words=a,b,c")
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
