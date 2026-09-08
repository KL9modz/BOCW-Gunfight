#!/usr/bin/env python3
"""Check builtin ARGUMENT COUNTS in a GSC file against ate47's Cold War table.

    python3 tools/check-args.py src/test_setteam/scripts/test_setteam.gsc
    python3 tools/check-args.py src/*/scripts/*.gsc

WHY THIS EXISTS. src/README.md, "What a harness PASS does and does not mean":

    It does NOT check:
      - Argument counts. system::register with 4 args passes stage 3 identically
        to the correct 5.

check-gsc.ps1 stage 4 asks whether a NAME exists in the dump. It never asks
whether the call passes a plausible number of arguments. Every project under
src/ now calls builtins that no stock script calls, so there is no stock call
site to copy the shape from - which makes arity the most likely remaining
defect class, and the one nothing was checking.

Table: t8-atian-menu/docs/notes/funcs_cw.csv - 4,481 Cold War builtins with
min/max argument counts and addresses in BlackOpsColdWar.exe.

⚠ THIS IS NOT A SUBSTITUTE FOR check-gsc.ps1. It checks arity and nothing else:
  not compilation, not dialect, not whether an argument MEANS what you think.
  Run both.

⚠ It cannot check argument SEMANTICS. setteam(1 arg) passes here whether the
  argument is a team name, an index or an entity. That is what tools/dump-grep.sh
  is for.
"""
import csv, os, re, sys

DEFAULT_TABLE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "t8-atian-menu", "docs", "notes", "funcs_cw.csv")

# GSC control flow and operators that parse as calls but are not
SKIP = {"if", "while", "for", "foreach", "switch", "return", "thread",
        "wait", "waittill", "waittillframeend", "notify", "endon", "isdefined"}


def load_table(path):
    arity = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            fn = (r.get("func") or "").strip().lower()
            if not fn:
                continue
            try:
                lo, hi = int(r["minargs"]), int(r["maxargs"])
            except (KeyError, ValueError, TypeError):
                continue
            if fn in arity:                       # duplicate pools: widen
                lo = min(lo, arity[fn][0])
                hi = max(hi, arity[fn][1])
            arity[fn] = (lo, hi)
    return arity


def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def scan_calls(code):
    """Yield (name, argcount). Balanced-paren scan, so NESTED CALLS are handled -
    a regex like \\w+\\([^()]*\\) silently skips switchmap_load(get_map_name(), x),
    which is exactly the call most worth checking."""
    for m in re.finditer(r"(?<![:\w])([A-Za-z_]\w*)\s*\(", code):
        name = m.group(1)
        i = m.end()                     # just past '('
        depth, args, instr, seen = 1, 1, False, False
        while i < len(code) and depth:
            ch = code[i]
            if ch == '"' and code[i - 1] != "\\":
                instr = not instr
                seen = True            # a string literal IS an argument
            elif instr:
                seen = True            # ...and so is anything inside one
            else:
                if ch in "([":
                    depth += 1
                elif ch in ")]":
                    depth -= 1
                elif ch == "," and depth == 1:
                    args += 1
                if depth >= 1 and not ch.isspace() and ch not in "(),":
                    seen = True
            i += 1
        yield name, (args if seen else 0)


def main():
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    table = DEFAULT_TABLE
    for a in sys.argv[1:]:
        if a.startswith("--table="):
            table = a.split("=", 1)[1]
    if not files:
        print(__doc__)
        return 2
    if not os.path.exists(table):
        print("TABLE NOT FOUND: %s" % table)
        print("Clone ate47/t8-atian-menu beside the dump, or pass --table=<path>")
        return 2

    arity = load_table(table)
    print("table: %s  (%d builtins)\n" % (os.path.normpath(table), len(arity)))

    bad = unknown = 0
    for path in files:
        code = strip_comments(open(path, encoding="utf-8").read())
        local = set(re.findall(
            r"^function\s+(?:private\s+)?(?:autoexec\s+)?(\w+)", code, re.M))
        rows, seen = [], set()
        for fn, n in scan_calls(code):
            if fn in SKIP or fn in local or (fn, n) in seen:
                continue
            seen.add((fn, n))
            lo_hi = arity.get(fn.lower())
            if lo_hi is None:
                rows.append(("?", fn, n, "-", "not a CW builtin (GSC function?)"))
                unknown += 1
            elif lo_hi[0] <= n <= lo_hi[1]:
                rows.append((" ", fn, n, "%d-%d" % lo_hi, "ok"))
            else:
                rows.append(("!", fn, n, "%d-%d" % lo_hi, "ARITY MISMATCH"))
                bad += 1
        print("== %s" % path)
        for flag, fn, n, tbl, verdict in sorted(rows, key=lambda r: (r[0] != "!", r[1])):
            print("  %s %-26s called with %d   table %-6s %s" % (flag, fn, n, tbl, verdict))
        print()

    print("arity mismatches: %d   |   names not in the CW table: %d" % (bad, unknown))
    print("\n'not a CW builtin' is usually fine - namespaced GSC functions and")
    print("stock script functions are not in this table. check-gsc.ps1 stage 3/4")
    print("is what resolves those. A MISMATCH is not fine.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
