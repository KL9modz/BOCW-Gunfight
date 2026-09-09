#!/usr/bin/env bash
# Inject ONE GSC payload, on the standard known-safe hook/replace pair.
#
#   ! bash /c/bocw/inject.sh menu     <- Atian Menu (map carry, 19 maps)
#   ! bash /c/bocw/inject.sh mod      <- gunfight_mod (60s timer + fixes)
#   ! bash /c/bocw/inject.sh <name>   <- any payload: $SP/<name>.gscc
#
# The third form is how the staged tests run - lobby_probe, test_addclients,
# test_spawnmode, test_seatspectator, test_latejoin. `menu` and `mod` stay as
# aliases only because their payload filenames do not match their project names.
#
# ⚠ ONE PAYLOAD AT A TIME. Every injection uses the same replace target, so each
#   one clobbers the last. That is a feature for the staged tests - "one write per
#   match" is enforced by the mechanism rather than by remembering.
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

NAME="${1:-}"

case "$NAME" in
    "")   echo "usage: bash /c/bocw/inject.sh menu|mod|<project-name>"; exit 1 ;;
    menu) PAYLOAD="$MENU";  LABEL="Atian Menu - map carry, 19 maps" ;;
    mod)  PAYLOAD="$GFMOD"; LABEL="gunfight_mod - 60s timer, zones_guard, timelimit_fix" ;;
    # Anything else is a project name. Resolved by convention rather than listed,
    # so a new src/<name>/ works here the moment its .gscc is built - no edit to
    # this file, and no chance of the list going stale against src/.
    *)    PAYLOAD="$SP/$NAME.gscc"; LABEL="$NAME" ;;
esac

# Reject a name that would escape the payload dir before it reaches the -f test,
# so a typo says so instead of producing a confusing MISSING path.
case "$NAME" in
    */*|..*) echo "not a payload name: $NAME"; exit 1 ;;
esac

[ -f "$ACTS" ]    || { echo "MISSING: $ACTS";    exit 1; }
if [ ! -f "$PAYLOAD" ]; then
    echo "MISSING: $PAYLOAD"
    echo
    echo "Built payloads in $SP:"
    ls -1 "$SP"/*.gscc 2>/dev/null | sed 's|.*/|  |; s|\.gscc$||' || echo "  (none)"
    echo
    echo "Compile it first:  acts gscc <script>.gsc -g cw -p pc -o $SP/$NAME"
    exit 1
fi

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
case "$NAME" in
    menu) echo "  RMB+V opens.  up RMB / down LMB / select R / back V" ;;
    mod)  echo "  round timer should read 60s and survive a map carry" ;;
    lobby_probe)       echo "  reads 1-12 then 9, one every 5s. Probe 12 must equal probe 6" ;;
    test_addclients)   echo "  fills until refused. The last count before the stall is the ceiling" ;;
    test_spawnmode)    echo "  READ PROBE 31 FIRST. Zero = the wrapper never ran, not 'the fix failed'" ;;
    test_seatspectator) echo "  read_only=1 on the first pass. 21/23 print before iscodcaster is called" ;;
    test_latejoin)     echo "  20xxxxx = allies*100 + axis. 2000404 is 4v4" ;;
    test_sessionswitch) echo "  read_only=1 FIRST: 40 must not be 99999. Live: read 41 before judging presence" ;;
    gunfight_menu)     echo "  RMB+V opens. RMB up / LMB down / R select / V back. Settings persist as gf_* dvars" ;;
    *)    echo "  test a LOBBY RETURN afterwards if this payload writes anything" ;;
esac
