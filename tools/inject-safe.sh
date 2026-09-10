#!/usr/bin/env bash
# Inject, but REFUSE if this process has already been injected into.
#
# B9 measured that injecting a second payload over a live one breaks the link
# outright - neither the old nor the new payload runs, and the failure is silent:
# you restart, see nothing, and blame the payload. The agent then made that exact
# mistake twice in one session on 2026-09-10, both times while explaining the rule
# to klaze. A rule that gets broken while being recited is a rule that needs to be
# enforced by the tool.
#
#   bash tools/inject-safe.sh <payload.cscc|.gscc> <target> <replace>
#   FORCE=1 bash tools/inject-safe.sh ...   # only when you MEAN to re-inject
#
# State lives in a file keyed by the game's PID, so a relaunch clears it for free.

set -u

ACTS="/c/bocw/ACTS/bin/acts.exe"
PAYLOAD="${1:?payload}"; TARGET="${2:?target}"; REPLACE="${3:?replace}"

pid="$(tasklist 2>/dev/null | awk '/BlackOpsColdWar\.exe/{print $2; exit}')"
[ -n "$pid" ] || { echo "BOCW not running"; exit 1; }

mark="/tmp/gf_injected_$pid"

if [ -e "$mark" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "REFUSING: pid $pid was already injected into:"
    sed 's/^/    /' "$mark"
    echo
    echo "B9: injecting over a live payload breaks the link silently."
    echo "RELAUNCH THE GAME, then run this again."
    exit 1
fi

cd "$(dirname "$ACTS")" || exit 1
out="$(./acts.exe injectcw "$PAYLOAD" "$TARGET" "$REPLACE" 2>&1)"
printf '%s\n' "$out" | tail -2

if printf '%s' "$out" | grep -q 'injected at'; then
    echo "$(date +%H:%M:%S)  $(basename "$PAYLOAD")  -> $TARGET" >> "$mark"
else
    echo "INJECTION FAILED - restarting will not help." >&2
    exit 1
fi

# ⚠ USE THIS SCRIPT, NOT acts.exe DIRECTLY. The agent added this guard on
#   2026-09-10 after breaking the B9 rule twice, then immediately broke it a third
#   time by calling acts.exe injectcw by hand and bypassing the check it had just
#   written. If you are about to type `acts.exe injectcw`, type this instead.
