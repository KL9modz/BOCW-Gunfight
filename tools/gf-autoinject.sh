#!/usr/bin/env bash
# Robust single first-load injector. Detects a FRESH game launch by the PID changing (no fragile
# quit-gap polling), then hammers injectcw through the first script parse so gunfight_menu.gscc
# links FIRST and mod_apply runs. Started + stopped by Fable via the Bash tool.
set -u
ACTS="/c/bocw/ACTS/bin/acts.exe"
PAYLOAD="/c/bocw/payloads/gunfight_menu.gscc"
HOOK='scripts\mp_common\bb.gsc'
REPLACE='scripts\core_common\clientids_shared.gsc'
getpid(){ python -c "import sys;sys.path.insert(0,'C:/bocw/BOCW-Gunfight/tools/gf-control');import gf_native;print(gf_native.find_game_pid() or 0)" 2>/dev/null; }
[ -f "$PAYLOAD" ] || { echo "MISSING $PAYLOAD"; exit 1; }
start="$(getpid)"
echo "gf-watch: current game pid=$start -- RELAUNCH the game now; I'll catch the fresh launch."
while true; do
  cur="$(getpid)"
  if [ -n "$cur" ] && [ "$cur" != "0" ] && [ "$cur" != "$start" ]; then break; fi
  sleep 0.2
done
echo "gf-watch: fresh launch pid=$cur -- hammering injectcw through the first parse ..."
i=0
while true; do
  i=$((i+1))
  OUT="$("$ACTS" injectcw "$PAYLOAD" "$HOOK" "$REPLACE" 2>&1)"
  if echo "$OUT" | grep -qi "injected at"; then echo "gf-watch: >>> INJECTED on attempt $i <<<"; exit 0; fi
  g="$(getpid)"; if [ "$g" = "0" ]; then echo "gf-watch: game exited before inject"; exit 1; fi
  sleep 0.05
done
