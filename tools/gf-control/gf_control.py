"""Gunfight Host Control - a Windows GUI that drives the in-match mod through the in-process
bridge, so the host can run the match from a real window on a second screen / RDP instead of
the ~4-line in-game feed the game caps us to.

HOW IT WORKS. Every button composes console `set <dvar> <value>` lines and hands them to the
gf-bridge transport (tools/gf-bridge/bridge_channel.py), which writes them into a named
shared-memory block. The in-process gf_bridge.dll polls that block and runs each line via
cwpatch's command executor - and an in-process `set` DOES reach the GSC dvar store the menu
reads (proven in-game 2026-09-13, T1; an external WriteProcessMemory never could, which is
why the old dvar-write backend is retired here). The injected menu (src/gunfight_menu)
re-reads its gf_* dvars every round in mod_apply(), so a CONFIG change lands next round.
ACTIONS (map/gametype stage or switch, fill bots, restart) are one-shots: gf_cmd_* trigger
dvars + gf_cmd_go, which the menu's command-poller (cmd_poll / cmd_dispatch in
gunfight_menu.gsc) runs host-side and clears. gf_cmd_stage=1 makes a map/gametype switch a
STAGE: switchmap_load only, the lobby shows the map when the match ends.

SAFETY. The bridge transport touches NO game memory - just a shared-memory block - so it needs
no elevation and nothing that can wedge the game. Dry-run by default: it shows the exact `set`
lines it WOULD send and sends nothing. `--live` sends them for real; the gf_bridge.dll must be
loaded in the game (build+inject it once per launch, tools/gf-bridge/README.md). If the DLL is
not loaded, a sent command simply sits unread in the buffer.

    python gf_control.py            # dry-run, safe anywhere
    python gf_control.py --live     # sends over the bridge (needs gf_bridge.dll loaded)
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import ttk, messagebox

# ---- artifact resolution: the standalone .exe (PyInstaller) vs the dev tree ------------------
# The runtime needs only PREBUILT artifacts (menu .gscc, gf_bridge.dll, cwpatch) + acts as the
# injector - none of the dev toolchain (zig/Python). In a frozen build they sit beside the exe
# (see gf-control.spec); in the dev tree they are the repo's usual siblings.
FROZEN = getattr(sys, "frozen", False)
if FROZEN:
    BUNDLE = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(sys.executable)))
    GFBRIDGE = os.path.join(BUNDLE, "gf-bridge")
    ACTS = os.path.join(BUNDLE, "acts", "acts.exe")
    MENU_PAYLOAD = os.path.join(BUNDLE, "payloads", "gunfight_menu.gscc")
    BRIDGE_DLL = os.path.join(GFBRIDGE, "gf_bridge.dll")
    CWPATCH_SRC = os.path.join(BUNDLE, "vendor", "discord_game_sdk.CWPATCH-13824.dll")
    ASSETS = os.path.join(BUNDLE, "assets")
else:
    REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    GFBRIDGE = os.path.join(REPO, "tools", "gf-bridge")
    ACTS = os.path.normpath(os.path.join(REPO, "..", "ACTS", "bin", "acts.exe"))
    MENU_PAYLOAD = os.path.normpath(os.path.join(REPO, "..", "payloads", "gunfight_menu.gscc"))
    BRIDGE_DLL = os.path.join(GFBRIDGE, "gf_bridge.dll")
    CWPATCH_SRC = os.path.normpath(os.path.join(REPO, "..", "vendor-backup",
                                                "discord_game_sdk.CWPATCH-13824.dll"))
    ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
# acts injectcw <payload> <hook> <replace> is the menu injection (NOT `bash inject.sh` - a
# windowless app resolves `bash` to WSL's System32\bash.exe, which can't run the repo script).
MENU_HOOK = r"scripts\mp_common\bb.gsc"
MENU_REPLACE = r"scripts\core_common\clientids_shared.gsc"

try:
    import gf_native
except Exception:
    gf_native = None

try:
    import roster_scan                       # read-only: the connected-player list out of the game
except Exception:
    roster_scan = None

try:
    import config_scan                       # read-only: the LIVE gf_* config out of the game
except Exception:
    config_scan = None


def _no_window() -> dict:
    """subprocess kwargs that hide the child's console window - otherwise every shell-out
    from the windowless pythonw app flashes a terminal (e.g. the 3s status poll)."""
    if sys.platform != "win32":
        return {}
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 0  # SW_HIDE
    return {"creationflags": getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000), "startupinfo": si}

try:
    from dvar_backend import DvarBackend, BackendError  # noqa: F401 (BackendError reused below)
except Exception:  # backend import must never stop the GUI from opening in dry-run
    DvarBackend = None
    BackendError = Exception

# The bridge transport: writes console-command lines into the shared-memory block the
# in-process gf_bridge.dll polls. This is the WORKING control path (T1 proved an in-process
# `set` reaches GSC getdvarint; an external WriteProcessMemory never could). No game memory is
# touched here - just shared memory - so this half runs unprivileged.
sys.path.insert(0, GFBRIDGE)      # dev: tools/gf-bridge ; frozen: BUNDLE/gf-bridge
try:
    import bridge_channel
except Exception:  # keep the GUI usable (display-only) if the transport is missing
    bridge_channel = None


class BridgeBackend:
    """Drives the mod by sending `set <dvar> <value>` lines through the in-process bridge DLL
    (gf_bridge.dll), which runs them via cwpatch's command executor. Presents the same small
    interface the GUI expects of a backend: connect(), apply(settings), and a .log list it
    drains. In dry-run it logs the exact lines and sends nothing."""

    def __init__(self, dry_run: bool):
        self.dry_run = dry_run
        self.log: list[str] = []

    def connect(self):
        if bridge_channel is None:
            raise BackendError("bridge_channel not found (tools/gf-bridge)")
        listening, seq, _ = bridge_channel.probe()
        self.log.append(f"bridge DLL is listening (seq={seq})" if listening
                        else "bridge DLL NOT detected - load gf_bridge.dll in the game")

    @staticmethod
    def _lines(settings: dict) -> list[str]:
        # gf_cmd_go, if present, must be set LAST so the GSC poller never fires on a half-set
        # command. Dict order already puts it last, but enforce it rather than trust the caller.
        items = [(k, v) for k, v in settings.items() if k != "gf_cmd_go"]
        if "gf_cmd_go" in settings:
            items.append(("gf_cmd_go", settings["gf_cmd_go"]))
        return [f"set {k} {v}" for k, v in items]

    def apply(self, settings: dict):
        lines = self._lines(settings)
        if self.dry_run:
            self.log.append("[dry-run] would send:")
            self.log.extend("  " + ln for ln in lines)
            return
        if bridge_channel is None:
            self.log.append("no bridge transport - nothing sent")
            return
        # Never send an oversize block: bridge_channel would truncate it mid-line, and a torn
        # `set` can set a dvar to a garbage value and hang the game. Refuse and say so instead.
        cap = bridge_channel.SIZE - bridge_channel.HDR - 1
        if len("\n".join(lines).encode("ascii", "replace")) > cap:
            self.log.append(f"NOT sent: {len(lines)} commands exceed the bridge buffer "
                            f"({cap} B) - apply fewer settings at once.")
            return
        seq, listening = bridge_channel.send(lines, quiet=True)
        self.log.append(f"sent #{seq}" + ("" if listening
                        else "  (gf_bridge.dll not detected - is it loaded?)"))
        self.log.extend("  " + ln for ln in lines)


class _Tip:
    """A minimal hover tooltip: shows `text` in a small popup just below `widget`. Used to
    carry the reference detail (stock values, -1 meanings) trimmed from the field labels."""

    def __init__(self, widget, text):
        self.widget = widget
        self.text = text
        self.tip = None
        widget.bind("<Enter>", self._show)
        widget.bind("<Leave>", self._hide)

    def _show(self, _e):
        if self.tip or not self.text:
            return
        x = self.widget.winfo_rootx() + 14
        y = self.widget.winfo_rooty() + self.widget.winfo_height() + 2
        self.tip = tk.Toplevel(self.widget)
        self.tip.wm_overrideredirect(True)
        self.tip.wm_geometry(f"+{x}+{y}")
        tk.Label(self.tip, text=self.text, bg="#ffffe0", fg="#222", relief="solid",
                 borderwidth=1, font=("Segoe UI", 8), justify="left", padx=6, pady=3).pack()

    def _hide(self, _e):
        if self.tip:
            self.tip.destroy()
            self.tip = None


# ---- control schema: (dvar, label, kind, spec, default) ----------------------
# kind: "choice" spec=[(label,value)...] | "int" spec=(min,max,step) | "toggle"
CONFIG = {
    "Teams": [
        ("gf_team_size", "Team size", "choice",
         [("2v2", 2), ("3v3", 3), ("4v4", 4), ("5v5", 5), ("6v6", 6)], 4),
        ("gf_spec_slots", "Spectator slots (added to maxplayers)", "choice",
         [("0", 0), ("2", 2), ("4", 4)], 2),
    ],
    "Round": [
        ("gf_timer_seconds", "Round timer (s)", "int", (0, 1440, 10), 60),
        # Pre-match / pre-round countdowns (mod_periods in gunfight_menu.gsc). The stock rows
        # offer 5-60 / 0-30; -1 = the lobby's own row. A change lands on the NEXT countdown.
        ("gf_prematch", "Pre-match (s)", "int", (-1, 60, 1), 15),
        ("gf_preround", "Pre-round (s)", "int", (-1, 30, 1), 7),
    ],
    "Loadout": [
        ("gf_loadout", "Loadout set", "choice",
         [("Default", 0), ("Snipers", 1), ("Blueprints", 2), ("Melee", 3)], 0),
        ("gf_customcac", "Custom classes", "choice",
         [("Off (Gunfight loadouts)", 0), ("On (player classes)", 1)], 0),
        ("gf_profile", "Gunfight profile (real blob)", "choice",
         [("On", 1), ("Off (raw hybrid)", 0)], 1),
        # Camo forced onto every pool weapon at every spawn (docs/notes/loadout-camo.md).
        # Random each round is the default; other ids 1-121 via the in-game "by ID" page.
        ("gf_camo", "Pool camo", "choice",
         [("Random each round", -2), ("Random per player", -3),
          ("Stock (pool's own look)", -1), ("Gold", 61), ("Diamond", 62), ("DM Ultra", 63),
          ("Golden Viper (ZM)", 64), ("Plague Diamond (ZM)", 65), ("Dark Aether (ZM)", 66),
          ("Pack-a-Punch 1", 67), ("Pack-a-Punch 2", 68), ("Pack-a-Punch 3", 69),
          ("PaP Mauer der Toten 1", 116), ("PaP Mauer der Toten 2", 117),
          ("PaP Mauer der Toten 3", 118), ("PaP Forsaken 1", 119),
          ("PaP Forsaken 2", 120), ("PaP Forsaken 3", 121)], -2),
        ("gf_camo_pool", "Random camo pool", "choice",
         [("Mastery + Pack-a-Punch", 0), ("All 1-121", 1)], 0),
        ("gf_camo_split", "Random rolls", "choice",
         [("Primary and secondary separately", 1), ("One camo for both", 0)], 1),
        ("gf_spyplane", "Spy plane", "choice",
         [("Off", 0), ("On", 1), ("Shared (hidden)", 3)], 0),
    ],
    "Match": [
        ("gf_roundwinlimit", "First to N rounds", "int", (-1, 50, 1), -1),
        ("gf_roundlimit", "Round cap", "int", (-1, 50, 1), -1),
        ("gf_rounds_loadout", "Rounds / loadout", "int", (-1, 20, 1), -1),
        ("gf_switch_sides", "Side switch", "choice",
         [("Mod-owned (one flip)", 1), ("Stock paths", 0)], 1),
    ],
    "Bots": [
        # Per-team difficulty = the stock bot_difficulty_<team> gametype setting (docs/notes/bots.md).
        # -1 leaves the lobby's row alone; 4 = the CUSTOM struct built from the knobs below.
        ("gf_bot_diff_allies", "Difficulty: allies", "choice",
         [("Lobby's value", -1), ("Recruit", 0), ("Regular", 1), ("Hardened", 2),
          ("Veteran", 3), ("CUSTOM", 4)], -1),
        ("gf_bot_diff_axis", "Difficulty: axis", "choice",
         [("Lobby's value", -1), ("Recruit", 0), ("Regular", 1), ("Hardened", 2),
          ("Veteran", 3), ("CUSTOM", 4)], -1),
        ("gf_bot_passive", "Passive (ignore all)", "toggle", None, 0),
    ],
    # CUSTOM knobs (used when a team's difficulty = CUSTOM). Stock recruit/regular/hardened/
    # veteran reference values live in TIPS below (hover the label). Rendered in two columns.
    "Custom bot tuning": [
        ("gf_bot_hit", "Hit chance %", "int", (0, 100, 5), 100),
        ("gf_bot_head", "Headshot %", "int", (0, 100, 5), 50),
        ("gf_bot_react", "Aim delay (ms)", "int", (0, 3000, 50), 100),
        ("gf_bot_fire", "Fire window (ms)", "int", (100, 3000, 100), 1000),
        ("gf_bot_hip", "Hipfire %", "int", (0, 100, 5), 100),
        ("gf_bot_far", "Long-range %", "int", (0, 100, 5), 90),
        ("gf_bot_semi", "Semi tap (ms)", "int", (0, 2000, 50), 100),
        ("gf_bot_burst", "Burst delay (ms)", "int", (0, 2000, 50), 100),
        ("gf_bot_moveshoot", "Move + shoot", "toggle", None, 1),
        ("gf_bot_fastaim", "Look speed", "choice",
         [("Slow", 0), ("Fast", 1), ("Max", 2)], 1),
        ("gf_bot_sprint", "Sprint", "toggle", None, 1),
        ("gf_bot_melee", "Melee", "toggle", None, 1),
        ("gf_bot_prone", "Prone", "toggle", None, 1),
        ("gf_bot_slide", "Slide", "toggle", None, 1),
        ("gf_bot_crouch", "Crouch", "toggle", None, 1),
    ],
    "Movement": [
        ("gf_gravity", "Gravity", "int", (20, 1600, 20), 800),
        ("gf_jump_boost", "Jump boost (u/s)", "int", (0, 3000, 50), 0),
        ("gf_speed", "Move speed %", "int", (25, 400, 25), 100),
        ("gf_falldamage", "Fall damage", "toggle", None, 0),
        ("gf_oob", "Out of bounds (restricted area)", "choice",
         [("Disabled - no warning, no death (default)", 1), ("Stock", 0)], 1),
        ("gf_jump", "Jump height", "int", (-1, 1000, 10), -1),
        ("gf_fly_speed", "Fly speed", "choice",
         [("10", 10), ("20", 20), ("40", 40), ("80", 80)], 20),
        ("gf_fly_fast", "Fly sprint speed", "choice",
         [("30", 30), ("60", 60), ("120", 120), ("240", 240)], 60),
    ],
    "Vehicle mode": [
        # gunfight_menu "Vehicle MODE" page (docs/notes/vehicle-mode.md): everyone spawns already
        # riding this map's ride of the class; nothing resident = everyone on foot (host feed says so).
        # Plain dvars (not the packed store). A change lands on the next spawn, or now via Apply now.
        ("gf_vehmode", "Everyone spawns riding", "choice",
         [("Off", 0), ("Motorcycles", 1), ("Attack helicopters (Hind)", 2),
          ("Helicopters any map (care package heli)", 3), ("Snowmobiles", 4),
          ("Quads + buggies", 5), ("Tanks + APCs", 6), ("Cars + trucks", 7),
          ("Streak gunship heli (seat untested)", 8), ("AUTO - lightest ride, else care heli", 9)], 0),
        ("gf_veh_lock", "Locked in (cannot get off)", "toggle", None, 1),
        ("gf_veh_hp", "Vehicle HP %", "int", (10, 400, 10), 100),
        ("gf_veh_alt", "Heli spawn height (u)", "int", (40, 1500, 20), 300),
        ("gf_dbg_veh", "Debug: VEHMODE line", "choice", [("Off", 0), ("On", 1)], 0),
    ],
    "Overtime zone": [
        # gunfight_menu "Overtime zone" page (docs/notes/overtime-zone.md). Off = HP tiebreak.
        ("gf_zone", "Overtime zone", "choice",
         [("Off (HP tiebreak)", 0), ("On (next round)", 1)], 0),
        ("gf_zone_overtime", "Overtime (s)", "choice", [("10", 10), ("20", 20), ("30", 30)], 20),
        ("gf_zone_capture", "Capture (s)", "choice", [("3", 3), ("5", 5), ("10", 10)], 5),
        ("gf_zone_radius", "Zone radius", "int", (32, 512, 16), 128),
    ],
    "Spawns": [
        ("gf_spawn_guard", "Spawn guard", "choice",
         [("Auto (default)", 2), ("Force (every map)", 1), ("Off", 0)], 2),
        ("gf_strike", "Crossroads: Strike layout under Gunfight", "choice",
         [("Off (full map)", 0), ("On", 1)], 0),
        ("gf_spawn_family", "Spawn family (markers to build from)", "choice",
         [("AUTO - authored S&D starts, else TDM starts (default)", 8), ("TDM (measured good)", 1),
          ("None - engine / geometric", 0), ("S&D", 2),
          ("Domination", 3), ("CTF", 4), ("Hardpoint", 5), ("Control", 6), ("FFA", 7)], 8),
        ("gf_spawn_pick", "Side pick", "choice",
         [("Near - gap based (closer up)", 0), ("Far ends - like TDM openings", 1)], 0),
        ("gf_spawn_gap", "Guard gap (units between sides)", "choice",
         [("1200", 1200), ("1800", 1800), ("2400", 2400), ("3200", 3200)], 1800),
        ("gf_spawn_autospread", "Auto trip dist", "int", (0, 8000, 100), 2500),
        ("gf_spawn_diag", "Spawn diagnostics", "choice", [("Off", 0), ("On", 1)], 1),
    ],
    "Session / Map": [
        ("gf_map_method", "Map switch method", "choice",
         [("Session (lobby follows)", 1), ("Carry (load-time)", 0)], 1),
        ("gf_autoswitch", "Auto-Gunfight on inject", "choice", [("Off", 0), ("On", 1)], 0),
        ("gf_switch_wait", "Switch wait (s)", "choice",
         [("0 (none)", 0), ("5", 5), ("25 (proven)", 25)], 0),
    ],
    "Display": [
        ("gf_menu_lines", "In-game rows", "int", (2, 12, 1), 3),
        # Default 2 since 2026-09-14 (klaze): menu carousel centre + status in the feed + info in
        # the hint row. The 2026-09-14 freeze was a torn dvar, since clamped; SPLIT is bounded.
        ("gf_menu_region", "Panel region", "choice",
         [("Menu centre + info feed + hint", 2), ("Lower-left feed", 0), ("Center", 1),
          ("Menu feed + status centre", 3)], 2),
        ("gf_feed_lines", "Feed lines", "int", (2, 12, 1), 14),
        ("gf_menu_hspan", "Centre carousel width (items)", "int", (1, 9, 1), 4),
        ("gf_caster_probe", "Caster input probe", "choice", [("Off", 0), ("On", 1)], 1),
        # Debug feed: each tool prints ONE complete feed line every 3 s while on.
        ("gf_census", "Debug: settings census", "choice",
         [("Off", 0), ("As launched", 1), ("Live", 2)], 0),
        ("gf_dbg_spawn", "Debug: spawn placements", "choice", [("Off", 0), ("On", 1)], 0),
        ("gf_dbg_structs", "Debug: spawn structs + lists", "choice", [("Off", 0), ("On", 1)], 0),
        ("gf_dbg_families", "Debug: spawn families + guard", "choice", [("Off", 0), ("On", 1)], 0),
        ("gf_dbg_match", "Debug: match info", "choice", [("Off", 0), ("On", 1)], 0),
        ("gf_dbg_flags", "Debug: marker flags census", "choice", [("Off", 0), ("On", 1)], 0),
        ("gf_dbg_assets", "Debug: asset census (vehicles + props)", "choice", [("Off", 0), ("On", 1)], 0),
    ],
}

# Hover text for labels whose reference detail was trimmed to keep the grid tight.
TIPS = {
    "gf_prematch": "Pre-match countdown (s). -1 = use the lobby's own row. Stock rows 5-60.",
    "gf_preround": "Pre-round countdown (s). -1 = use the lobby's own row. Stock rows 0-30.",
    "gf_roundwinlimit": "First team to N round wins ends the match. -1 = leave the lobby's value.",
    "gf_roundlimit": "Hard cap on rounds played. -1 = leave the lobby's value.",
    "gf_rounds_loadout": "Rounds before the loadout rotates. -1 = leave the lobby's value.",
    "gf_gravity": "bg_gravity. Stock 800; lower = floatier.",
    "gf_jump_boost": "Extra up-velocity (u/s) added at takeoff. 0 = off.",
    "gf_falldamage": "Off pushes the fall-damage thresholds out of reach, so boosted jumps land clean.",
    "gf_oob": "Disabled = nobody gets the restricted-area warning, countdown or death (stock's own per-player disable_oob switch, re-set every spawn). Applies at the next spawn, or now with Apply now.",
    "gf_jump": "Builtin jump height. -1 = engine default (untested).",
    "gf_vehmode": "Motorcycles: Diesel / Cartel / Collateral / Fireteam maps. Hind: Collateral + Fireteam maps. Care package heli: every map (flies, unarmed). Snowmobiles: Crossroads / Alpine. Quads + buggies: Collateral / Fireteam. Tanks: Crossroads (APC on Diesel / Checkmate). Cars: Cartel / Fireteam. A class this map lacks = everyone on foot.",
    "gf_veh_lock": "Riders cannot leave the seat (stock's disable_usability layer + a re-seat watcher). Live: applies to riders now.",
    "gf_veh_hp": "Percent of the asset's default health. 25 makes a Hind killable by rifles; 400 makes bikes tanky. Next ride.",
    "gf_veh_alt": "Air rides spawn this high above the spawn point (ceiling-traced). Next ride.",
    "gf_spawn_guard": "Central-spawn guard (untested - test solo first).",
    "gf_map_method": "Session = switchmap_load, the lobby follows. Carry = load-time override (UI stays stale).",
    "gf_camo": "Camo forced on every pool weapon each spawn. Ids 1-121 via the in-game 'by ID' page.",
    # Custom bot tuning - stock recruit / regular / hardened / veteran reference values:
    "gf_bot_diff_allies": "Per-team difficulty. -1 leaves the lobby's row; CUSTOM uses the tuning knobs.",
    "gf_bot_diff_axis": "Per-team difficulty. -1 leaves the lobby's row; CUSTOM uses the tuning knobs.",
    "gf_bot_hit": "Hit chance %. Stock 40 / 50 / 60 / 90.",
    "gf_bot_head": "Headshot chance %. Stock 0 / 3 / 10 / 20.",
    "gf_bot_react": "Aim / reaction delay (ms). Stock 1400 / 1100 / 700 / 300.",
    "gf_bot_fire": "Fire-window (ms). Stock 300 / 400 / 500 / 700.",
    "gf_bot_hip": "Hipfire accuracy %. Stock 50 / 50 / 60 / 70.",
    "gf_bot_far": "Long-range accuracy %. Stock 100 / 80 / 66 / 50.",
    "gf_bot_semi": "Semi-auto tap delay (ms). Stock 800 / 600 / 400 / 150.",
    "gf_bot_burst": "Burst delay (ms). Stock 1200 / 900 / 700 / 250.",
    "gf_bot_fastaim": "Look / turn speed: Slow (recruit) / Fast (veteran) / Max.",
    # Expanded feature set (matches the in-game menu pages):
    "gf_switch_sides": "Mod-owned = one coupled flip per rotation. Stock = both engine paths (may double-flip).",
    "gf_customcac": "Off = the mod's Gunfight loadouts. On = each player's own custom classes.",
    "gf_profile": "When a Gunfight level runs on another mode's settings (only an in-match Switch NOW from TDM does that; a lobby launch already gets the real blob), assert the real Gunfight blob (column A, 2026-09-14): 1 life/round, no kill limit, fixed loadouts, no streaks. Off = the raw hybrid.",
    "gf_zone": "Capture-zone overtime (needs gf_zone entities). Off = health tiebreak.",
    "gf_zone_radius": "Capture-zone radius in units. Stock ~128.",
    "gf_spawn_guard": "Off / Auto (engine start spawns when it has them, the guard's anchors when it has none - e.g. Crossroads under Gunfight) / Force (anchors always).",
    "gf_strike": "Crossroads loads the full 12v12 map under Gunfight. On = keep the Strike clips server-side - but clients (joiners too) still draw the 12v12 minimap and bounds, so walls stand on open ground. Off by default. No-op on other maps.",
    "gf_spawn_family": "Which markers the spawn guard builds from. AUTO = the map's AUTHORED team start spawns (mode flag + start flag + group_index on mp_spawn_point, the same points the engine's own start list holds): S&D's when the map has them on both sides, else TDM's, else the old geometric split. A named mode = that mode's markers (its authored starts when it has them, else geometric). Every spawn goes on them.",
    "gf_dbg_assets": "Debug feed: two lines - VEHICLES (which veh_t9_* names are resident vehicle assets on this map, by index:name) and PROPS (this map's Prop Hunt table: rows, size buckets, row-0 model + residency).",
    "gf_dbg_flags": "Debug feed: one line - which mode/side flag fields the map's spawn markers carry, with value tallies.",
    "gf_spawn_pick": "Near = two groups around the map centre at the gap (TDM's respawn zone). Far ends = the two outermost marker groups (TDM's opening spawns), rebuilt from markers so it works where the engine has none.",
    "gf_fly_speed": "Fly mode speed (Player -> Fly). Sprint speed is the separate field.",
    "gf_fly_fast": "Fly mode speed while sprinting.",
    "gf_menu_hspan": "How many menu items the centre carousel shows side by side (default 4).",
    "gf_spec_slots": "Spectator/caster slots added on top of team size x 2 in the maxplayers write (capped at the lobby budget), so a spectator does not take a player slot when filling bots.",
    "gf_spawn_gap": "Target distance between the two sides the guard builds (tightest marker groups either side of the map centre, facing each other).",
    "gf_spawn_autospread": "AUTO trips when the nearest start spawn is farther than obj-radius + this (units).",
    "gf_spawn_diag": "Print spawn diagnostics to the feed.",
    "gf_autoswitch": "On = auto-switch back to Gunfight when a non-GF gametype is injected.",
    "gf_switch_wait": "Seconds held during a session switch. 25 proven; 0 = cp-style, untested.",
    "gf_feed_lines": "Lower-left feed lines the menu primes (latched at HUD build, ~4-5 visible).",
    "gf_menu_region": "Where the menu draws. HINT panel = the use-prompt widget; others use feed / centre.",
    "gf_caster_probe": "Log a caster's button inputs to the feed (for wiring the caster keyset).",
    "gf_census": "Debug feed: one line every 3 s with all 46 settings (short keys, legend in docs/notes/mode-remnants.md). As launched = the blob before the mod writes; Live = now.",
    "gf_dbg_spawn": "Debug feed: one line every 3 s - this round's engine/guard placements for every player (name:team:how:distance-to-nearest-marker:PILE) plus the guard state.",
    "gf_dbg_structs": "Debug feed: one line - mp_spawn_point counts, the first structs' fields, and the engine's spawn list names.",
    "gf_dbg_families": "Debug feed: one line - spawn-struct family counts, legacy detector numbers, what the guard built.",
    "gf_dbg_match": "Debug feed: one line - the Show-match-info readout (mode/map, round, teams, timer, loadout, spawn guard, movement).",
}

# Audited names (docs/reference/bocw-maps.md). display -> (map, gametype-note)
MAPS_6V6 = [
    ("Amerika", "mp_amerika"), ("Apocalypse", "mp_apocalypse"),
    ("Armada Strike", "mp_black_sea"), ("Cartel", "mp_cartel"),
    ("Checkmate", "mp_kgb"), ("Collateral Strike", "mp_dune"),
    ("Crossroads (full 12v12)", "mp_tundra"), ("Deprogram", "mp_firebase"),
    ("Diesel", "mp_sm_gas_station"), ("Drive-In", "mp_drivein_rm"),
    ("Echelon", "mp_echelon"), ("Express", "mp_express_rm"),
    ("Garrison", "mp_tank"), ("Hijacked", "mp_hijacked_rm"),
    ("Jungle", "mp_jungle_rm"), ("Miami", "mp_miami"),
    ("Miami Strike", "mp_miami_strike"), ("Moscow", "mp_moscow"),
    ("Nuketown '84", "mp_nuketown6"), ("Raid", "mp_raid_rm"),
    ("Rush", "mp_paintball_rm"), ("Satellite", "mp_satellite"),
    ("Slums", "mp_slums_rm"), ("Standoff", "mp_village_rm"),
    ("The Pines", "mp_mall"), ("WMD", "mp_russianbase_rm"),
    ("Yamantau", "mp_cliffhanger"), ("Zoo", "mp_zoo_rm"),
]
MAPS_GF = [
    ("Amsterdam", "mp_sm_amsterdam"), ("Game Show", "mp_sm_game_show"),
    ("Gluboko", "mp_sm_vault"), ("ICBM", "mp_sm_central"),
    ("KGB", "mp_sm_finance"), ("Mansion", "mp_sm_market"),
    ("Showroom", "mp_sm_deptstore"), ("U-Bahn", "mp_sm_berlin_tunnel"),
]
# The full 12v12 layouts of the large maps: same files, but the map scripts open the 12v12
# boundary only for a 10v10/12v12 gametype string, so these pair the map with tdm10v10 and
# the gametype box is overridden when one is picked (mirrors the menu's "12v12 layouts" page).
MAPS_12V12 = [
    ("Armada 12v12 - TDM 10v10", "mp_black_sea"), ("Collateral 12v12 - TDM 10v10", "mp_dune"),
    ("Crossroads 12v12 - TDM 10v10", "mp_tundra"),
]
# Fireteam / Multi-team maps (40-player dedicated-server modes; the menu marks them untested).
# Projectile weapons (docs/notes/projectiles.md §6): every one resident on all 36 MP maps.
PROJ_WEAPONS = [
    ("RPG rocket", "launcher_freefire_t9"),
    ("Cigma missile", "launcher_standard_t9"),
    ("Crossbow bolt", "special_crossbow_t9"),
    ("M79 grenade", "special_grenadelauncher_t9"),
    ("Combat bow arrow", "sig_bow_flame"),
    ("Strafe run rocket", "straferun_rockets"),
    ("Cruise missile bomblet", "remote_missile_bomblet"),
    ("Jet fighter missile", "jetfighter_missile"),
    ("Frag grenade", "frag_grenade"),
]

# Universal props (docs/notes/static-props.md §5b): the menu's prop_universal() list, by label.
# The GSC matches the label or the model name. ⚠ gf_cmd_arg rides a 47-byte bridge slot
# ("set gf_cmd_arg " is 15 of them), so the value sent is the LABEL, never a long model name.
# The in-game Vehicles page's master list (gunfight_menu.gsc veh_master): the app names a vehicle by
# its INDEX in that list (gf_cmd_action vehspawn <i>) because an asset name does not fit the 47-byte
# bridge slot. Read out of the GSC source at startup so the two cannot drift; the baked copy below is
# the fallback when the repo is not beside the app (the frozen exe). kind 0 = drivable, 1 = other
# (streak / intro / turret - may not be enterable). The GSC answers "no vehicle assets on this map"
# itself for anything not resident where you are. docs/notes/vehicles.md, vehicle-mode.md.
VEHICLE_MASTER_BAKED = [
    (0, 'Light buggy (FAV)', 0),
    (1, 'Light buggy (FAV) alt', 0),
    (2, 'Heavy buggy (FAV)', 0),
    (3, 'Motorcycle', 0),
    (4, 'Motorcycle alt', 0),
    (5, 'Motorcycle (slow)', 0),
    (6, 'Quad / ATV', 0),
    (7, 'Snowmobile', 0),
    (8, 'Snowmobile alt', 0),
    (9, 'Snowmobile (single seat)', 0),
    (10, 'Sedan', 0),
    (11, 'Sedan alt', 0),
    (12, 'Sedan (BO4 midsize)', 0),
    (13, 'Light truck', 0),
    (14, 'Light truck alt', 0),
    (15, 'Light truck (base)', 0),
    (16, 'Transport truck', 0),
    (17, 'Transport truck alt', 0),
    (18, 'Transport truck (objective)', 0),
    (19, 'Tank T-72', 0),
    (20, 'Tank T-72 alt', 0),
    (21, 'Tank T-72 (base)', 0),
    (22, 'APC (heavy)', 0),
    (23, 'APC (heavy, open turret)', 0),
    (24, 'Hind gunship', 0),
    (25, 'Armada heli (campaign)', 0),
    (26, 'Jetski', 0),
    (27, 'Jetski alt', 0),
    (28, 'Tactical raft', 0),
    (29, 'Tactical raft alt', 0),
    (30, 'Tactical raft (grey)', 0),
    (31, 'Tactical raft (grey, base)', 0),
    (32, 'PBR gunboat', 0),
    (33, 'PBR gunboat alt', 0),
    (34, 'Chopper Gunner (streak)', 1),
    (35, 'Care package heli - FLIES ON EVERY MAP', 0),
    (36, 'Vehicle-drop heli (streak)', 1),
    (37, 'RC-XD', 1),
    (38, 'RC-XD alt', 1),
    (39, 'Exfil chopper (VIP escort)', 1),
    (40, 'Exfil helicopter (Fireteam)', 1),
    (41, 'AC-130 gunship (streak)', 1),
    (42, 'Attack helicopter (streak)', 1),
    (43, 'Attack helicopter guard (streak)', 1),
    (44, 'VTOL Forger (streak)', 1),
    (45, 'Strafe run plane (streak)', 1),
    (46, 'Air transport (intro)', 1),
    (47, 'Air transport (infiltration, BO4)', 1),
    (48, 'Mounted MG tripod', 1),
    (49, 'Express train', 1),
    (50, 'Intro cinematic vehicle (Checkmate / Satellite)', 1),
    (51, 'Intro cinematic tank (Garrison / Amerika)', 1),
    (52, 'Intro cinematic vehicle (Garrison)', 1),
    (53, 'Intro cinematic vehicle (Miami)', 1),
    (54, 'Intro cinematic vehicle (Moscow cia)', 1),
    (55, 'Intro cinematic vehicle (Moscow kgb)', 1),
    (56, 'Intro cinematic helicopter (The Pines)', 1),
    (57, 'Intro cinematic APC (The Pines)', 1),
    (58, 'Intro cinematic APC (Amerika)', 1),
    (59, 'Intro cinematic vehicle (Echelon)', 1),
    (60, 'Intro cinematic vehicle (Yamantau)', 1),
    (61, 'Intro cinematic vehicle (Apocalypse)', 1),
    (62, 'Intro cinematic vehicle (Cartel)', 1),
    (63, 'Intro cinematic vehicle (Collateral cia)', 1),
    (64, 'Intro cinematic vehicle (Collateral kgb)', 1),
    (65, 'Intro cinematic vehicle (Crossroads kgb)', 1),
    (66, 'Intro cinematic vehicle (Crossroads)', 1),
    (67, 'Intro cinematic vehicle (Crossroads kgb 2)', 1),
    (68, 'Intro cinematic vehicle (Crossroads cia)', 1),
]


def _load_vehicle_master() -> list[tuple[int, str, int]]:
    """(index, label, kind) rows of veh_master(), parsed from the GSC when it is reachable."""
    here = os.path.dirname(os.path.abspath(__file__))
    gsc = os.path.join(here, "..", "..", "src", "gunfight_menu", "scripts", "gunfight_menu.gsc")
    try:
        text = open(gsc, encoding="utf-8", errors="replace").read()
        body = text[text.index("function private veh_master()"):]
        body = body[:body.index("\nfunction private ", 10)]
        rows = re.findall(r'veh_def\(\s*m,\s*#?"[^"]+",\s*"([^"]+)",\s*(\d)', body)
        if len(rows) >= 10:
            return [(i, label, int(kind)) for i, (label, kind) in enumerate(rows)]
    except Exception:
        pass
    return list(VEHICLE_MASTER_BAKED)


VEHICLE_MASTER = _load_vehicle_master()

PROP_UNIVERSAL = [
    ("Park bench", "p9_usa_bench_01"), ("Bicycle", "p9_usa_bicycle_01"), ("Couch", "p9_usa_couch_04"),
    ("Dumpster", "p9_usa_dumpster_01_full"), ("Mailbox", "p9_usa_mailbox_01"),
    ("Street light", "p9_usa_street_light_01"), ("Soda machine", "p9_usa_vending_machine_soda_02"),
    ("Target dummy", "p9_usa_kgb_target_dummy_01"), ("Beach chair", "p9_usa_chair_beach"),
    ("Surfboard", "p9_usa_surf_longboard_01"), ("Arcade game", "p9_nt6_arcade_game"),
    ("Washing machine", "p9_nt6_machine_washing_dirty"), ("Vintage fridge", "p9_nt6_refrigerator_vintage_closed_02"),
    ("Wooden chair", "p9_nt6_chair_wood"), ("Tire barricade", "p9_nt6_barricade_tire_01"),
    ("Snowman", "p9_nt6x_win_snowman"), ("Arcade cabinet", "p9_mal_arcade_cabinet_08"),
    ("Kiddie rocket ride", "p9_mal_rocket_ride_01"), ("Scissor lift", "p9_mal_scissor_lift_01"),
    ("Bean bag", "p9_mal_bean_bag_chair_sml"), ("Phone booth", "p9_rus_amk_telephonebooth_01_closed_v2_wet"),
    ("Long park bench", "p9_rus_bench_park_long"), ("Oil drum", "p9_rus_oil_drum_01"),
    ("Computer server", "p9_rus_computer_server_02"), ("Concrete barrier 144", "p9_ger_kgb_mount_barrier_concrete_144"),
    ("Metal barrel", "p9_ger_tank_barrel_metal_01"), ("Gas pump", "p9_ger_tank_gas_pump_01"),
    ("Sandbag cover", "p9_lat_sandbag_cover_02_grime"), ("Czech hedgehog", "p9_lat_hedgehog_metal_snow"),
    ("Large ammo crate", "p9_usa_large_ammo_crate_01"), ("Hay bale", "p9_rm_zoo_hay_bale_sqr"),
    ("Wooden spool", "p9_rm_pai_wooden_spool"), ("Water cooler", "p9_rm_rai_water_cooler_metal_full"),
    ("Palm tree", "p9_foliage_tree_palm_coconut_lrg_01"), ("Pot of gold", "p9_pot_of_gold_pristine"),
    ("Dirty bomb", "p9_wz_dirty_bomb_01"), ("155mm artillery gun", "p9_m114_155mm_artillery_gun_01_pickup"),
    ("Rusted barrel (PH)", "p9_barrel_metal_rusted_01_prophunt"), ("Concrete K-rail (PH)", "p9_krail_concrete_worn_01_prophunt"),
    ("Vase (PH)", "p9_rm_rai_dub_vase_prophunt"), ("Satellite panel (PH)", "p9_ang_satellite_panel_02_prophunt"),
    ("Mattress (PH)", "p9_nt6_abandoned_mattress_01_prophunt"), ("Mannequin M1 (PH)", "p9_nt6_mannequin_clothes_male_01_dirty_full_prophunt"),
    ("Server rack (PH)", "p9_ger_tank_computer_server_diagnostic_01_silver_prophunt"),
    ("Tank tread rolls (PH)", "p9_ger_tank_tank_tread_rolls_01_prophunt"),
]

MAPS_FT = [
    ("Alpine", "wz_ski_slopes"), ("Duga", "wz_duga"), ("Golova", "wz_golova"),
    ("Ruka", "wz_forest"), ("Sanatorium", "wz_sanatorium"),
]
GAMETYPES = ["gunfight", "gunfight_3v3", "tdm", "tdm10v10", "dm", "dom", "koth", "sd", "conf", "control"]

# Weapons for the give-weapon action, extracted from gunfight_menu.gsc wp_* pages.
# (display, internal name); the app sends the internal name as gf_cmd_arg.
WEAPONS = {
    "Assault rifles": [
        ("XM4", "ar_standard_t9"),
        ("AK-47", "ar_damage_t9"),
        ("Krig 6", "ar_accurate_t9"),
        ("QBZ-83", "ar_fastfire_t9"),
        ("FFAR 1", "ar_fasthandling_t9"),
        ("Groza", "ar_mobility_t9"),
        ("FARA 83", "ar_slowfire_t9"),
        ("C58", "ar_slowhandling_t9"),
        ("EM2", "ar_british_t9"),
        ("Vargo 52 ?", "ar_season6_t9"),
        ("Grav ?", "ar_soviet_t9"),
    ],
    "SMGs": [
        ("MP5", "smg_standard_t9"),
        ("Milano 821", "smg_handling_t9"),
        ("AK-74u", "smg_heavy_t9"),
        ("KSP 45", "smg_burst_t9"),
        ("Bullfrog", "smg_capacity_t9"),
        ("MAC-10", "smg_fastfire_t9"),
        ("LC10", "smg_accurate_t9"),
        ("PPSh-41", "smg_spray_t9"),
        ("OTs 9 ?", "smg_cqb_t9"),
        ("TEC-9 ?", "smg_semiauto_t9"),
        ("LAPA ?", "smg_season6_t9"),
        ("smg_flechette_t9 - unknown", "smg_flechette_t9"),
    ],
    "Tactical rifles": [
        ("M16", "tr_powerburst_t9"),
        ("AUG ?", "tr_longburst_t9"),
        ("CARV.2", "tr_fastburst_t9"),
        ("DMR 14", "tr_precisionsemi_t9"),
        ("Type 63", "tr_damagesemi_t9"),
    ],
    "LMGs": [
        ("Stoner 63", "lmg_light_t9"),
        ("RPD", "lmg_slowfire_t9"),
        ("M60", "lmg_fastfire_t9"),
        ("MG 82", "lmg_accurate_t9"),
    ],
    "Snipers": [
        ("Pelington 703", "sniper_standard_t9"),
        ("LW3 Tundra", "sniper_quickscope_t9"),
        ("M82", "sniper_powersemi_t9"),
        ("ZRG 20mm ?", "sniper_cannon_t9"),
        ("Swiss K31 ?", "sniper_accurate_t9"),
    ],
    "Shotguns": [
        ("Hauer 77", "shotgun_pump_t9"),
        ("Gallo SA12", "shotgun_fullauto_t9"),
        ("Streetsweeper", "shotgun_semiauto_t9"),
        (".410 Ironhide", "shotgun_leveraction_t9"),
    ],
    "Pistols": [
        ("1911", "pistol_semiauto_t9"),
        ("Magnum", "pistol_revolver_t9"),
        ("Diamatti", "pistol_burst_t9"),
        ("AMP63", "pistol_fullauto_t9"),
        ("Marshal", "pistol_shotgun_t9"),
        ("1911 akimbo", "pistol_semiauto_t9_dw"),
        ("Magnum akimbo", "pistol_revolver_t9_dw"),
        ("Diamatti akimbo", "pistol_burst_t9_dw"),
        ("AMP63 akimbo", "pistol_fullauto_t9_dw"),
        ("Marshal akimbo", "pistol_shotgun_t9_dw"),
    ],
    "Launchers + special": [
        ("Cigma 2", "launcher_standard_t9"),
        ("RPG-7", "launcher_freefire_t9"),
        ("M79", "special_grenadelauncher_t9"),
        ("R1 Shadowhunter", "special_crossbow_t9"),
        ("Nail Gun", "special_nailgun_t9"),
        ("Ballistic Knife", "special_ballisticknife_t9_dw"),
    ],
    "Melee": [
        ("Knife", "knife_loadout"),
        ("Sledgehammer", "melee_sledgehammer_t9"),
        ("Wakizashi", "melee_wakizashi_t9"),
        ("Machete", "melee_machete_t9"),
        ("E-Tool", "melee_etool_t9"),
        ("Baseball Bat", "melee_baseballbat_t9"),
        ("Mace", "melee_mace_t9"),
        ("Sai", "melee_sai_t9_dw"),
        ("Cane", "melee_cane_t9"),
        ("Battle Axe", "melee_battleaxe_t9"),
        ("Hammer & Sickle ?", "melee_coldwar_t9_dw"),
        ("melee_scythe_t9 - unknown", "melee_scythe_t9"),
        ("Bowie Knife", "melee_bowie"),
        ("Bowie Knife - bloody", "melee_bowie_bloody"),
        ("Knife - Scream", "hash_28fdaa999c8aa3af"),
        ("Knife - Infected", "hash_3f47e8be065a0dc0"),
    ],
    "Fun (untested)": [
        ("Ray Gun", "ray_gun"),
        ("Flamethrower - Purifier", "hero_flamethrower"),
        ("Annihilator", "hero_annihilator"),
        ("War Machine - pineapple gun", "hero_pineapplegun"),
        ("Death Machine - sig_lmg", "sig_lmg"),
        ("Sparrow bow - sig_bow_flame", "sig_bow_flame"),
        ("Turret gun - ultimate_turret", "ultimate_turret"),
    ],
}


class App:
    # Config sections split across two scrolling columns (balanced by height).
    LEFT = ["Teams", "Round", "Loadout", "Match", "Spawns", "Display"]
    RIGHT = ["Bots", "Custom bot tuning", "Movement", "Vehicle mode", "Overtime zone", "Session / Map"]
    WIDE = {"Custom bot tuning"}          # rendered in two field-columns to keep it short
    _DUR = {"Once": 0, "5s": 5, "10s": 10, "30s": 30, "60s": 60, "Fixed": -1}
    # Cold War text colour codes (^0-^9) with an approximate on-screen colour for the cheat sheet.
    CODES = [
        ("^0", "black", "#0a0a0a"),
        ("^1", "red", "#ff3b3b"),
        ("^2", "green", "#46d246"),
        ("^3", "yellow", "#ffd21e"),
        ("^4", "blue", "#5478ff"),
        ("^5", "cyan", "#46d2ff"),
        ("^6", "magenta", "#ff5cff"),
        ("^7", "white", "#ffffff"),
        ("^8", "grey (team)", "#9a9a9a"),
        ("^9", "grey", "#7a7a7a"),
    ]

    def __init__(self, root: tk.Tk, live: bool):
        self.root = root
        self.live = live
        self.vars: dict[str, tk.Variable] = {}
        # Only send config dvars that DIFFER from their default (or were sent before, so a
        # reset-to-default still applies). Each `set gf_x` registers a dvar in the game's store,
        # which has a hard cap - blasting all ~50 every apply helped overflow it (crash 2026-09-14).
        self._defaults = {dvar: default for fields in CONFIG.values()
                          for dvar, _l, _k, _s, default in fields}
        self._labels = {dvar: _l for fields in CONFIG.values()
                        for dvar, _l, _k, _s, default in fields}
        # Last value we actually SENT for each dvar (seeded to the app defaults). A field is
        # "pending" only when its current value differs from this - unlike _sent/_touched, this
        # is NOT sticky, so a restart-required field stops prompting once applied or reverted.
        self._applied = dict(self._defaults)
        self._sent: set = set()
        # Anything the user TOUCHES in the UI is sent on the next apply even when it sits at
        # the app default - the in-game menu (or a previous app run) may have left the dvar
        # at another value, and "unchanged from default" then silently did nothing
        # (klaze 2026-09-15: unchecking bots passive / fall damage + Apply had no effect).
        self._touched: set = set()
        # The bridge is the working control path; the old DvarBackend memory-write is retired
        # here (route A - external dvar write - was proven not to reach the GSC dvar store).
        self.backend = BridgeBackend(dry_run=not live) if bridge_channel is not None else None

        root.title("Gunfight Host Control" + ("  [LIVE]" if live else "  [DRY-RUN]"))
        try:                                    # window/taskbar icon (gunfight.us logo)
            self._icon = tk.PhotoImage(file=os.path.join(ASSETS, "logo.png"))
            root.iconphoto(True, self._icon)
        except Exception:
            pass
        root.geometry("900x880")
        root.minsize(760, 560)

        style = ttk.Style()
        for theme in ("vista", "clam"):     # vista is native on Windows; clam is the fallback
            if theme in style.theme_names():
                style.theme_use(theme)
                break
        root.option_add("*Font", ("Segoe UI", 9))
        style.configure("TLabelframe.Label", font=("Segoe UI", 9, "bold"), foreground="#20406a")
        style.configure("Accent.TButton", font=("Segoe UI", 9, "bold"))

        self._banner()
        nb = ttk.Notebook(root)
        nb.pack(fill="both", expand=True, padx=8, pady=(4, 4))
        nb.add(self._config_tab(nb), text="   Config   ")
        nb.add(self._actions_tab(nb), text="   Actions   ")
        nb.add(self._inject_tab(nb), text="   Inject / Status   ")
        self._logbox()
        self._connect()
        self._tick_status()

    def _banner(self):
        c = "#7a1f1f" if self.live else "#20406a"
        bar = tk.Frame(self.root, bg=c)
        bar.pack(fill="x")
        txt = ("● LIVE - sends commands to the running game over the bridge"
               if self.live else "○ DRY-RUN - shows the commands only, sends nothing")
        tk.Label(bar, text=txt, bg=c, fg="white", font=("Segoe UI", 10, "bold")).pack(pady=5)

    # ---- Config: a scrollable two-column pane of setting cards ---------------
    def _config_tab(self, nb) -> ttk.Frame:
        tab = ttk.Frame(nb)

        bar = ttk.Frame(tab)
        bar.pack(fill="x", padx=10, pady=(10, 2))
        ttk.Button(bar, text="Apply now", style="Accent.TButton",
                   command=self._apply_live).pack(side="left")
        ttk.Button(bar, text="Next round",
                   command=self._apply_next_round).pack(side="left", padx=6)
        ttk.Button(bar, text="+ Restart",
                   command=self._apply_restart).pack(side="left")
        ttk.Button(bar, text="Reset",
                   command=self._reset).pack(side="left", padx=6)
        # Read the LIVE values out of the running game (config_scan.py, a read-only memory
        # sweep) and snap every field to them - the app is otherwise blind to what the game
        # actually has (in-game menu picks, a previous app run). See config_scan.py.
        ttk.Button(bar, text="Load current",
                   command=self._load_current).pack(side="left", padx=(6, 0))
        # NO "Apply ALL" button: one existed for ~10 minutes on 2026-09-15 and CRASHED the game
        # on first click - ~60 `set gf_*` in one message registers that many dvars at once and
        # the store overflows ("Can't register more dvar", the 2026-09-14 crash class). The
        # touched-field rule above is the safe way to undo an in-game menu value.
        ttk.Label(bar, text="Apply now = live this round · Next round = defers round-safe · Load current = read the game’s live values",
                  foreground="#777").pack(side="left", padx=10)

        inner = self._scrollable(tab)
        left = ttk.Frame(inner)
        right = ttk.Frame(inner)
        left.grid(row=0, column=0, sticky="new")
        right.grid(row=0, column=1, sticky="new")
        inner.columnconfigure(0, weight=1, uniform="cfg")
        inner.columnconfigure(1, weight=1, uniform="cfg")

        for name in self.LEFT:
            self._section(left, name)
        for name in self.RIGHT:
            self._section(right, name)
        return tab

    def _scrollable(self, parent) -> ttk.Frame:
        """A vertically scrolling frame that fills `parent`. Returns the inner frame to
        pack/grid content into; it is kept exactly as wide as the viewport (no h-scroll)."""
        canvas = tk.Canvas(parent, borderwidth=0, highlightthickness=0)
        vsb = ttk.Scrollbar(parent, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=vsb.set)
        vsb.pack(side="right", fill="y")
        canvas.pack(side="left", fill="both", expand=True, padx=(8, 0), pady=4)
        inner = ttk.Frame(canvas)
        win = canvas.create_window((0, 0), window=inner, anchor="nw")
        inner.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.bind("<Configure>", lambda e: canvas.itemconfigure(win, width=e.width))
        # Wheel scroll only while the pointer is over this canvas (don't hijack combos elsewhere).
        canvas.bind("<Enter>", lambda e: canvas.bind_all(
            "<MouseWheel>", lambda ev: canvas.yview_scroll(int(-ev.delta / 120), "units")))
        canvas.bind("<Leave>", lambda e: canvas.unbind_all("<MouseWheel>"))
        return inner

    def _section(self, parent, title):
        fields = CONFIG[title]
        ncols = 2 if title in self.WIDE else 1
        box = ttk.LabelFrame(parent, text=title)
        box.pack(fill="x", padx=6, pady=6)
        for c in range(ncols):
            box.columnconfigure(c * 2 + 1, weight=1)
        for i, (dvar, label, kind, spec, default) in enumerate(fields):
            r, c = divmod(i, ncols)
            self._field(box, dvar, label, kind, spec, default, r, c * 2)

    def _field(self, parent, dvar, label, kind, spec, default, r, c):
        lbl = ttk.Label(parent, text=label, anchor="w")
        lbl.grid(row=r, column=c, sticky="w", padx=(8, 8), pady=3)
        if TIPS.get(dvar):
            _Tip(lbl, TIPS[dvar])
        if kind == "choice":
            var = tk.IntVar(value=default)
            combo = ttk.Combobox(parent, state="readonly",
                                 values=[l for l, _ in spec], width=16)
            combo.current([v for _, v in spec].index(default))
            combo.grid(row=r, column=c + 1, sticky="ew", padx=(0, 8), pady=3)
            combo.bind("<<ComboboxSelected>>",
                       lambda e, s=spec, v=var, cb=combo: v.set(s[cb.current()][1]))
            self.vars[dvar] = var
            var.trace_add("write", lambda *_a, d=dvar: self._touched.add(d))
        elif kind == "int":
            lo, hi, step = spec
            var = tk.IntVar(value=default)
            ttk.Spinbox(parent, from_=lo, to=hi, increment=step, textvariable=var,
                        width=8).grid(row=r, column=c + 1, sticky="w", padx=(0, 8), pady=3)
            self.vars[dvar] = var
            var.trace_add("write", lambda *_a, d=dvar: self._touched.add(d))
        elif kind == "toggle":
            var = tk.IntVar(value=default)
            ttk.Checkbutton(parent, variable=var).grid(row=r, column=c + 1, sticky="w",
                                                       padx=(0, 8), pady=3)
            self.vars[dvar] = var
            var.trace_add("write", lambda *_a, d=dvar: self._touched.add(d))

    # ---- Actions tab --------------------------------------------------------
    def _actions_tab(self, nb) -> ttk.Frame:
        tab = ttk.Frame(nb)
        note = ("Actions send gf_cmd_* triggers over the bridge; the menu's command-poller "
                "runs them host-side.\nStage = the lobby shows the map when the match ends.   "
                "Switch NOW = in-match session switch.")
        tk.Label(tab, text=note, fg="#8a5a00", justify="left").pack(anchor="w", padx=12, pady=(12, 8))
        # The tab outgrew the 880 px window (per-client + teleport rows, 2026-09-15), so
        # its boxes live in the same scrolling frame the Config tab uses.
        body = self._scrollable(tab)

        box = ttk.LabelFrame(body, text="Session switch  (map + gametype)")
        box.pack(fill="x", padx=12, pady=6)
        KEEP = "(keep current map)"      # switch gametype alone - no map needed
        self.map_var = tk.StringVar(value=KEEP)
        allmaps = [KEEP] + [f"{d}  [{m}]" for d, m in MAPS_6V6] + \
                  [f"{d}  [{m}]  (GF)" for d, m in MAPS_GF] + \
                  [f"{d}  [{m}]  (12v12)" for d, m in MAPS_12V12] + \
                  [f"{d}  [{m}]  (Fireteam, untested)" for d, m in MAPS_FT]
        self._maplut = {KEEP: ""}
        self._maplut.update({f"{d}  [{m}]": m for d, m in MAPS_6V6})
        self._maplut.update({f"{d}  [{m}]  (GF)": m for d, m in MAPS_GF})
        self._maplut.update({f"{d}  [{m}]  (12v12)": m for d, m in MAPS_12V12})
        self._maplut.update({f"{d}  [{m}]  (Fireteam, untested)": m for d, m in MAPS_FT})
        # a 12v12 pick carries its own gametype (tdm10v10), like the menu's act_map_gt rows
        self._map_gt = {f"{d}  [{m}]  (12v12)": "tdm10v10" for d, m in MAPS_12V12}
        g = ttk.Frame(box)
        g.pack(fill="x", padx=10, pady=8)
        ttk.Label(g, text="Map").grid(row=0, column=0, sticky="w", pady=4)
        ttk.Combobox(g, state="readonly", values=allmaps, textvariable=self.map_var,
                     width=48).grid(row=0, column=1, sticky="w", padx=8, pady=4)
        self.gt_var = tk.StringVar(value="gunfight")
        ttk.Label(g, text="Gametype").grid(row=1, column=0, sticky="w", pady=4)
        ttk.Combobox(g, state="readonly", values=GAMETYPES, textvariable=self.gt_var,
                     width=22).grid(row=1, column=1, sticky="w", padx=8, pady=4)
        btns = ttk.Frame(box)
        btns.pack(anchor="w", padx=10, pady=(0, 10))
        # Two verbs, same as the in-game pick page. Stage = switchmap_load only: the
        # match keeps running and the pregame lobby shows the map when it ends.
        ttk.Button(btns, text="Stage for lobby (next match)",
                   command=lambda: self._switch(stage=True)).pack(side="left", padx=(0, 6))
        ttk.Button(btns, text="Switch NOW", style="Accent.TButton",
                   command=lambda: self._switch(stage=False)).pack(side="left")

        box2 = ttk.LabelFrame(body, text="Bots / match")
        box2.pack(fill="x", padx=12, pady=6)
        r2 = ttk.Frame(box2)
        r2.pack(anchor="w", padx=10, pady=10)
        for text, cmd in [("Fill with bots", "fillbots"),
                          ("Remove all bots", "removebots"),
                          ("Restart match", "restart")]:
            ttk.Button(r2, text=text, width=16,
                       command=lambda c=cmd: self._cmd(c)).pack(side="left", padx=4)
        # Single-bot verbs (docs/notes/bots.md). gf_cmd_addbot carries WHICH side:
        # 1 auto (smaller side, tie -> opposite the host) / 2 allies / 3 axis.
        box3 = ttk.LabelFrame(body, text="Bots - one at a time")
        box3.pack(fill="x", padx=12, pady=6)
        r3 = ttk.Frame(box3)
        r3.pack(anchor="w", padx=10, pady=10)
        for text, settings in [("Add: auto", {"gf_cmd_action": "addbot", "gf_cmd_arg": "auto"}),
                               ("Add: allies", {"gf_cmd_action": "addbot", "gf_cmd_arg": "allies"}),
                               ("Add: axis", {"gf_cmd_action": "addbot", "gf_cmd_arg": "axis"}),
                               ("Remove one", {"gf_cmd_action": "removebot"}),
                               ("Even up", {"gf_cmd_action": "evenbots"})]:
            ttk.Button(r3, text=text, width=12,
                       command=lambda s=settings: self._write({**s, "gf_cmd_go": 1})
                       ).pack(side="left", padx=4)

        box4 = ttk.LabelFrame(body, text="Host")
        box4.pack(fill="x", padx=12, pady=6)
        r4 = ttk.Frame(box4)
        r4.pack(anchor="w", padx=10, pady=(10, 4))
        ttk.Button(r4, text="Pause match", width=16,
                   command=lambda: self._pause(1)).pack(side="left", padx=4)
        ttk.Button(r4, text="Resume match", width=16,
                   command=lambda: self._pause(2)).pack(side="left", padx=4)
        ttk.Button(r4, text="Announce settings", width=18,
                   command=lambda: self._action("announce")).pack(side="left", padx=4)
        ttk.Button(r4, text="Countdown 5..GO", width=16,
                   command=lambda: self._action("countdown")).pack(side="left", padx=4)
        r5 = ttk.Frame(box4)
        r5.pack(fill="x", padx=10, pady=(4, 2))
        ttk.Label(r5, text="Broadcast").pack(side="left")
        self.say_var = tk.StringVar()
        entry = ttk.Entry(r5, textvariable=self.say_var)
        entry.pack(side="left", fill="x", expand=True, padx=6)
        entry.bind("<Return>", lambda e: self._broadcast())
        ttk.Button(r5, text="Send", command=self._broadcast).pack(side="left", padx=(0, 2))
        ttk.Button(r5, text="Clear", command=self._broadcast_clear).pack(side="left", padx=2)
        ttk.Button(r5, text="Codes", command=self._show_codes).pack(side="left", padx=2)
        r5b = ttk.Frame(box4)
        r5b.pack(anchor="w", padx=10, pady=(0, 10))
        ttk.Label(r5b, text="Location").pack(side="left")
        self.say_loc = tk.IntVar(value=0)
        for txt, val in (("Center", 0), ("Feed", 1), ("Banner", 2)):
            ttk.Radiobutton(r5b, text=txt, variable=self.say_loc, value=val).pack(side="left", padx=(4, 0))
        ttk.Label(r5b, text="     Hold").pack(side="left")
        self.say_dur = tk.StringVar(value="Once")
        ttk.Combobox(r5b, state="readonly", width=7, textvariable=self.say_dur,
                     values=["Once", "5s", "10s", "30s", "60s", "Fixed"]).pack(side="left", padx=4)
        ttk.Label(r5b, text="  Indent").pack(side="left")
        self.say_indent = tk.StringVar(value="0")
        ttk.Spinbox(r5b, from_=0, to=40, width=3, textvariable=self.say_indent).pack(side="left", padx=2)
        ttk.Label(r5b, text="(Banner = persistent hint line, held until Clear; Indent nudges it right)",
                  foreground="#777").pack(side="left", padx=6)

        # Player / weapons - the menu-only verbs, via the generic gf_cmd_action channel.
        box5 = ttk.LabelFrame(body, text="Player / weapons  (host)")
        box5.pack(fill="x", padx=12, pady=6)
        r6 = ttk.Frame(box5)
        r6.pack(anchor="w", padx=10, pady=(10, 4))
        for text, act in [("Fly", "fly"), ("God mode", "godmode"), ("Third person", "thirdperson"),
                          ("Max ammo", "maxammo"), ("Drop weapon", "dropweapon"),
                          ("Unlock all", "unlockall"), ("Freeze all", "freeze")]:
            ttk.Button(r6, text=text, width=12,
                       command=lambda a=act: self._action(a)).pack(side="left", padx=3)
        r7 = ttk.Frame(box5)
        r7.pack(fill="x", padx=10, pady=4)
        ttk.Label(r7, text="Give weapon").pack(side="left")
        self.wpn_var = tk.StringVar()
        wlist = [f"{d}  [{n}]" for cat in WEAPONS.values() for d, n in cat]
        self._wpnlut = {f"{d}  [{n}]": n for cat in WEAPONS.values() for d, n in cat}
        ttk.Combobox(r7, state="readonly", values=wlist, textvariable=self.wpn_var,
                     width=38).pack(side="left", padx=6)
        ttk.Button(r7, text="Give", command=self._give_weapon).pack(side="left")
        r8 = ttk.Frame(box5)
        r8.pack(anchor="w", padx=10, pady=(4, 10))
        for label, act, hi in [("Camo id", "camo", 149), ("Operator id", "operator", 60),
                               ("Outfit id", "outfit", 60)]:
            ttk.Label(r8, text=label).pack(side="left", padx=(0, 2))
            var = tk.IntVar(value=0)
            setattr(self, f"cos_{act}", var)
            ttk.Spinbox(r8, from_=0, to=hi, textvariable=var, width=5).pack(side="left", padx=(0, 2))
            ttk.Button(r8, text="Set",
                       command=lambda a=act: self._action(a, str(getattr(self, f"cos_{a}").get()))
                       ).pack(side="left", padx=(0, 14))

        # Teleport (docs/notes/teleport.md): the menu's Teleport hub over gf_cmd_action.
        # "crosshair" = wherever the host is aiming when the command lands; "saved point" =
        # Save point (kept across rounds); "map centre" = level.mapcenter. The gun / grenade
        # buttons are toggles like Fly / God mode; "everyone" never includes bots.
        boxt = ttk.LabelFrame(body, text="Teleport  (host; everyone = every living player but you)")
        boxt.pack(fill="x", padx=12, pady=6)
        rt1 = ttk.Frame(boxt)
        rt1.pack(anchor="w", padx=10, pady=(10, 2))
        ttk.Label(rt1, text="Everyone", width=11).pack(side="left")
        for text, arg in [("to me", "me"), ("to crosshair", "aim"), ("to saved point", "saved"),
                          ("to map centre", "centre")]:
            ttk.Button(rt1, text=text, width=14,
                       command=lambda a=arg: self._action("tpall", a)).pack(side="left", padx=3)
        rt2 = ttk.Frame(boxt)
        rt2.pack(anchor="w", padx=10, pady=2)
        ttk.Label(rt2, text="My team", width=11).pack(side="left")
        for text, arg in [("to me", "me"), ("to crosshair", "aim")]:
            ttk.Button(rt2, text=text, width=14,
                       command=lambda a=arg: self._action("tpteam", a)).pack(side="left", padx=3)
        ttk.Label(rt2, text="   Other team").pack(side="left")
        for text, arg in [("to me", "me"), ("to crosshair", "aim")]:
            ttk.Button(rt2, text=text, width=14,
                       command=lambda a=arg: self._action("tpenemy", a)).pack(side="left", padx=3)
        rt3 = ttk.Frame(boxt)
        rt3.pack(anchor="w", padx=10, pady=2)
        ttk.Label(rt3, text="Me", width=11).pack(side="left")
        for text, arg in [("to crosshair", "aim"), ("to saved point", "saved"), ("to map centre", "centre")]:
            ttk.Button(rt3, text=text, width=14,
                       command=lambda a=arg: self._action("tpme", a)).pack(side="left", padx=3)
        ttk.Button(rt3, text="Save point", width=14,
                   command=lambda: self._action("tpsave")).pack(side="left", padx=3)
        rt4 = ttk.Frame(boxt)
        rt4.pack(anchor="w", padx=10, pady=(2, 10))
        ttk.Label(rt4, text="Toggle", width=11).pack(side="left")
        for text, act, arg in [("TP gun: host", "tpgun", "host"), ("TP gun: everyone", "tpgun", "all"),
                               ("TP grenade: host", "tpnade", "host"), ("TP grenade: everyone", "tpnade", "all")]:
            ttk.Button(rt4, text=text, width=20,
                       command=lambda a=act, g=arg: self._action(a, g)).pack(side="left", padx=3)

        # Vehicles (2026-09-18, klaze: "everything in the app"): the menu's Vehicles page over
        # gf_cmd_action - spawn by master INDEX ahead of the host (aircraft above his head), enter
        # the aimed vehicle, sweep the empty ones this menu spawned. docs/notes/vehicles.md.
        boxv = ttk.LabelFrame(body, text="Vehicles  (host; spawns ahead of you, aircraft above you - only what this map has resident)")
        boxv.pack(fill="x", padx=12, pady=6)
        rv1 = ttk.Frame(boxv)
        rv1.pack(anchor="w", padx=10, pady=(10, 2))
        ttk.Label(rv1, text="Drivable", width=13).pack(side="left")
        self._vehlut = {(f"{label}  [#{i}]" if kind == 0 else f"{label}  [other #{i}]"): i
                        for i, label, kind in VEHICLE_MASTER}
        drivable = [k for k, i in self._vehlut.items() if VEHICLE_MASTER[i][2] == 0]
        other = [k for k, i in self._vehlut.items() if VEHICLE_MASTER[i][2] != 0]
        self.veh_var = tk.StringVar(value=next((k for k in drivable if k.startswith("Motorcycle ")), drivable[0]))
        ttk.Combobox(rv1, state="readonly", values=drivable, textvariable=self.veh_var,
                     width=40).pack(side="left", padx=3)
        ttk.Button(rv1, text="Spawn ahead of me", width=18,
                   command=lambda: self._action("vehspawn", str(self._vehlut.get(self.veh_var.get(), 0)))
                   ).pack(side="left", padx=3)
        rv2 = ttk.Frame(boxv)
        rv2.pack(anchor="w", padx=10, pady=2)
        ttk.Label(rv2, text="Other", width=13).pack(side="left")
        self.veh_other_var = tk.StringVar(value=other[0] if other else "")
        ttk.Combobox(rv2, state="readonly", values=other, textvariable=self.veh_other_var,
                     width=40).pack(side="left", padx=3)
        ttk.Button(rv2, text="Spawn (untested)", width=18,
                   command=lambda: self._action("vehspawn", str(self._vehlut.get(self.veh_other_var.get(), 0)))
                   ).pack(side="left", padx=3)
        rv3 = ttk.Frame(boxv)
        rv3.pack(anchor="w", padx=10, pady=(2, 10))
        ttk.Label(rv3, text="", width=13).pack(side="left")
        ttk.Button(rv3, text="Enter the vehicle I aim at", width=24,
                   command=lambda: self._action("vehenter")).pack(side="left", padx=3)
        ttk.Button(rv3, text="Remove empty spawned vehicles", width=28,
                   command=lambda: self._action("vehclear")).pack(side="left", padx=3)
        ttk.Label(rv3, text="  spawn-riding modes: Config → Vehicle mode", foreground="#777").pack(side="left")

        # Map toys (2026-09-17, none run in-game yet): the menu's Destructibles + exploders /
        # Projectiles / Props pages over gf_cmd_action. docs/notes/destructibles.md,
        # projectiles.md, static-props.md. Every one is a WRITE that changes the match.
        boxm = ttk.LabelFrame(body, text="Map toys  (destructibles, radiant exploders, projectiles, props - untested)")
        boxm.pack(fill="x", padx=12, pady=6)
        rm1 = ttk.Frame(boxm)
        rm1.pack(anchor="w", padx=10, pady=(10, 2))
        ttk.Label(rm1, text="Destructibles", width=13).pack(side="left")
        for text, arg in [("break aimed", "aim"), ("break near me", "near"), ("break ALL", "all")]:
            ttk.Button(rm1, text=text, width=14,
                       command=lambda a=arg: self._action("destruct", a)).pack(side="left", padx=3)
        rm2 = ttk.Frame(boxm)
        rm2.pack(anchor="w", padx=10, pady=2)
        ttk.Label(rm2, text="Exploders", width=13).pack(side="left")
        for text, arg in [("fire next", "next"), ("fire previous", "prev"), ("again", "again"),
                          ("stop current", "stop"), ("fire all", "all"), ("stop walk", "stopall")]:
            ttk.Button(rm2, text=text, width=12,
                       command=lambda a=arg: self._action("exploder", a)).pack(side="left", padx=3)
        rm3 = ttk.Frame(boxm)
        rm3.pack(anchor="w", padx=10, pady=2)
        ttk.Label(rm3, text="Projectiles", width=13).pack(side="left")
        for text, arg in [("host", "host"), ("everyone", "all"), ("OFF", "off")]:
            ttk.Button(rm3, text=text, width=9,
                       command=lambda a=arg: self._action("proj", a)).pack(side="left", padx=3)
        ttk.Button(rm3, text="homing", width=9, command=lambda: self._action("projhoming")).pack(side="left", padx=3)
        ttk.Button(rm3, text="trail FX", width=9, command=lambda: self._action("projtrail")).pack(side="left", padx=3)
        rm4 = ttk.Frame(boxm)
        rm4.pack(anchor="w", padx=10, pady=2)
        ttk.Label(rm4, text="", width=13).pack(side="left")
        self.proj_var = tk.StringVar(value="RPG rocket  [launcher_freefire_t9]")
        self._projlut = {f"{d}  [{n}]": n for d, n in PROJ_WEAPONS}
        ttk.Combobox(rm4, state="readonly", values=list(self._projlut), textvariable=self.proj_var,
                     width=40).pack(side="left", padx=3)
        ttk.Button(rm4, text="Set projectile", width=14,
                   command=lambda: self._action("projweapon", self._projlut.get(self.proj_var.get(), ""))
                   ).pack(side="left", padx=3)
        ttk.Label(rm4, text="  rate ms").pack(side="left")
        self.proj_rate = tk.StringVar(value="300")
        ttk.Combobox(rm4, state="readonly", width=5, textvariable=self.proj_rate,
                     values=["0", "150", "300", "600", "1000"]).pack(side="left", padx=2)
        ttk.Button(rm4, text="Set",
                   command=lambda: self._action("projrate", self.proj_rate.get())).pack(side="left", padx=3)
        rm5 = ttk.Frame(boxm)
        rm5.pack(anchor="w", padx=10, pady=(2, 10))
        ttk.Label(rm5, text="Props", width=13).pack(side="left")
        self.prop_var = tk.StringVar(value=PROP_UNIVERSAL[0][0])
        self._proplut = {d: n for d, n in PROP_UNIVERSAL}
        ttk.Combobox(rm5, state="readonly", values=[d for d, _ in PROP_UNIVERSAL], textvariable=self.prop_var,
                     width=28).pack(side="left", padx=3)
        ttk.Button(rm5, text="Place where I look", width=18,
                   command=lambda: self._action("prop", f'"{self.prop_var.get()}"')
                   ).pack(side="left", padx=3)
        ttk.Button(rm5, text="Remove last", width=12, command=lambda: self._action("propundo")).pack(side="left", padx=3)
        ttk.Button(rm5, text="Remove all", width=12, command=lambda: self._action("propclear")).pack(side="left", padx=3)

        # Per-player verbs (the menu's Players page): gf_cmd_target names the player as shown
        # in game - exact name or a case-insensitive prefix; the GSC resolves it.
        box6 = ttk.LabelFrame(body, text="Player by name  (as shown in game; a prefix is enough)")
        box6.pack(fill="x", padx=12, pady=6)
        # Connected players, read OUT of the game (roster_scan.py: a read-only memory sweep for
        # the roster line gunfight_menu keeps alive - the only game->app channel there is).
        # Pick one to fill the Player box with the exact name. Refresh is a ~1 s read once the
        # line has been found; the first find after a game launch can take a minute.
        r8b = ttk.Frame(box6)
        r8b.pack(fill="x", padx=10, pady=(10, 4))
        ttk.Label(r8b, text="Connected").pack(side="left")
        self.roster_var = tk.StringVar()
        self._roster_lut = {}
        self.roster_box = ttk.Combobox(r8b, state="readonly", width=36, textvariable=self.roster_var, values=[])
        self.roster_box.pack(side="left", padx=6)
        self.roster_box.bind("<<ComboboxSelected>>", self._roster_pick)
        ttk.Button(r8b, text="Refresh", command=self._roster_refresh).pack(side="left", padx=3)
        self.roster_auto = tk.BooleanVar(value=False)
        ttk.Checkbutton(r8b, text="auto 5 s", variable=self.roster_auto,
                        command=self._roster_auto_tick).pack(side="left", padx=6)
        self.roster_status = ttk.Label(r8b, text="", foreground="#777")
        self.roster_status.pack(side="left", padx=6)
        r9 = ttk.Frame(box6)
        r9.pack(fill="x", padx=10, pady=(0, 10))
        ttk.Label(r9, text="Player").pack(side="left")
        self.target_var = tk.StringVar()
        ttk.Entry(r9, textvariable=self.target_var, width=22).pack(side="left", padx=6)
        for text, act, arg in [("Move to allies", "move", "allies"), ("Move to axis", "move", "axis"),
                               ("Spectator", "spectate", ""), ("Freeze / unfreeze", "freezeone", "")]:
            ttk.Button(r9, text=text, width=16,
                       command=lambda a=act, g=arg: self._target_action(a, g)).pack(side="left", padx=3)
        # Per-client control (the Players page's per-player rows, 2026-09-15): same target
        # rule, one verb per button; Give / Camo / Operator / Outfit reuse the pickers in
        # the host box above. Kick is refused for the host by the GSC.
        r10 = ttk.Frame(box6)
        r10.pack(anchor="w", padx=10, pady=(0, 4))
        for text, act in [("God mode", "godone"), ("Max ammo", "ammoone"), ("Third person", "thirdone"),
                          ("Fly", "flyone"), ("Kill", "killone"), ("Take weapon", "takeone"),
                          ("Strip weapons", "stripone"), ("Kick", "kickone")]:
            ttk.Button(r10, text=text, width=12,
                       command=lambda a=act: self._target_action(a)).pack(side="left", padx=3)
        r11 = ttk.Frame(box6)
        r11.pack(anchor="w", padx=10, pady=(0, 10))
        ttk.Button(r11, text="Give picked weapon", width=18,
                   command=self._give_weapon_to).pack(side="left", padx=3)
        for text, act, var in [("Camo id", "camoone", "cos_camo"), ("Operator id", "operatorone", "cos_operator"),
                               ("Outfit id", "outfitone", "cos_outfit")]:
            ttk.Button(r11, text=text, width=11,
                       command=lambda a=act, v=var: self._target_action(a, str(getattr(self, v).get()))
                       ).pack(side="left", padx=3)
        ttk.Label(r11, text="  Speed %").pack(side="left")
        self.target_speed = tk.StringVar(value="150")
        ttk.Combobox(r11, state="readonly", width=5, textvariable=self.target_speed,
                     values=["0", "50", "100", "150", "200", "300"]).pack(side="left", padx=2)
        ttk.Button(r11, text="Set",
                   command=lambda: self._target_action("speedone", self.target_speed.get())).pack(side="left", padx=3)
        ttk.Label(r11, text="(0 = back to the global speed)", foreground="#777").pack(side="left", padx=6)
        # Teleport verbs for the named player (docs/notes/teleport.md): to me = in front of
        # you facing you; me to them = in front of them; swap = exchange positions and views.
        r12 = ttk.Frame(box6)
        r12.pack(anchor="w", padx=10, pady=(0, 10))
        ttk.Label(r12, text="Teleport").pack(side="left")
        for text, arg in [("them to me", "tome"), ("me to them", "metothem"), ("swap places", "swap")]:
            ttk.Button(r12, text=text, width=14,
                       command=lambda g=arg: self._target_action("tpplayer", g)).pack(side="left", padx=3)
        return tab

    # ---- Connected players (roster_scan: read-only sweep of the game's memory) ----------
    def _roster_refresh(self, force_full: bool = False):
        if roster_scan is None or gf_native is None:
            self._say("roster: roster_scan / gf_native not importable")
            return
        if getattr(self, "_roster_busy", False):
            return
        self._roster_busy = True
        self.roster_status.config(text="scanning...")

        def worker():
            try:
                pid = gf_native.find_game_pid()
                if not pid:
                    raise roster_scan.RosterError("game not running")
                sc = getattr(self, "_roster_scanner", None)
                if sc is None or sc.pid != pid:
                    if sc is not None:
                        sc.close()
                    sc = roster_scan.Scanner(pid)
                    self._roster_scanner = sc
                r = sc.read(force_full)
                self.root.after(0, lambda: self._roster_done(r, None))
            except Exception as e:                      # noqa: BLE001 - shown in the status label
                self.root.after(0, lambda: self._roster_done(None, str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def _roster_done(self, r, err):
        self._roster_busy = False
        if err:
            self.roster_status.config(text=err)
            return
        if r is None:
            self.roster_status.config(text="no roster in memory (menu injected? match running?)")
            return
        self._roster_lut = {p.label(): p for p in r.players}
        self.roster_box["values"] = list(self._roster_lut)
        how = f"swept {r.scanned_s:.1f}s" if r.full_scan else "cached"
        self.roster_status.config(text=f"{len(r.players)} in the match ({how})")

    def _roster_pick(self, _event=None):
        p = self._roster_lut.get(self.roster_var.get())
        if p is not None:
            self.target_var.set(p.name)

    def _roster_auto_tick(self):
        if not self.roster_auto.get():
            return
        self._roster_refresh()
        self.root.after(5000, self._roster_auto_tick)

    def _target_action(self, name, arg=""):
        target = self.target_var.get().strip()
        if not target:
            self._say("name a player first")
            return
        # quoted like the broadcast text: names carry spaces ("C. Smartt"); the per-command
        # cap is ~48 bytes, so keep the name short - a prefix resolves in the GSC.
        s = {"gf_cmd_target": f'"{target[:24]}"', "gf_cmd_action": name}
        if arg != "":
            s["gf_cmd_arg"] = arg
        s["gf_cmd_go"] = 1
        self._write(s)

    # ---- Inject / Status tab -----------------------------------------------
    def _inject_tab(self, nb) -> ttk.Frame:
        tab = ttk.Frame(nb)
        note = ("One-stop launch: confirm the game is up with cwpatch, inject the mod menu, and\n"
                "build + load the bridge DLL - then Config / Actions drive the match.")
        tk.Label(tab, text=note, fg="#8a5a00", justify="left").pack(anchor="w", padx=12, pady=(12, 8))

        box = ttk.LabelFrame(tab, text="Status")
        box.pack(fill="x", padx=12, pady=6)
        grid = ttk.Frame(box)
        grid.pack(anchor="w", padx=12, pady=8)
        self.st_game = ttk.Label(grid, text="Game: checking...")
        self.st_game.grid(row=0, column=0, sticky="w", pady=2)
        self.st_cwpatch = ttk.Label(grid, text="cwpatch: checking...")
        self.st_cwpatch.grid(row=1, column=0, sticky="w", pady=2)
        self.st_bridge = ttk.Label(grid, text="Bridge DLL: checking...")
        self.st_bridge.grid(row=2, column=0, sticky="w", pady=2)
        sr = ttk.Frame(box)
        sr.pack(anchor="w", padx=12, pady=(0, 8))
        ttk.Button(sr, text="Refresh", command=self._refresh_status).pack(side="left")
        # Battle.net writes the stock SDK back over cwpatch on updates/repairs - re-install it.
        ttk.Button(sr, text="Install / reinstall cwpatch",
                   command=self._install_cwpatch).pack(side="left", padx=6)

        box2 = ttk.LabelFrame(tab, text="Inject  (one payload per game launch)")
        box2.pack(fill="x", padx=12, pady=6)
        r0 = ttk.Frame(box2)
        r0.pack(anchor="w", padx=12, pady=(10, 2))
        ttk.Button(r0, text="Set up all  (bridge + menu)", width=26, style="Accent.TButton",
                   command=self._setup_all).pack(side="left", padx=4)
        ttk.Label(r0, text="one click - then restart the match to link the menu",
                  foreground="#777").pack(side="left", padx=8)
        r = ttk.Frame(box2)
        r.pack(anchor="w", padx=12, pady=(2, 8))
        ttk.Label(r, text="or separately:").pack(side="left", padx=(0, 6))
        ttk.Button(r, text="Inject mod menu", width=16,
                   command=self._inject_menu).pack(side="left", padx=4)
        ttk.Button(r, text="Inject bridge", width=14,
                   command=self._inject_bridge).pack(side="left", padx=4)
        if not FROZEN:                       # dev-only: recompile the bridge with zig
            ttk.Button(r, text="Build bridge (dev)", width=16,
                       command=self._build_bridge_dev).pack(side="left", padx=4)
        ttk.Label(box2, foreground="#777", justify="left",
                  text=("cwpatch installs on first Set up all (loads at the next game launch).\n"
                        "Load a private MATCH once before injecting the menu (puts bb.gsc in the pool).\n"
                        "Menu = GSC payload (restart to link); bridge = prebuilt native DLL (immediate).")
                  ).pack(anchor="w", padx=12, pady=(0, 8))
        return tab

    def _logbox(self):
        frame = ttk.LabelFrame(self.root, text="Log")
        frame.pack(fill="both", expand=False, padx=8, pady=(0, 8))
        self.logw = tk.Text(frame, height=7, bg="#101418", fg="#c8d0d8",
                            font=("Consolas", 9), wrap="none", borderwidth=0)
        sb = ttk.Scrollbar(frame, orient="vertical", command=self.logw.yview)
        self.logw.configure(yscrollcommand=sb.set)
        sb.pack(side="right", fill="y")
        self.logw.pack(side="left", fill="both", expand=True)

    # ---- behaviour -----------------------------------------------------------
    def _connect(self):
        if not self.backend:
            self._say("backend module unavailable - GUI is display-only.")
            return
        try:
            self.backend.connect()
        except BackendError as e:
            self._say(f"connect: {e}")
        self._drain()

    # Structural settings the engine can only apply by RELOADING the match: changing a round
    # limit the match has already passed ends it, and a team-size/maxplayers change resets it.
    # "Next round" refuses to defer these (it would look like a surprise restart, klaze
    # 2026-09-15) - it routes them to a restart choice instead. Adjust as we learn which of
    # these actually defer cleanly on the current build.
    RESTART_REQUIRED = {"gf_roundwinlimit", "gf_roundlimit", "gf_team_size", "gf_spec_slots"}

    def _is_changed(self, dvar, val):
        return (val != self._defaults.get(dvar) or dvar in self._sent or dvar in self._touched)

    def _apply_config(self, trailer=None, force=False, exclude=None):
        # trailer (optional) rides in the SAME message so the config lands before the command
        # fires: {"gf_cmd_apply":1,"gf_cmd_go":1} (live) or {"gf_cmd_restart":1,"gf_cmd_go":1}.
        # Send CHANGED settings, ones sent before, and ones the user touched (even back to the
        # default) - not the whole set every time, to avoid registering ~50 dvars per apply.
        # force=True would send every field - never wire it to a button: it crashed the game
        # (dvar store overflow) on 2026-09-15. Kept only for a deliberate, small CONFIG.
        settings = {}
        for dvar, v in self.vars.items():
            if exclude and dvar in exclude:
                continue
            val = v.get()
            if force or self._is_changed(dvar, val):
                settings[dvar] = val
                self._sent.add(dvar)
        # Pack the 15 numeric bot knobs into ONE gf_bot dvar (the mod reads gf_bot, not the
        # individual gf_bot_* - dvar-pool budget). Send it whenever any of them is in play.
        BOT_PACK = ["gf_bot_hit", "gf_bot_head", "gf_bot_react", "gf_bot_fire", "gf_bot_hip",
                    "gf_bot_far", "gf_bot_semi", "gf_bot_burst", "gf_bot_moveshoot",
                    "gf_bot_fastaim", "gf_bot_sprint", "gf_bot_melee", "gf_bot_prone",
                    "gf_bot_slide", "gf_bot_crouch"]
        if any(k in settings for k in BOT_PACK):
            for k in BOT_PACK:
                settings.pop(k, None)
            # TWO dvars, not one: a single `set gf_bot <15 fields>` is ~54 bytes and the bridge
            # command slot only restores 48 - a longer `set` corrupts game memory and hard-crashes
            # (klaze 2026-09-15). Fields 0-7 in gf_bot, 8-14 in gf_bot2; each `set` is <40 bytes.
            settings["gf_bot"] = ",".join(str(self.vars[k].get()) for k in BOT_PACK[:8])
            settings["gf_bot2"] = ",".join(str(self.vars[k].get()) for k in BOT_PACK[8:])
        # Pack the 57 int config settings into chunk dvars gf_c0..gf_c9 (6 per chunk, SORTED
        # key order) instead of 57 individual  - the game's dvar pool is only 4096
        # and heavy maps nearly fill it (dvar-pool-crash). The GSC sorts the SAME 57 keys the
        # SAME way and reads the SAME chunks (gunfight_menu.gsc cfg_spec/cfg_load). If ANY
        # packed field changed, rebuild + send all 10 chunks from the current field values.
        PACKED = ['gf_autoswitch', 'gf_bot_diff_allies', 'gf_bot_diff_axis', 'gf_bot_passive', 'gf_camo', 'gf_camo_pool', 'gf_camo_split', 'gf_caster_probe', 'gf_census', 'gf_customcac', 'gf_dbg_assets', 'gf_dbg_families', 'gf_dbg_flags', 'gf_dbg_match', 'gf_dbg_spawn', 'gf_dbg_structs', 'gf_falldamage', 'gf_feed_lines', 'gf_fly_fast', 'gf_fly_speed', 'gf_gravity', 'gf_jump', 'gf_jump_boost', 'gf_loadout', 'gf_map_method', 'gf_menu_hspan', 'gf_menu_lines', 'gf_menu_region', 'gf_prematch', 'gf_preround', 'gf_profile', 'gf_roundlimit', 'gf_rounds_loadout', 'gf_roundwinlimit', 'gf_spawn_autospread', 'gf_spawn_diag', 'gf_spawn_family', 'gf_spawn_gap', 'gf_spawn_guard', 'gf_spawn_pick', 'gf_spec_slots', 'gf_speed', 'gf_spyplane', 'gf_strike', 'gf_switch_sides', 'gf_switch_wait', 'gf_team_size', 'gf_timer_seconds', 'gf_zone', 'gf_zone_capture', 'gf_zone_overtime', 'gf_zone_radius']
        packed_changed = [k for k in PACKED if k in settings]
        if packed_changed:
            # Send only the CHUNKS that contain a changed field, so an app apply does not
            # clobber in-game menu changes to fields in other chunks. (Within a changed chunk,
            # its other 5 fields carry the app's values - same as the old per-field behaviour
            # for anything the app has ever shown.)
            changed_chunks = set()
            for k in packed_changed:
                changed_chunks.add(PACKED.index(k) // 6)
            for k in PACKED:
                if PACKED.index(k) // 6 in changed_chunks:
                    self._applied[k] = self.vars[k].get()   # sent inside its chunk
                settings.pop(k, None)
            vals = [str(self.vars[k].get()) for k in PACKED]
            for ci in sorted(changed_chunks):
                settings["gf_c" + str(ci)] = ",".join(vals[ci * 6: ci * 6 + 6])
        # (Oversized-command safety lives in BridgeBackend.apply now - the single choke point
        # for every send path, not just this one. See dvar_backend.py.)
        for k, val in settings.items():
            self._applied[k] = val
        changed = len(settings)
        if trailer:
            settings.update(trailer)
        tail = ("  + " + " ".join(k for k in trailer if k != "gf_cmd_go")) if trailer else ""
        self._say(f"apply {changed} changed config dvars{tail}:")
        if self.backend:
            self.backend.apply(settings)
        else:
            for k, val in settings.items():
                self._say(f"  [no backend] set {k} {val}")
        self._drain()

    def _apply_next_round(self):
        self._sync_untouched(self._apply_next_round_body)

    def _apply_next_round_body(self):
        # "Next round" = defer changed settings to the next round. Structural settings cannot
        # defer (they reload the match), so pull those out and let the user decide: restart now
        # to apply everything, or keep them pending and apply only the round-safe settings.
        # Pending = changed since last applied (NOT the sticky _sent/_touched sets, which made
        # a once-touched field prompt on every Next round - klaze 2026-09-15).
        pending = [d for d in self.RESTART_REQUIRED
                   if d in self.vars and self.vars[d].get() != self._applied.get(d)]
        if pending:
            from tkinter import messagebox
            names = ", ".join(self._labels.get(d, d) for d in pending)
            msg = ("These can't take effect next round - the match must reload:\n\n  "
                   + names
                   + "\n\nRestart the match now to apply everything?\n\n"
                   + "No = apply only the round-safe settings now and keep these pending "
                   + "(they apply on your next + Restart).")
            if messagebox.askyesno("Restart needed for some settings", msg):
                self._apply_restart_body()      # wrapper already synced - do not re-sync
                return
            # No: clear each pending field back to its applied value so it stops prompting and
            # the user can keep applying other things next round (klaze 2026-09-15).
            for d in pending:
                self.vars[d].set(self._applied.get(d))
                self._touched.discard(d)
            self._say("next round: reverted " + names + " (use + Restart to change them)")
        self._apply_config(exclude=self.RESTART_REQUIRED)

    # The live subsystems cmd_apply_live() can re-assert mid-match, and which config fields feed
    # each. "Apply now" tells the GSC which of these actually changed, so it re-applies ONLY that
    # subsystem - exactly what an in-game menu pick does. Re-running an untouched subsystem (esp.
    # periods, whose setgametypesetting reloads the match) is what made an app apply restart when
    # the same change from the menu did not. Fields NOT here (team size, camo, spawn, limits, ...)
    # are structural / next-round - cmd_apply_live never applies them, so they need no scope.
    LIVE_SCOPE = {
        "move": {"gf_gravity", "gf_jump", "gf_jump_boost", "gf_speed", "gf_falldamage",
                 "gf_oob", "gf_fly_speed", "gf_fly_fast"},
        "bots": {"gf_bot_diff_allies", "gf_bot_diff_axis", "gf_bot_passive",
                 "gf_bot_hit", "gf_bot_head", "gf_bot_react", "gf_bot_fire", "gf_bot_hip",
                 "gf_bot_far", "gf_bot_semi", "gf_bot_burst", "gf_bot_moveshoot", "gf_bot_fastaim",
                 "gf_bot_sprint", "gf_bot_melee", "gf_bot_prone", "gf_bot_slide", "gf_bot_crouch"},
        "periods": {"gf_prematch", "gf_preround"},
        "timer": {"gf_timer_seconds"},
        # Vehicle mode: everyone alive dismounts + remounts the (re-resolved) ride now.
        "veh": {"gf_vehmode", "gf_veh_lock", "gf_veh_hp"},
    }

    def _apply_live(self):
        self._sync_untouched(self._apply_live_body)

    def _apply_live_body(self):
        # Scope = the live subsystems whose fields changed since the last apply. Empty when only
        # structural / next-round fields changed (or nothing) - the GSC then re-applies nothing
        # instead of the whole blob. Computed BEFORE _apply_config updates _applied.
        scope = sorted(s for s, keys in self.LIVE_SCOPE.items()
                       if any(k in self.vars and self.vars[k].get() != self._applied.get(k)
                              for k in keys))
        arg = ",".join(scope) if scope else "none"
        self._apply_config(trailer={"gf_cmd_action": "apply", "gf_cmd_arg": arg, "gf_cmd_go": 1})

    def _apply_restart(self):
        self._sync_untouched(self._apply_restart_body)

    def _apply_restart_body(self):
        self._apply_config(trailer={"gf_cmd_action": "restart", "gf_cmd_go": 1})

    def _sync_untouched(self, then):
        # Before ANY apply: pull the game's LIVE values into every field the user has NOT
        # explicitly touched, so a resent packed chunk carries the game's real neighbours instead
        # of app defaults. Without this, the chunk that holds e.g. gravity (gf_c3) also carries
        # gf_loadout at the app default, and next-round mod_apply re-asserts that stale neighbour
        # -> setgametypesetting -> match RELOAD. bocw-85's chunk map: 7 of 9 packed chunks drag a
        # reload-triggering field (loadout / customcac / prematch / preround / profile / round
        # limits / spec_slots / spyplane / team_size), which is why almost every app apply
        # restarted while the same change from the in-game menu did not. config_scan is the read
        # path (app<-game); if it is unavailable we apply UNSYNCED (old behaviour, no worse).
        if config_scan is None or gf_native is None:
            then()
            return
        if getattr(self, "_sync_busy", False):
            return                              # a sync is already in flight; drop this click
        self._sync_busy = True

        def worker():
            try:
                pid = gf_native.find_game_pid()
                live = config_scan.read_config(pid, self._defaults) if pid else None
            except Exception:                   # noqa: BLE001 - reported below, then apply unsynced
                live = None
            self.root.after(0, lambda: self._sync_untouched_done(live, then))

        threading.Thread(target=worker, daemon=True).start()

    def _sync_untouched_done(self, live, then):
        self._sync_busy = False
        if live:
            _tick, cfg = live
            n = 0
            for dvar, val in cfg.items():
                if dvar not in self.vars or dvar in self._touched:
                    continue                    # keep the user's explicit picks untouched
                try:
                    if self.vars[dvar].get() != val:
                        self.vars[dvar].set(val)   # the write-trace re-adds it to _touched
                        n += 1
                    self._applied[dvar] = val
                    self._touched.discard(dvar)    # a sync is not a user change
                except Exception:               # noqa: BLE001 - one bad field must not block apply
                    pass
            if n:
                self._say(f"apply: synced {n} untouched field(s) to the live game first")
        else:
            self._say("apply: could not read live config - applying UNSYNCED (a stale neighbour may reload)")
        then()

    def _action(self, name, arg=""):
        s = {"gf_cmd_action": name}
        if arg != "":
            s["gf_cmd_arg"] = arg
        s["gf_cmd_go"] = 1
        self._write(s)

    def _give_weapon(self):
        n = self._wpnlut.get(self.wpn_var.get())
        if not n:
            self._say("pick a weapon first")
            return
        self._action("giveweapon", n)

    def _give_weapon_to(self):
        n = self._wpnlut.get(self.wpn_var.get())
        if not n:
            self._say("pick a weapon first")
            return
        self._target_action("giveone", n)

    def _switch(self, stage: bool = False):
        # Empty map = keep the current map (GSC falls back to sv_mapname), so you can switch
        # the gametype alone - e.g. to gunfight - without choosing a map. "" clears any stale value.
        m = self._maplut.get(self.map_var.get())
        gt = self._map_gt.get(self.map_var.get(), self.gt_var.get())
        self._write({"gf_cmd_map": m if m else '""',
                     "gf_cmd_gametype": gt,
                     "gf_cmd_stage": int(stage), "gf_cmd_go": 1})

    def _cmd(self, name):
        # Folded into the generic action channel (dvar-pool budget): one gf_cmd_action string
        # instead of a dedicated gf_cmd_<name> dvar per command.
        self._write({"gf_cmd_action": name, "gf_cmd_go": 1})

    def _pause(self, val):
        # folded into the action channel: 1 = pause, else resume.
        self._write({"gf_cmd_action": "pause" if val == 1 else "resume", "gf_cmd_go": 1})

    def _broadcast(self):
        # Cap to ~28 chars: the bridge writes each command over cwpatch's 48-byte command blob.
        msg = self.say_var.get().strip().replace('"', "'")[:28]
        if not msg:
            self._say("type a message to broadcast first")
            return
        try:
            indent = max(0, min(40, int(self.say_indent.get() or 0)))
        except ValueError:
            indent = 0
        # loc/dur/indent first, quoted msg (spaces survive `set`), go last - one bridge message.
        self._write({"gf_cmd_say_loc": self.say_loc.get(),
                     "gf_cmd_say_dur": self._DUR.get(self.say_dur.get(), 0),
                     "gf_say_hint_indent": indent,
                     "gf_cmd_say": f'"{msg}"', "gf_cmd_go": 1})
        self.say_var.set("")

    def _broadcast_clear(self):
        self._write({"gf_cmd_action": "sayclear", "gf_cmd_go": 1})

    def _show_codes(self):
        win = tk.Toplevel(self.root)
        win.title("Cold War text codes")
        win.configure(bg="#101418")
        try:
            win.iconphoto(True, self._icon)
        except Exception:
            pass
        tk.Label(win, text="Colour codes - type them into the broadcast message",
                 bg="#101418", fg="#c8d0d8", font=("Segoe UI", 10, "bold")
                 ).pack(anchor="w", padx=14, pady=(12, 6))
        for code, name, color in self.CODES:
            row = tk.Frame(win, bg="#101418")
            row.pack(fill="x", padx=14, pady=1)
            tk.Label(row, text=code, bg="#101418", fg="#8a8f94",
                     font=("Consolas", 12), width=3, anchor="w").pack(side="left")
            tk.Label(row, text=name, bg="#101418", fg="#8a8f94",
                     font=("Consolas", 9), width=13, anchor="w").pack(side="left")
            tk.Label(row, text="  The quick brown fox 1234  ", bg="#40454b", fg=color,
                     font=("Consolas", 12)).pack(side="left")
        tk.Label(win, justify="left", bg="#101418", fg="#8a8f94", font=("Segoe UI", 8),
                 text=("A ^code colours the rest of the line until the next code; ^7 resets to white.\n"
                       "Example:   ^1Red ^2green ^3yellow\n"
                       "Server text has no bold / size / font control, and glyphs are unreliable.\n"
                       "Messages are capped at ~28 characters (bridge command-blob limit).")
                 ).pack(anchor="w", padx=14, pady=(10, 12))

    # ---- Inject / Status ---------------------------------------------------
    def _tick_status(self):
        self._refresh_status()
        self.root.after(5000, self._tick_status)      # light poll; probes are read-only

    def _refresh_status(self):
        # Bridge = shared-memory probe; game + cwpatch = native ctypes (no subprocess, so no
        # console flash and it works in the standalone build).
        if bridge_channel is not None:
            try:
                listening, seq, _ = bridge_channel.probe()
                self.st_bridge.config(
                    text="Bridge DLL: " + (f"listening (seq={seq})" if listening else "NOT loaded"),
                    foreground="#1a7f1a" if listening else "#a11")
            except Exception as e:
                self.st_bridge.config(text=f"Bridge DLL: {e}", foreground="#a11")
        if gf_native is None:
            return
        pid = gf_native.find_game_pid()
        self.st_game.config(text="Game: " + (f"running (pid {pid})" if pid else "not running"),
                            foreground="#1a7f1a" if pid else "#a11")
        gd = gf_native.find_game_dir(pid or None)
        slot = os.path.join(gd, "discord_game_sdk.dll") if gd else None
        try:
            size = os.path.getsize(slot) if slot and os.path.exists(slot) else 0
        except OSError:
            size = 0
        if size == gf_native.CWPATCH_SIZE:
            self.st_cwpatch.config(text="cwpatch: installed" + (" + loaded" if pid else " (loads next launch)"),
                                   foreground="#1a7f1a")
        elif not gd:
            self.st_cwpatch.config(text="cwpatch: game folder not found", foreground="#777")
        elif size:
            self.st_cwpatch.config(text="cwpatch: NOT installed - Set up all installs it",
                                   foreground="#a11")
        else:
            self.st_cwpatch.config(text="cwpatch: slot missing", foreground="#a11")

    def _install_cwpatch(self):
        # Put the bundled cwpatch back in the game's discord_game_sdk.dll slot. Use it on first
        # setup AND whenever Battle.net has reverted it to the stock SDK (status shows NOT installed).
        if gf_native is None:
            self._say("native helpers unavailable"); return
        if not os.path.exists(CWPATCH_SRC):
            self._say("cwpatch source missing: " + CWPATCH_SRC); return
        pid = gf_native.find_game_pid()
        gd = gf_native.find_game_dir(pid or None)
        if not gd:
            self._say("game folder not found - can't install cwpatch"); return
        msg = gf_native.install_cwpatch(CWPATCH_SRC, gd, game_running=bool(pid))
        self._say("cwpatch: " + msg)
        if pid and "already" not in msg:
            self._say("  -> close the game, click again, then relaunch (cwpatch loads at start)")
        elif "installed" in msg:
            self._say("  -> relaunch the game so cwpatch loads")
        self._refresh_status()

    def _bridge_loaded(self) -> bool:
        # A listening bridge == the DLL is loaded in the game == gf_bridge.dll is file-locked
        # (can't be rebuilt) and re-injecting would double-load it.
        if bridge_channel is None:
            return False
        try:
            listening, _, _ = bridge_channel.probe()
            return listening
        except Exception:
            return False

    def _shell_async(self, args, label, cwd=None, then=None):
        """Run an injection/build command off the UI thread, tail its output to the Log.
        Guard: these run the repo's own scripts; the human clicks the button."""
        self._say(f"$ {label}...")
        def worker():
            try:
                p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=200,
                                   **_no_window())
                out = ((p.stdout or "") + (p.stderr or "")).rstrip()
                ok = (p.returncode == 0)
            except FileNotFoundError as e:
                out, ok = f"cannot run {args[0]!r}: {e} (on PATH?)", False
            except Exception as e:
                out, ok = f"error: {e}", False
            self.root.after(0, lambda: self._shell_done(out, ok, then))
        threading.Thread(target=worker, daemon=True).start()

    def _shell_done(self, out, ok, then):
        for line in out.splitlines()[-14:]:
            self._say("  " + line)
        low = out.lower()
        failed_menu = "find target script" in low   # acts: bb.gsc not in the pool yet
        if failed_menu:
            self._say("  -> load a private MATCH once first (puts bb.gsc in the pool), then inject.")
        if not ok and ("permission denied" in low or "failed to write output" in low):
            self._say("  -> gf_bridge.dll is locked because it's loaded in the game.")
            self._say("     Relaunch the game (unloads it), then Set up all.")
        self._refresh_status()
        if then and ok and not failed_menu:      # don't chain past a failed step
            then()

    def _setup_all(self):
        if not messagebox.askokcancel(
                "Set up all",
                "Install cwpatch (if needed), load the bridge, and inject the mod menu.\n\n"
                "cwpatch is read at game start, so the first time you'll relaunch once.\n"
                "After the menu injects, restart the match to link it."):
            return
        if gf_native is None:
            self._say("native helpers unavailable - can't set up"); return
        pid = gf_native.find_game_pid()
        gd = gf_native.find_game_dir(pid or None)

        # 1. cwpatch must be in the slot BEFORE the game starts (it is loaded at launch).
        if not os.path.exists(CWPATCH_SRC):
            self._say("cwpatch source missing: " + CWPATCH_SRC)
            self._say("  provide it (repo: vendor-backup\\ ; standalone: bundled), then Set up all")
            return
        if gd and gf_native.sha256(os.path.join(gd, "discord_game_sdk.dll")) != gf_native.CWPATCH_SHA256:
            self._say("cwpatch: " + gf_native.install_cwpatch(CWPATCH_SRC, gd, game_running=bool(pid)))
            self._say("  -> " + ("close the game, relaunch it, then Set up all again"
                                 if pid else "now LAUNCH the game, then Set up all again"))
            self._refresh_status(); return

        # cwpatch is in the slot from here; the injections need the game running.
        if not pid:
            self._say("cwpatch is in place - LAUNCH the game, then Set up all")
            self._refresh_status(); return

        # 2. bridge - inject the PREBUILT gf_bridge.dll natively (no zig at runtime).
        if self._bridge_loaded():
            self._say("bridge already loaded - keeping it")
        elif os.path.exists(BRIDGE_DLL):
            self._say(gf_native.inject_dll(pid, BRIDGE_DLL))
        else:
            self._say("gf_bridge.dll not found: " + BRIDGE_DLL)
            if not FROZEN:
                self._say("  dev: 'Build bridge (dev)' first, then Set up all")

        # 3. menu - acts injectcw of the prebuilt payload.
        self._menu_inject_async(
            then=lambda: self._say("set up complete - restart the match to link the menu"))
        self._refresh_status()

    def _menu_inject_async(self, then=None):
        self._shell_async([ACTS, "injectcw", MENU_PAYLOAD, MENU_HOOK, MENU_REPLACE],
                          "inject mod menu", cwd=os.path.dirname(ACTS), then=then)

    def _inject_menu(self):
        if not messagebox.askokcancel(
                "Inject mod menu",
                "Inject the gunfight_menu payload into the running game?\n\n"
                "One payload per game launch. Restart the match afterwards to link it."):
            return
        self._menu_inject_async()

    def _inject_bridge(self):
        if gf_native is None:
            self._say("native helpers unavailable"); return
        pid = gf_native.find_game_pid()
        if not pid:
            messagebox.showinfo("Inject bridge", "Launch the game first."); return
        if self._bridge_loaded():
            messagebox.showinfo(
                "Bridge already loaded",
                "A bridge DLL is already loaded in the running game (re-injecting would double-load "
                "it). To load a different build, relaunch the game first, then Set up all.")
            return
        if not os.path.exists(BRIDGE_DLL):
            self._say("gf_bridge.dll not found: " + BRIDGE_DLL)
            if not FROZEN:
                self._say("  dev: 'Build bridge (dev)' first")
            return
        if not messagebox.askokcancel("Inject bridge",
                "Inject the prebuilt gf_bridge.dll into the running game?"):
            return
        self._say(gf_native.inject_dll(pid, BRIDGE_DLL))
        self._refresh_status()

    def _build_bridge_dev(self):
        # Dev-only: recompile gf_bridge.dll with zig after changing bridge.c. The DLL must be
        # unloaded (relaunch the game first if the bridge is live).
        if self._bridge_loaded():
            messagebox.showinfo("Build bridge (dev)",
                "The bridge is loaded, so gf_bridge.dll is file-locked. Relaunch the game first.")
            return
        self._shell_async(
            ["zig", "cc", "-target", "x86_64-windows-gnu", "-shared", "-O2",
             "-o", "gf_bridge.dll", "bridge.c"],
            "build gf_bridge.dll (zig)", cwd=GFBRIDGE)

    def _write(self, settings: dict):
        self._say(f"trigger: {settings}")
        if self.backend:
            self.backend.apply(settings)
        self._drain()

    def _reset(self):
        for section, fields in CONFIG.items():
            for dvar, _l, _k, _s, default in fields:
                self.vars[dvar].set(default)
        self._say("reset to defaults (not yet applied)")

    def _load_current(self):
        # Snap every field to the game's LIVE config (config_scan.py: the GSC publishes the
        # packed chunks + gf_oob + bot knobs as a marked string, swept read-only from memory).
        # This is the ONLY read path - the bridge is app->game only - so it is how the app
        # learns what the in-game menu (or a previous run) set. Also seeds _applied so the
        # pending/Next-round logic treats the loaded values as the baseline.
        if config_scan is None or gf_native is None:
            self._say("load current: config_scan / gf_native not importable")
            return
        if getattr(self, "_loadcur_busy", False):
            return
        self._loadcur_busy = True
        self._say("load current: sweeping game memory...")

        def worker():
            try:
                pid = gf_native.find_game_pid()
                if not pid:
                    raise RuntimeError("game not running")
                r = config_scan.read_config(pid, self._defaults)
                self.root.after(0, lambda: self._load_current_done(r, None))
            except Exception as e:                      # noqa: BLE001 - surfaced in the log
                self.root.after(0, lambda: self._load_current_done(None, str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def _load_current_done(self, r, err):
        self._loadcur_busy = False
        if err:
            self._say("load current: " + err)
            return
        if r is None:
            self._say("load current: no GFCFG in memory (menu injected? match running?)")
            return
        tick, cfg = r
        n = 0
        for dvar, val in cfg.items():
            if dvar not in self.vars:
                continue
            try:
                cur = self.vars[dvar].get()
            except Exception:
                cur = None
            if cur != val:
                self.vars[dvar].set(val)          # trace re-adds it to _touched; clear below
                n += 1
            self._applied[dvar] = val             # loaded value is the new baseline
            self._touched.discard(dvar)           # not a pending change - it IS the game's value
        self._say(f"load current: {len(cfg)} fields read, {n} changed to match the game (tick {tick})")


    def _say(self, msg: str):
        self.logw.insert("end", msg + "\n")
        self.logw.see("end")

    def _drain(self):
        if self.backend and self.backend.log:
            for line in self.backend.log:
                self.logw.insert("end", "  " + line + "\n")
            self.backend.log.clear()
            self.logw.see("end")


def main() -> int:
    # The standalone .exe is the deploy tool -> LIVE by default (pass --dry to preview).
    # The dev script stays dry-run-safe unless --live.
    if "--dry" in sys.argv:
        live = False
    else:
        live = FROZEN or ("--live" in sys.argv)
    root = tk.Tk()
    App(root, live)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
