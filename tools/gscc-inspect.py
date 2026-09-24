#!/usr/bin/env python3
"""Inspect a Cold War (T9, VM38) compiled script (.gscc / .cscc) without ACTS.

    python3 tools/gscc-inspect.py <file.gscc> [--dump=<bocw-source>] [--table=<funcs_cw.csv>]
                                  [--names=<extra .gsc dir>] [--strings] [--imports] [--exports]

With no section flag it prints everything. It never executes anything: it reads the header,
the string table, the import / export tables and the #using list, and names what it can.

WHY. ACTS's `gscd` decompiles fully but only runs on Windows. This is the read-only half that
runs anywhere: which BUILTINS and stock functions a payload calls (how it draws, what it
touches), and every string it can show on screen. Enough to review a community menu before
anyone injects it, or to check what one of our own builds imports.

LAYOUT (ACTS src/core/acts/tools/gsc/data/gsc_data_t9.hpp, T9GSCOBJ; magic 0x38000a0d43534780):
    0x18 u16 string_count · 0x1a exports_count · 0x1c imports_count · 0x20 globalvar_count
    0x24 u16 includes_count · 0x26 devblock_string_count · 0x28 u32 devblock_string_offset
    0x30 u32 string_offset · 0x34 includes_table · 0x38 exports_tables · 0x3c import_tables
    0x44 u32 globalvar_offset · 0x48 u32 file_size
  string  entry: u32 offset, u8 num_address, u8 type, u16 pad, then u32 * num_address
  import  entry: u32 name, u32 namespace, u16 num_address, u8 param_count, u8 flags, then u32 * n
  export  entry: u32 checksum, u32 address, u32 name, u32 namespace, u32 callback_event,
                 u8 param_count, u8 flags, u16 pad
  include entry: u64 script-name hash
Strings: a first byte with the top bits 10 (0x80-0xBF) marks an encrypted string; ACTS writes
0x8B <len+1> 00 <plaintext> (the header tools/strip-strhdr.ps1 removes). Both are decoded when
the text is in fact plain; a genuinely encrypted string is reported as such.

NAMES. Function / namespace ids are the 32-bit T8/T9 script hash (tools/dvar-live/t89.py);
#using entries are the 64-bit FNV-1a name hash (tools/crack-hash.py). Candidates come from the
retail builtin table, every function and namespace in the dump, and any --names directory.
An unresolved id is printed as function_xxxxxxxx, the way ACTS prints it.
"""
import csv, os, re, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "dvar-live"))
from t89 import t89scr  # noqa: E402

MAGIC = 0x38000A0D43534780
IMPORT_CALLTYPE = {1: "method childthread", 2: "method thread", 3: "function childthread",
                   4: "function", 5: "func/method", 6: "function thread", 7: "method"}


def fnv64(s):
    h = 0xCBF29CE484222325
    for c in s.lower().encode():
        h = ((h ^ c) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h & 0x7FFFFFFFFFFFFFFF


def default_paths():
    home = os.path.expanduser("~")
    guesses = [os.path.join(HERE, "..", "..", "bocw-source"), os.path.join(HERE, "..", "..", "bocw-source-main"),
               os.path.join(HERE, "..", "..", "ate47", "bocw-source"), os.path.join(home, "ate47", "bocw-source")]
    dump = next((g for g in guesses if os.path.isdir(g)), None)
    tguesses = [os.path.join(HERE, "..", "..", "t8-atian-menu", "docs", "notes", "funcs_cw.csv"),
                os.path.join(HERE, "..", "..", "ate47", "t8-atian-menu", "docs", "notes", "funcs_cw.csv"),
                os.path.join(home, "ate47", "t8-atian-menu", "docs", "notes", "funcs_cw.csv")]
    table = next((g for g in tguesses if os.path.isfile(g)), None)
    return dump, table


def build_names(dump, table, extra):
    funcs, spaces, scripts, builtins = {}, {}, {}, set()
    if table and os.path.isfile(table):
        with open(table, newline="", encoding="utf-8", errors="replace") as f:
            for r in csv.DictReader(f):
                n = (r.get("func") or "").strip()
                if n and not n.startswith("function_"):
                    funcs.setdefault(t89scr(n), n)
                    builtins.add(n.lower())
    fre = re.compile(r"^\s*function\s+(?:private\s+)?(?:autoexec\s+)?(\w+)\s*\(", re.M)
    nre = re.compile(r"^#namespace\s+(\w+);", re.M)
    for root in [d for d in (dump, extra) if d and os.path.isdir(d)]:
        for dp, _, fs in os.walk(root):
            for fn in fs:
                if not fn.endswith((".gsc", ".csc")):
                    continue
                p = os.path.join(dp, fn)
                rel = os.path.relpath(p, root).replace("\\", "/")
                for form in (rel, rel.replace("/", "\\")):
                    scripts.setdefault(fnv64(form), rel)
                base = os.path.splitext(fn)[0]              # a file's default namespace is its name
                spaces.setdefault(t89scr(base), base)
                try:
                    src = open(p, encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                for n in fre.findall(src):
                    if not n.startswith("function_"):
                        funcs.setdefault(t89scr(n), n)
                for n in nre.findall(src):
                    if not n.startswith("namespace_"):
                        spaces.setdefault(t89scr(n), n)
                        funcs.setdefault(t89scr(n), n)
    return funcs, spaces, scripts, builtins


def read_string(b, off):
    """-> (text, how) where how is plain / acts-header / encrypted."""
    if b[off] & 0xC0 == 0x80:
        n = b[off + 1]
        raw = b[off + 3: off + 3 + max(n - 1, 0)]
        if b[off + 2] == 0 and n >= 1 and all(32 <= c < 127 or c in (9, 10, 13) for c in raw):
            return raw.decode("latin-1"), "acts-header"
        return None, "encrypted"
    end = b.index(0, off)
    return b[off:end].decode("latin-1"), "plain"


def parse(path):
    b = open(path, "rb").read()
    if len(b) < 0x58 or struct.unpack_from("<Q", b, 0)[0] != MAGIC:
        raise SystemExit("%s: not a Cold War VM38 script (magic)" % path)
    h = {}
    (h["name"],) = struct.unpack_from("<Q", b, 0x10)
    (h["crc"],) = struct.unpack_from("<I", b, 0x08)
    (h["strings"], h["exports"], h["imports"], _, h["gvars"], _, h["includes"], h["devstrings"]) = \
        struct.unpack_from("<8H", b, 0x18)
    (h["devstr_off"], h["cseg"], h["str_off"], h["inc_off"], h["exp_off"], h["imp_off"], _, h["gvar_off"],
     h["size"]) = struct.unpack_from("<9I", b, 0x28)
    if h["size"] != len(b):
        print("warning: header size %d != file size %d" % (h["size"], len(b)))

    strings, pos = [], h["str_off"]
    for _ in range(h["strings"]):
        off, nref, typ = struct.unpack_from("<IBB", b, pos)
        text, how = read_string(b, off)
        strings.append((off, nref, typ, text, how))
        pos += 8 + 4 * nref

    imports, pos = [], h["imp_off"]
    for _ in range(h["imports"]):
        name, ns, nref, params, flags = struct.unpack_from("<IIHBB", b, pos)
        imports.append((name, ns, nref, params, flags))
        pos += 12 + 4 * nref

    exports, pos = [], h["exp_off"]
    for _ in range(h["exports"]):
        crc, addr, name, ns, ev, params, flags = struct.unpack_from("<IIIIIBB", b, pos)
        exports.append((addr, name, ns, params, flags))
        pos += 24

    includes = [struct.unpack_from("<Q", b, h["inc_off"] + 8 * i)[0] for i in range(h["includes"])]
    return h, strings, imports, exports, includes


def main():
    args = sys.argv[1:]
    files = [a for a in args if not a.startswith("--")]
    opt = {a.split("=", 1)[0]: (a.split("=", 1)[1] if "=" in a else True) for a in args if a.startswith("--")}
    if len(files) != 1:
        print(__doc__)
        return 2
    dump, table = default_paths()
    dump = opt.get("--dump", dump)
    table = opt.get("--table", table)
    funcs, spaces, scripts, builtins = build_names(dump, table, opt.get("--names"))
    sections = [s for s in ("--strings", "--imports", "--exports") if s in opt] or \
               ["--strings", "--imports", "--exports"]

    h, strings, imports, exports, includes = parse(files[0])
    fn = lambda x: funcs.get(x, "function_%08x" % x)
    ns = lambda x: spaces.get(x, funcs.get(x, "namespace_%08x" % x))

    print("== %s  %d bytes  script %016x%s  crc %08x" % (
        files[0], h["size"], h["name"], (" (" + scripts[h["name"]] + ")") if h["name"] in scripts else "", h["crc"]))
    print("   strings %d · imports %d · exports %d · includes %d · globals %d · dev strings %d" % (
        h["strings"], h["imports"], h["exports"], h["includes"], h["gvars"], h["devstrings"]))
    print("   names: %d functions/namespaces, %d scripts, %d builtins (dump=%s)" % (
        len(funcs), len(scripts), len(builtins), dump))
    print("\n#using")
    for inc in includes:
        print("   %s" % scripts.get(inc, "script_%016x" % inc))

    # A builtin call is imported under the file's OWN namespace (the #namespace line; measured on the
    # Atian build: 0x61cac3a4 = t89scr("atianmenu")), so that namespace prints as none.
    own = {e[2] for e in exports}
    if own:
        print("   own namespace: %s" % ", ".join(sorted(ns(x) for x in own)))

    if "--imports" in sections:
        print("\nIMPORTS - what it calls (b = retail builtin; refs = call sites)")
        rows = []
        for name, space, nref, params, flags in imports:
            n = fn(name)
            where = "" if space in own or space == 0 else ns(space) + "::"
            kind = IMPORT_CALLTYPE.get(flags & 0xF, "flags %02x" % flags)
            dev = " dev" if flags & 0x20 else ""
            rows.append((where + n, kind + dev, params, nref, "b" if not where and n.lower() in builtins else ""))
        for r in sorted(rows, key=lambda r: (r[4] != "b", r[0])):
            print("   %-1s %-58s %-20s args %-2d refs %d" % (r[4], r[0], r[1], r[2], r[3]))

    if "--exports" in sections:
        print("\nEXPORTS - its own functions")
        for addr, name, space, params, flags in sorted(exports, key=lambda e: e[0]):
            print("   @%06x %s::%s (%d)%s" % (addr, ns(space), fn(name), params,
                                             " autoexec" if flags & 0x01 else ""))

    if "--strings" in sections:
        print("\nSTRINGS - everything it can put on screen or pass as a name")
        kinds = {}
        for off, nref, typ, text, how in strings:
            kinds[how] = kinds.get(how, 0) + 1
            shown = text if text is not None else "<encrypted, %d bytes>" % 0
            print("   %5x x%-2d %s" % (off, nref, shown.replace("\n", "\\n")))
        print("   (%s)" % ", ".join("%s %d" % kv for kv in sorted(kinds.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
