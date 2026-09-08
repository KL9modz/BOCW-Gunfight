#!/usr/bin/env bash
# Inject ONE of the two GSC payloads, on the standard known-safe hook/replace pair.
#
#   ! bash /c/bocw/inject.sh menu     <- Atian Menu (map carry, 19 maps)
#   ! bash /c/bocw/inject.sh mod      <- gunfight_mod (60s timer + fixes)
#
# ── WHY NOT BOTH AT ONCE ─────────────────────────────────────────────────────
# injectcw takes (script, target, replace) and OVERWRITES the replace script's
# buffer. Two injections sharing a replace means the second clobbers the first,
# so both must use different pairs to coexist.
#
# That was tried on 2026-09-08 and BROKE THE GAME: gunfight_mod was injected over
# scripts\core_common\scene_model_shared.gsc, and leaving a match then hung
# forever on "connecting to lobby". scene_model_shared declares
# `class cscenemodel : csceneobject` with an empty body - but the FRONTEND uses
# scene models for menu backgrounds and character previews, and a subclass
# declaration still has to exist at link time. An empty body is not a free loss.
#
# Other candidates were checked and rejected for the same class of reason:
#   core_common\serverfield_shared.gsc  - defines register/get, actively used
#   mp_common\entityheadicons.gsc       - registration wrapper; killing it leaves
#                                         land_mine / molotov / supplydrop calling
#                                         entityheadicons:: against uninit state
#
# clientids_shared.gsc is the ONE known-safe replace target. Community standard,
# and its functionality has been destroyed by every injection all session with no
# observed consequence. Do not substitute another without testing a lobby return.
#
# ── THE WORKFLOW THIS ENABLES ────────────────────────────────────────────────
#   1. inject.sh menu   -> restart match -> carry to the map you want (RMB+V)
#   2. inject.sh mod    -> restart match -> play with the 60s timer and fixes
# The mod replaces the menu, which is fine: by then the carry is done. Re-run
# step 1 when you want to change map again.
#
# PREREQUISITE: the process must have loaded MP scripts at least once, or the
# hook is not in the scriptparsetree pool ("Can't find target script"). Load a
# private match once first. Injection is inert until the next map load links it.

set -u

ACTS="/c/bocw/ACTS/bin/acts.exe"
SP="${GF_PAYLOADS:-/c/bocw/payloads}"
MENU="$SP/BlackOpsColdWar_atianmenu_pc.gscc"
GFMOD="$SP/gunfight_mod.gscc"

TARGET='scripts\mp_common\bb.gsc'
REPLACE='scripts\core_common\clientids_shared.gsc'

case "${1:-}" in
    menu) PAYLOAD="$MENU";  LABEL="Atian Menu - map carry, 19 maps" ;;
    mod)  PAYLOAD="$GFMOD"; LABEL="gunfight_mod - 60s timer, zones_guard, timelimit_fix" ;;
    *)    echo "usage: bash /c/bocw/inject.sh menu|mod"; exit 1 ;;
esac

[ -f "$ACTS" ]    || { echo "MISSING: $ACTS";    exit 1; }
[ -f "$PAYLOAD" ] || { echo "MISSING: $PAYLOAD"; exit 1; }

cd "$(dirname "$ACTS")" || exit 1

echo "=== injecting: $LABEL ==="

# Capture rather than pipe. A pipeline's exit status is the LAST command's, so
# `acts.exe ... | tail` reported tail's success no matter what acts did - a failed
# injection still printed "RESTART THE MATCH" and looked fine. 'injected at' is the
# same success signal autoinject.sh already keys on.
out="$(./acts.exe injectcw "$PAYLOAD" "$TARGET" "$REPLACE" 2>&1)"
printf '%s\n' "$out" | tail -2

if ! printf '%s' "$out" | grep -q 'injected at'; then
    echo
    echo "INJECTION FAILED - restarting the match will NOT help. Fix this first." >&2
    case "$out" in
        *"Can't find target script"*)
            echo "  The hook is not in the scriptparsetree pool yet." >&2
            echo "  Load into a private match once, then re-run this." >&2 ;;
    esac
    exit 1
fi

echo
echo "RESTART THE MATCH to link it."
# A `case`, not two `[ ]` tests. As a trailing test the false branch became the
# script's exit status, so `inject.sh menu` exited 1 on success.
case "$1" in
    menu) echo "  RMB+V opens.  up RMB / down LMB / select R / back V" ;;
    mod)  echo "  round timer should read 60s and survive a map carry" ;;
esac
