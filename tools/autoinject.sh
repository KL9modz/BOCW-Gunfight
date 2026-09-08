#!/usr/bin/env bash
# Auto-injector: watch for Black Ops Cold War and inject a GSC payload as soon as
# the game is ready, so you never run injectcw by hand again.
#
#   ! bash /c/bocw/autoinject.sh menu &     <- Atian Menu (map carry, 19 maps)
#   ! bash /c/bocw/autoinject.sh mod  &     <- gunfight_mod (60s timer + fixes)
#
# Run it BEFORE launching the game, or any time after. It waits.
#
# ── WHY THIS AND NOT A DLL ───────────────────────────────────────────────────
# A real auto-injector DLL would have to patch the scriptparsetree pool itself:
# locate the script asset by FNV1a64 name hash, then overwrite the ScriptAsset
# struct's buffer pointer and length. ACTS prints the pool location every run
# (pool: BlackOpsColdWar.exe+1273c9f0) so the base is known - but the ENTRY
# STRUCT LAYOUT for the PC build is not. ACTS is a closed, packed binary; the
# public PS4 injector (socankam/Cold-War-PS4-GSC-Injector) has a PS4 variant with
# different offsets. Guessing a struct and writing it into live game memory is a
# crash generator, and the failure would be indistinguishable from anything else.
#
# acts.exe already does the patching correctly. The DLL was only ever a way to
# make it happen AUTOMATICALLY - and a watcher achieves that with no
# reverse-engineering risk at all.
#
# ── HOW IT KNOWS WHEN TO INJECT ──────────────────────────────────────────────
# The hook script (mp_common\bb.gsc) is only in the scriptparsetree pool once the
# process has loaded MP scripts. Before that, injectcw exits with
# "Can't find target script" - a clean, harmless failure. So this simply retries
# until it succeeds rather than trying to detect readiness some cleverer way.
#
# It injects ONCE per game process, then waits for the process to exit and arms
# itself again - which is exactly the manual step that was tedious after every
# restart.
#
# Injection is inert until the next map load links it: RESTART THE MATCH after.

set -u

ACTS="/c/bocw/ACTS/bin/acts.exe"
SP="${GF_PAYLOADS:-/c/bocw/payloads}"
MENU="$SP/BlackOpsColdWar_atianmenu_pc.gscc"
GFMOD="$SP/gunfight_mod.gscc"

TARGET='scripts\mp_common\bb.gsc'
REPLACE='scripts\core_common\clientids_shared.gsc'

POLL=5          # seconds between checks
EXE="BlackOpsColdWar.exe"

case "${1:-}" in
    menu) PAYLOAD="$MENU";  LABEL="Atian Menu" ;;
    mod)  PAYLOAD="$GFMOD"; LABEL="gunfight_mod (60s timer)" ;;
    *)    echo "usage: bash /c/bocw/autoinject.sh menu|mod   (append & to background it)"; exit 1 ;;
esac

[ -f "$ACTS" ]    || { echo "MISSING: $ACTS";    exit 1; }
[ -f "$PAYLOAD" ] || { echo "MISSING: $PAYLOAD"; exit 1; }

cd "$(dirname "$ACTS")" || exit 1

game_running() { tasklist 2>/dev/null | grep -qi "$EXE"; }

echo "autoinject: watching for $EXE — payload: $LABEL"
echo "autoinject: Ctrl-C to stop"

while true; do

    # 1. wait for the game to appear
    while ! game_running; do sleep "$POLL"; done
    echo "autoinject: game up, waiting for MP scripts to load..."

    # 2. retry until the hook is in the pool (fails harmlessly until then)
    injected=0
    while game_running; do
        out="$(./acts.exe injectcw "$PAYLOAD" "$TARGET" "$REPLACE" 2>&1)"

        if printf '%s' "$out" | grep -q 'injected at'; then
            echo "autoinject: INJECTED $LABEL — now restart the match to link it"
            injected=1
            break
        fi

        # "Can't find target script" just means MP scripts are not loaded yet.
        if ! printf '%s' "$out" | grep -q "Can't find target script"; then
            echo "autoinject: unexpected output:"
            printf '%s\n' "$out" | sed 's/^/    /'
        fi

        sleep "$POLL"
    done

    # 3. one injection per process; wait for exit, then re-arm
    if [ "$injected" -eq 1 ]; then
        while game_running; do sleep "$POLL"; done
        echo "autoinject: game closed — re-arming"
    fi
done
