#!/bin/bash
# Extract and decompile Cold War's LUI (LuaJIT) source from the installed game — OFFLINE, no game
# process is touched.  docs/notes/lui-source.md explains what comes out and what it settled.
#
#   bash tools/lui/extract-lui.sh                 # everything into $LUI_OUT (default /c/bocw/lui-source)
#   bash tools/lui/extract-lui.sh core_ui         # one zone
#
# Steps (each is skipped when its output already exists):
#   1. acts fastfile -C <game> -d      zone\<z>.ff  -> <out>/ff/<z>.ff.dec   (Oodle only; enc:false)
#   2. tools/lui/ljcarve.py             <z>.ff.dec  -> <out>/luac/<z>/*.luac + index.json
#   3. tools/lui/ljcarve.py --names     all indexes -> <out>/xhash_names.json  (FNV1a lower63 cracks)
#   4. ljd (patched, tools/lui/ljd-t9.patch)         -> <out>/lua/<z>_NNNN_OFF.lua
#
# Needs: ACTS 3.3.0 (C:/bocw/ACTS/bin), the game's oo2core_8_win64.dll copied into ACTS/bin/deps/,
# python3, git.  ljd is cloned once into <out>/ljd (MIT, Aussiemon/ljd @ 2ed0381) and patched.
set -u
GAME="${GAME_DIR:-D:\\Battle.net\\Call of Duty Black Ops Cold War}"
ACTS="${ACTS_BIN:-/c/bocw/ACTS/bin}"
OUT="${LUI_OUT:-/c/bocw/lui-source}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ZONES="${1:-core_ui mp_common core_frontend core_common core_bootstrap}"
JOBS="${JOBS:-8}"

mkdir -p "$OUT/ff" "$OUT/luac" "$OUT/lua"

if [ ! -f "$ACTS/deps/oo2core_8_win64.dll" ]; then
    mkdir -p "$ACTS/deps"
    cp "$(cygpath "$GAME")/oo2core_8_win64.dll" "$ACTS/deps/" || { echo "need oo2core_8_win64.dll from the game dir"; exit 1; }
fi

for z in $ZONES; do
    if [ ! -s "$OUT/ff/$z.ff.dec" ]; then
        echo "== decompress $z.ff"
        (cd "$ACTS" && ./acts.exe -t fastfile -C "$GAME" -d -o "$OUT/ff" "zone\\$z.ff" | tail -2)
    fi
    if [ ! -s "$OUT/luac/$z/index.json" ]; then
        echo "== carve $z"
        python "$REPO/tools/lui/ljcarve.py" "$OUT/ff/$z.ff.dec" "$OUT/luac/$z"
    fi
done

echo "== xhash names"
python "$REPO/tools/lui/ljcarve.py" --names "$OUT"/luac/* "$OUT"/ff/*.ff.dec /c/bocw/bocw-source-main "$OUT/xhash_names.json"

if [ ! -d "$OUT/ljd" ]; then
    echo "== ljd"
    git clone -q https://github.com/Aussiemon/ljd.git "$OUT/ljd" && (cd "$OUT/ljd" && git checkout -q 2ed0381 && git apply "$REPO/tools/lui/ljd-t9.patch") || { echo "ljd setup failed"; exit 1; }
fi

echo "== decompile ($JOBS jobs)"
export LJD_XHASH_NAMES="$OUT/xhash_names.json" LJD_DIR="$OUT/ljd" LUA_OUT="$OUT/lua"
one() {
    f="$1"; n=$(basename "$f" .luac); o="$LUA_OUT/$n.lua"
    [ -s "$o" ] && return 0
    (cd "$LJD_DIR" && timeout 300 python main.py -c -f "$f" -o "$o" >/dev/null 2>"$LUA_OUT/$n.err") || echo "FAIL $n" >> "$LUA_OUT/_fail.txt"
    [ -s "$LUA_OUT/$n.err" ] || rm -f "$LUA_OUT/$n.err"
}
export -f one
for z in $ZONES; do ls "$OUT/luac/$z/"*.luac; done | xargs -P "$JOBS" -n 1 bash -c 'one "$0"'
echo "decompiled: $(ls "$OUT/lua/"*.lua | wc -l)   failed: $(cat "$OUT/lua/_fail.txt" 2>/dev/null | wc -l)"
