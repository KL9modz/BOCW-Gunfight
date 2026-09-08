#!/usr/bin/env python3
"""Stages 3 and 4 of check-gsc.ps1, without ACTS or PowerShell.

    python3 tools/check-dump.py src/*/scripts/*.gsc
    python3 tools/check-dump.py --dump=/path/to/bocw-source src/lobby_probe/scripts/lobby_probe.gsc

WHAT IT IS. tools/check-gsc.ps1 runs four stages: (1) compile with `acts gscc`,
(2) round-trip with `acts gscd`, (3) resolve every namespace::function against the
dump, (4) confirm every BARE call appears somewhere in the dump. Stages 1-2 need
ACTS, a Windows binary. Stages 3-4 need only the dump.

This is stages 3 and 4, ported. Stage 4 is the one that matters most for this
project right now: it is what catches the logprint class of failure -
hello_world.gsc called logprint(), which appears ZERO times in the dump because it
is not a T9 builtin, the harness said PASS, and the game crashed 1-2s into a map
load. Every project under src/ now calls builtins no stock script calls, so there
is no stock call site to copy from and this stage is the only offline check on
whether the name is real.

⚠ THIS IS NOT A SUBSTITUTE FOR check-gsc.ps1. It cannot compile and it cannot
  round-trip, so it says nothing about dialect, syntax, or bytecode. Run the real
  harness on a machine with ACTS before injecting anything.

⚠ IT ALSO CORRECTS A FALSE POSITIVE IN STAGE 4. "No stock script calls this" is not
  the same as "this does not exist", and the original stage could not tell them
  apart. Cross-checking ate47's Cold War function table - which lists every builtin
  the ENGINE exports, with its address - splits the signal three ways:

      dump 0 · table 0   the name does not exist      -> FATAL, this is logprint
      dump 0 · table 1   exists, stock never calls it -> untested, not fatal
      dump >0            stock calls it               -> safest

  isvalidgametype and mapexists are the second case: both sit at real addresses in
  BlackOpsColdWar.exe and neither appears anywhere in 859 stock scripts. Flagging
  them as logprint would have been wrong.
"""
import os, re, sys

KEYWORDS = {"if","while","for","foreach","switch","case","return","break","continue",
            "thread","function","autoexec","private","else","do","new"}

DEFAULT_TABLE = "/home/user/ate47/t8-atian-menu/docs/notes/funcs_cw.csv"


def load_engine_table(path):
    """Every builtin the ENGINE exports. Absence here plus absence from the dump is
    the logprint signature; presence here means the name is real regardless."""
    import csv
    names = set()
    try:
        with open(path, newline="") as f:
            for r in csv.DictReader(f):
                n = (r.get("func") or "").strip().lower()
                if n:
                    names.add(n)
    except OSError:
        return None
    return names

def load_dump(root):
    """Map every callable name in the dump to one file that calls or defines it."""
    calls, nsfns = {}, {}
    call_re = re.compile(r'(?<![\w:.\\&])([a-z_][a-z0-9_]*)\s*\(')
    ns_re   = re.compile(r'\b([a-z_][a-z0-9_]*)::([a-z_][a-z0-9_]*)\s*\(')
    fn_re   = re.compile(r'(?m)^\s*function\s+(?:private\s+|autoexec\s+)*([a-z_][a-z0-9_]*)\s*\(')
    nsdecl  = re.compile(r'(?m)^\s*#namespace\s+([a-z_][a-z0-9_]*)\s*;')
    n = 0
    for base in ("scripts", "hashed"):
        p = os.path.join(root, base)
        if not os.path.isdir(p):
            continue
        for dp, _, fs in os.walk(p):
            for fn in fs:
                if not fn.endswith((".gsc", ".csc")):
                    continue
                path = os.path.join(dp, fn)
                try:
                    t = open(path, errors="ignore").read()
                except OSError:
                    continue
                n += 1
                rel = os.path.relpath(path, root)
                for m in call_re.finditer(t):
                    calls.setdefault(m.group(1), rel)
                for m in ns_re.finditer(t):
                    nsfns.setdefault((m.group(1), m.group(2)), rel)
                # a namespace's own functions are reachable as ns::fn
                for nsm in nsdecl.finditer(t):
                    ns = nsm.group(1)
                    for m in fn_re.finditer(t):
                        nsfns.setdefault((ns, m.group(1)), rel)
    return calls, nsfns, n


def main():
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    dump = "/home/user/ate47/bocw-source"
    table_path = DEFAULT_TABLE
    for a in sys.argv[1:]:
        if a.startswith("--dump="):
            dump = a.split("=", 1)[1]
        elif a.startswith("--table="):
            table_path = a.split("=", 1)[1]
    if not files:
        print(__doc__); return 2
    if not os.path.isdir(dump):
        print("DUMP NOT FOUND: %s  (pass --dump=<path>)" % dump); return 2

    print("dump: %s" % dump)
    engine = load_engine_table(table_path)
    print("engine table: %s" % (("%d builtins" % len(engine)) if engine else "NOT FOUND - stage 4 will over-report"))
    calls, nsfns, nfiles = load_dump(dump)
    print("indexed %d script files - %d distinct call names, %d namespace::function pairs\n"
          % (nfiles, len(calls), len(nsfns)))

    bad = warn = 0
    for src in files:
        text = open(src, encoding="utf-8").read()
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        text = re.sub(r"//[^\n]*", "", text)
        local = set(re.findall(r'(?m)^\s*function\s+(?:private\s+|autoexec\s+)*([a-z_][a-z0-9_]*)\s*\(', text))
        print("== %s" % src)

        # stage 3 - namespace::function
        for ns, fn in sorted(set(re.findall(r'\b([a-z_][a-z0-9_]*)::([a-z_][a-z0-9_]*)\s*\(', text))):
            if (ns, fn) in nsfns:
                print("   ok   %s::%s" % (ns, fn))
            else:
                print("   !! NOT FOUND  %s::%s" % (ns, fn)); bad += 1

        # stage 4 - bare calls
        bare = sorted({m for m in re.findall(r'(?<![\w:.\\&])([a-z_][a-z0-9_]*)\s*\(', text)
                       if m not in KEYWORDS and m not in local})
        for b in bare:
            if b in calls:
                print("   ok   %s()          %s" % (b, calls[b]))
            elif engine and b.lower() in engine:
                print("   ~~ UNUSED BY STOCK  %s()  - real engine builtin, no stock caller." % b)
                print("        Not the logprint case. Untested, and the first thing to suspect")
                print("        if the script dies at that line.")
                warn += 1
            else:
                print("   !! NOT IN DUMP OR ENGINE TABLE  %s()  - this is the logprint signature." % b)
                bad += 1
        print()

    print("fatal: %d    unused-by-stock: %d" % (bad, warn))
    if bad:
        print("A fatal is the logprint signature - compiles, then kills the script at link.")
    if warn:
        print("An unused-by-stock call is real but has no precedent. Emit it LAST so the")
        print("probes before it have already printed if it throws.")
    if not bad and not warn:
        print("Stages 3-4 clean.")
    print("⚠ Stages 1-2 (compile + round-trip) still need ACTS on a Windows machine.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
