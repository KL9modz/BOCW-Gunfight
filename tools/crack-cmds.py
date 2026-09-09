#!/usr/bin/env python3
"""Recover console-command NAMES from `acts dcfuncscw`'s hashed output.

    acts dcfuncscw                      # on the test box, game running, in the lobby
    python3 tools/crack-cmds.py cfuncs_cw.csv
    python3 tools/crack-cmds.py cfuncs_cw.csv --words=setlobbymap,uisetmap
    python3 tools/crack-cmds.py --hash map_restart          # forward direction

WHY THIS EXISTS. `acts dcfuncscw` walks the game's console-command linked list
(`cmd_function_t` from a hardcoded base) and writes location,name,func - but the
NAME column is a hash. That list is the definitive answer to "is there a command
that sets the lobby's map", which is the one thing standing between us and a
one-line DLL for Gunfight-on-any-map. See docs/notes/lobby-map-dll.md.

SAME ALGORITHM as tools/crack-hash.py - FNV1a64, lowercased, & MASK63. This tool
adds a COMMAND-SHAPED vocabulary instead of a gametype-settings one, because
that is the whole game: the names that crack are the ones you can guess, and
console commands are named nothing like gametype settings.

⚠ It also tries the UNMASKED 64-bit form. tools/crack-hash.py does not, because
  every hash it targets came out of GSC where the mask is certain. Here the hash
  comes from an engine struct read out of process memory, and unlock-dlls.md
  already records one place the two forms differ:
      acts h64 loot_fakeall  -> 60cdc482a7d159f8   (masked)
      raw FNV-1a 64          -> e0cdc482a7d159f8
  Guessing wrong about the mask would read as "the wordlist was wrong", which is
  the one failure mode this project keeps having to walk back.

⚠ A MISS MEANS THE WORDLIST WAS WRONG. It does not mean the command is absent -
  report it as "not found with N candidates" and add guesses with --words.
"""
import csv, itertools, os, sys

MASK64 = 0xFFFFFFFFFFFFFFFF
MASK63 = 0x7FFFFFFFFFFFFFFF
FNV1A_PRIME = 0xcbf29ce484222325
IV_DEFAULT = 0x100000001b3


def fnv(s):
    h = FNV1A_PRIME
    for c in s.lower():
        h = ((h ^ ord(c)) * IV_DEFAULT) & MASK64
    return h


# Console commands, not gametype settings. Quake-lineage verbs plus the
# BOCW-specific lobby vocabulary that cwpatch already proves exists
# (lobbylaunchgame, killserver, fast_restart, full_restart are all real).
KNOWN = [
    # confirmed real in this game, from unlock-dlls.md - CONTROLS for the run.
    # If none of these five crack, the hash form is wrong, not the wordlist.
    "lobbylaunchgame", "killserver", "fast_restart", "full_restart", "map_restart",
    # quake lineage
    "map", "devmap", "connect", "disconnect", "reconnect", "quit", "exec",
    "bind", "unbind", "set", "seta", "sets", "setu", "toggle", "vstr", "wait",
    "cmdlist", "dvarlist", "screenshot", "clear", "echo", "kick", "banclient",
    "status", "serverinfo", "systeminfo", "spdevmap", "loadgame", "savegame",
    "restart", "vid_restart", "snd_restart", "reset", "resetdvars",
]

HEADS = ["", "set", "get", "ui", "lobby", "host", "party", "match", "game",
         "sv", "cl", "mp", "dev", "start", "launch", "change", "select", "force"]
STEMS = ["map", "maps", "gametype", "gametypes", "mode", "playlist", "lobby",
         "match", "game", "round", "team", "teams", "player", "players", "bot",
         "bots", "client", "clients", "spectator", "caster", "rotation", "level"]
TAILS = ["", "name", "list", "index", "select", "set", "load", "start", "launch",
         "next", "restart", "change", "override", "count", "size"]


def candidates(extra):
    seen = set()
    for w in KNOWN:
        if w not in seen:
            seen.add(w)
            yield w
    for h, s, t, sep in itertools.product(HEADS, STEMS, TAILS, ["", "_"]):
        w = (h + sep if h else "") + s + (sep + t if t else "")
        if w and w not in seen:
            seen.add(w)
            yield w
    # head + TWO stems, because the shape we most want is compound:
    # setlobbymap, changegamemap, uiplaylistmap. The single-stem pass above
    # cannot reach those, and the self-test proved it by missing setlobbymap.
    for h, s1, s2, sep in itertools.product(HEADS, STEMS, STEMS, ["", "_"]):
        if s1 == s2:
            continue
        w = (h + sep if h else "") + s1 + sep + s2
        if w not in seen:
            seen.add(w)
            yield w
    for w in extra:
        w = w.strip()
        if w and w not in seen:
            seen.add(w)
            yield w


# Anything whose name contains one of these is worth a human look even if the
# rest of the dump is noise - these are the shapes that could set a lobby's map.
INTERESTING = ("map", "gametype", "playlist", "lobby", "launch", "mode")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    extra, forward = [], False
    for a in sys.argv[1:]:
        if a.startswith("--words="):
            extra = a.split("=", 1)[1].split(",")
        elif a == "--hash":
            forward = True

    if forward:
        for name in args:
            print("%-28s masked %016x   raw %016x"
                  % (name, fnv(name) & MASK63, fnv(name)))
        return 0

    if not args:
        print(__doc__)
        return 2

    path = args[0]
    if not os.path.isfile(path):
        print("no such file: %s\n\nRun `acts dcfuncscw` on the test box first, with the\n"
              "game RUNNING and sitting in the lobby you care about." % path)
        return 2

    # Build both tables once; a command list is thousands of rows and the
    # candidate set is ~30k, so hashing per row would be quadratic for nothing.
    cands = list(candidates(extra))
    masked = {}
    raw = {}
    for w in cands:
        h = fnv(w)
        masked.setdefault(h & MASK63, w)
        raw.setdefault(h, w)

    rows, hits, controls = 0, [], 0
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            val = (row.get("name") or "").strip()
            if not val:
                continue
            try:
                h = int(val, 16) if not val.isdigit() else int(val)
            except ValueError:
                continue
            rows += 1
            name = masked.get(h & MASK63) or raw.get(h)
            if name:
                hits.append((name, row.get("func", ""), row.get("location", "")))
                if name in KNOWN[:5]:
                    controls += 1

    print("commands in file: %d      candidates tried: %d      resolved: %d"
          % (rows, len(cands), len(hits)))
    print()
    if controls == 0:
        print("⚠⚠ NONE of the five known-real controls resolved "
              "(lobbylaunchgame, killserver,")
        print("   fast_restart, full_restart, map_restart). Do NOT read anything into the")
        print("   rest of this output - the hash form or the CSV column is wrong, not the")
        print("   wordlist. Check tools/crack-cmds.py --hash map_restart against a value")
        print("   you can see in the file.")
        print()
    else:
        print("✅ %d of 5 controls resolved - the hash form is right.\n" % controls)

    interesting = [h for h in hits if any(k in h[0] for k in INTERESTING)]
    print("=== map / gametype / lobby shaped (%d) ===" % len(interesting))
    for name, func, loc in sorted(interesting):
        print("  %-30s func %s" % (name, func))
    print()
    print("=== everything else resolved (%d) ===" % (len(hits) - len(interesting)))
    for name, func, loc in sorted(h for h in hits if h not in interesting):
        print("  %s" % name)
    print()
    print("⚠ %d of %d commands did NOT resolve. That is the wordlist being wrong,"
          % (rows - len(hits), rows))
    print("  not the commands being absent. Add guesses with --words=a,b,c.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
