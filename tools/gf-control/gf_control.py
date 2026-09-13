"""Gunfight Host Control - a Windows GUI that drives the in-match mod by writing its
gf_* dvars, so the host can run the match from a real window on a second screen / RDP
instead of the ~4-line in-game feed the game caps us to.

HOW IT WORKS. The injected menu (src/gunfight_menu) re-reads its gf_* dvars every round
in mod_apply(). So anything in the CONFIG tab below takes effect next round the moment
the dvar is written - no new in-game code. ACTIONS (map/gametype stage or switch, fill
bots, restart) are one-shots: they are written as gf_cmd_* trigger dvars + gf_cmd_go, and
the menu payload's command-poller (cmd_poll / cmd_dispatch in gunfight_menu.gsc) runs
them host-side and clears the triggers. gf_cmd_stage=1 turns a map/gametype switch into
a STAGE: switchmap_load only, the lobby shows the map when the match ends.

SAFETY. Dry-run by default: it shows every dvar it WOULD write and touches no memory.
`--live` attaches to the game and writes for real - which needs the dvar-setter
signature confirmed in-game first (see README; the exe is encrypted at rest). Per the
project guard the agent writes this; klaze runs the live memory writes on the test box.

    python gf_control.py            # dry-run, safe anywhere
    python gf_control.py --live     # writes dvars (needs confirmed sig + the game up)
"""

from __future__ import annotations

import sys
import tkinter as tk
from tkinter import ttk

try:
    from dvar_backend import DvarBackend, BackendError
except Exception:  # backend import must never stop the GUI from opening in dry-run
    DvarBackend = None
    BackendError = Exception

# ---- control schema: (dvar, label, kind, spec, default) ----------------------
# kind: "choice" spec=[(label,value)...] | "int" spec=(min,max,step) | "toggle"
CONFIG = {
    "Teams": [
        ("gf_team_size", "Team size", "choice",
         [("2v2", 2), ("3v3", 3), ("4v4", 4), ("5v5", 5), ("6v6", 6)], 4),
    ],
    "Round": [
        ("gf_timer_seconds", "Round timer (s)", "int", (0, 1440, 10), 60),
        # Pre-match / pre-round countdowns (mod_periods in gunfight_menu.gsc). The stock rows
        # offer 5-60 / 0-30; -1 = the lobby's own row. A change lands on the NEXT countdown.
        ("gf_prematch", "Pre-match countdown (s, -1 = lobby)", "int", (-1, 60, 1), 15),
        ("gf_preround", "Pre-round countdown (s, -1 = lobby)", "int", (-1, 30, 1), 7),
    ],
    "Loadout": [
        ("gf_loadout", "Loadout set", "choice",
         [("Default", 0), ("Snipers", 1), ("Blueprints", 2), ("Melee", 3)], 0),
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
        ("gf_roundwinlimit", "First to N rounds (-1 = leave)", "int", (-1, 50, 1), -1),
        ("gf_roundlimit", "Round cap (-1 = leave)", "int", (-1, 50, 1), -1),
        ("gf_rounds_loadout", "Rounds per loadout (-1 = leave)", "int", (-1, 20, 1), -1),
    ],
    "Bots": [
        # Per-team difficulty = the stock bot_difficulty_<team> gametype setting (docs/notes/bots.md).
        # -1 leaves the lobby's row alone; 4 = the CUSTOM struct built from the knobs below.
        ("gf_bot_diff_allies", "Bot difficulty: allies", "choice",
         [("Lobby's value", -1), ("Recruit", 0), ("Regular", 1), ("Hardened", 2),
          ("Veteran", 3), ("CUSTOM", 4)], -1),
        ("gf_bot_diff_axis", "Bot difficulty: axis", "choice",
         [("Lobby's value", -1), ("Recruit", 0), ("Regular", 1), ("Hardened", 2),
          ("Veteran", 3), ("CUSTOM", 4)], -1),
        ("gf_bot_passive", "Bots passive (ignore everyone)", "toggle", None, 0),
        # CUSTOM knobs. Stock recruit/regular/hardened/veteran values in the comments.
        ("gf_bot_hit", "Custom: hit chance % (40/50/60/90)", "int", (0, 100, 5), 100),
        ("gf_bot_head", "Custom: headshot chance % (0/3/10/20)", "int", (0, 100, 5), 50),
        ("gf_bot_react", "Custom: aim delay ms (1400/1100/700/300)", "int", (0, 3000, 50), 100),
        ("gf_bot_fire", "Custom: fire window ms (300/400/500/700)", "int", (100, 3000, 100), 1000),
        ("gf_bot_hip", "Custom: hipfire accuracy % (50/50/60/70)", "int", (0, 100, 5), 100),
        ("gf_bot_far", "Custom: long-range accuracy % (100/80/66/50)", "int", (0, 100, 5), 90),
        ("gf_bot_semi", "Custom: semi-auto tap delay ms (800/600/400/150)", "int", (0, 2000, 50), 100),
        ("gf_bot_burst", "Custom: burst delay ms (1200/900/700/250)", "int", (0, 2000, 50), 100),
        ("gf_bot_moveshoot", "Custom: move while shooting", "toggle", None, 1),
        ("gf_bot_fastaim", "Custom: look speed", "choice",
         [("Slow (recruit)", 0), ("Fast (veteran)", 1), ("Max", 2)], 1),
        ("gf_bot_sprint", "Custom: sprint", "toggle", None, 1),
        ("gf_bot_melee", "Custom: melee", "toggle", None, 1),
        ("gf_bot_prone", "Custom: prone", "toggle", None, 1),
        ("gf_bot_slide", "Custom: slide", "toggle", None, 1),
        ("gf_bot_crouch", "Custom: crouch", "toggle", None, 1),
    ],
    "Movement": [
        ("gf_gravity", "Gravity (bg_gravity, stock 800)", "int", (20, 1600, 20), 800),
        ("gf_jump_boost", "Jump boost (u/s added at takeoff, 0 = off)", "int", (0, 3000, 50), 0),
        ("gf_speed", "Move speed %", "int", (25, 400, 25), 100),
        ("gf_falldamage", "Fall damage (off = boosted jumps land clean)", "toggle", None, 1),
        ("gf_jump", "Builtin jump height (-1 = engine default, untested)", "int", (-1, 1000, 10), -1),
    ],
    "Spawns / Map method": [
        ("gf_spawn_guard", "Spawn guard (untested)", "toggle", None, 0),
        ("gf_map_method", "Map switch method", "choice",
         [("Session (lobby follows)", 1), ("Carry (load-time)", 0)], 1),
    ],
    "Menu display": [
        ("gf_menu_lines", "In-game rows", "int", (2, 20, 1), 3),
        ("gf_menu_region", "Panel region", "choice",
         [("Lower-left feed", 0), ("Center", 1), ("Status left + menu centre", 2)], 0),
    ],
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
GAMETYPES = ["gunfight", "gunfight_3v3", "tdm", "dm", "dom", "koth", "sd", "conf", "control"]


class App:
    def __init__(self, root: tk.Tk, live: bool):
        self.root = root
        self.live = live
        self.vars: dict[str, tk.Variable] = {}
        self.backend = DvarBackend(dry_run=not live) if DvarBackend else None

        root.title("Gunfight Host Control" + ("  [LIVE]" if live else "  [DRY-RUN]"))
        root.geometry("560x760")

        self._banner()
        nb = ttk.Notebook(root)
        nb.pack(fill="both", expand=True, padx=8, pady=(0, 4))
        nb.add(self._config_tab(nb), text="Config")
        nb.add(self._actions_tab(nb), text="Actions")
        self._logbox()
        self._connect()

    def _banner(self):
        c = "#7a1f1f" if self.live else "#20406a"
        bar = tk.Frame(self.root, bg=c)
        bar.pack(fill="x")
        txt = ("LIVE - writes dvars to the running game"
               if self.live else "DRY-RUN - shows writes only, touches nothing")
        tk.Label(bar, text=txt, bg=c, fg="white", font=("Segoe UI", 10, "bold")).pack(pady=4)

    def _config_tab(self, nb) -> ttk.Frame:
        tab = ttk.Frame(nb)
        for section, fields in CONFIG.items():
            box = ttk.LabelFrame(tab, text=section)
            box.pack(fill="x", padx=8, pady=4)
            for dvar, label, kind, spec, default in fields:
                self._field(box, dvar, label, kind, spec, default)
        btns = ttk.Frame(tab)
        btns.pack(fill="x", padx=8, pady=6)
        ttk.Button(btns, text="Apply config", command=self._apply_config).pack(side="left")
        ttk.Button(btns, text="Reset to defaults", command=self._reset).pack(side="left", padx=6)
        return tab

    def _field(self, parent, dvar, label, kind, spec, default):
        row = ttk.Frame(parent)
        row.pack(fill="x", padx=6, pady=2)
        ttk.Label(row, text=label, width=30, anchor="w").pack(side="left")
        if kind == "choice":
            var = tk.IntVar(value=default)
            combo = ttk.Combobox(row, state="readonly",
                                 values=[l for l, _ in spec], width=22)
            combo.current([v for _, v in spec].index(default))
            combo.pack(side="left")
            combo.bind("<<ComboboxSelected>>",
                       lambda e, s=spec, v=var, c=combo: v.set(s[c.current()][1]))
            self.vars[dvar] = var
        elif kind == "int":
            lo, hi, step = spec
            var = tk.IntVar(value=default)
            ttk.Spinbox(row, from_=lo, to=hi, increment=step, textvariable=var,
                        width=10).pack(side="left")
            self.vars[dvar] = var
        elif kind == "toggle":
            var = tk.IntVar(value=default)
            ttk.Checkbutton(row, variable=var).pack(side="left")
            self.vars[dvar] = var

    def _actions_tab(self, nb) -> ttk.Frame:
        tab = ttk.Frame(nb)
        note = ("Actions write gf_cmd_* trigger dvars; the menu payload's command-poller\n"
                "runs them host-side. Stage = lobby shows the map when the match ends;\n"
                "Switch NOW = in-match session switch.")
        tk.Label(tab, text=note, fg="#8a5a00", justify="left").pack(anchor="w", padx=10, pady=6)

        box = ttk.LabelFrame(tab, text="Session switch (map + gametype)")
        box.pack(fill="x", padx=8, pady=4)
        self.map_var = tk.StringVar()
        allmaps = [f"{d}  [{m}]" for d, m in MAPS_6V6] + \
                  [f"{d}  [{m}]  (GF)" for d, m in MAPS_GF]
        self._maplut = {f"{d}  [{m}]": m for d, m in MAPS_6V6}
        self._maplut.update({f"{d}  [{m}]  (GF)": m for d, m in MAPS_GF})
        ttk.Label(box, text="Map").pack(anchor="w", padx=6)
        ttk.Combobox(box, state="readonly", values=allmaps, textvariable=self.map_var,
                     width=44).pack(padx=6, pady=2)
        self.gt_var = tk.StringVar(value="gunfight")
        ttk.Label(box, text="Gametype").pack(anchor="w", padx=6)
        ttk.Combobox(box, state="readonly", values=GAMETYPES, textvariable=self.gt_var,
                     width=20).pack(anchor="w", padx=6, pady=2)
        btns = ttk.Frame(box)
        btns.pack(padx=6, pady=6)
        # Two verbs, same as the in-game pick page. Stage = switchmap_load only: the
        # match keeps running and the pregame lobby shows the map when it ends.
        ttk.Button(btns, text="Stage for lobby (next match)",
                   command=lambda: self._switch(stage=True)).pack(side="left", padx=4)
        ttk.Button(btns, text="Switch NOW",
                   command=lambda: self._switch(stage=False)).pack(side="left", padx=4)

        box2 = ttk.LabelFrame(tab, text="Bots / match")
        box2.pack(fill="x", padx=8, pady=4)
        for text, cmd in [("Fill with bots", "fillbots"),
                          ("Remove all bots", "removebots"),
                          ("Restart match", "restart")]:
            ttk.Button(box2, text=text,
                       command=lambda c=cmd: self._cmd(c)).pack(side="left", padx=6, pady=6)
        # Single-bot verbs (docs/notes/bots.md). gf_cmd_addbot carries WHICH side:
        # 1 auto (smaller side, tie -> opposite the host) / 2 allies / 3 axis.
        box3 = ttk.LabelFrame(tab, text="Bots - one at a time")
        box3.pack(fill="x", padx=8, pady=4)
        for text, settings in [("Add bot (auto)", {"gf_cmd_addbot": 1}),
                               ("Add bot: allies", {"gf_cmd_addbot": 2}),
                               ("Add bot: axis", {"gf_cmd_addbot": 3}),
                               ("Remove one bot", {"gf_cmd_removebot": 1}),
                               ("Even up teams", {"gf_cmd_evenbots": 1})]:
            ttk.Button(box3, text=text,
                       command=lambda s=settings: self._write({**s, "gf_cmd_go": 1})
                       ).pack(side="left", padx=4, pady=6)
        return tab

    def _logbox(self):
        frame = ttk.LabelFrame(self.root, text="Log")
        frame.pack(fill="both", expand=False, padx=8, pady=4)
        self.logw = tk.Text(frame, height=9, bg="#101418", fg="#c8d0d8",
                            font=("Consolas", 9), wrap="none")
        self.logw.pack(fill="both", expand=True)

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

    def _apply_config(self):
        settings = {dvar: v.get() for dvar, v in self.vars.items()}
        self._say(f"apply {len(settings)} config dvars:")
        if self.backend:
            self.backend.apply(settings)
        else:
            for k, val in settings.items():
                self._say(f"  [no backend] set {k} {val}")
        self._drain()

    def _switch(self, stage: bool = False):
        m = self._maplut.get(self.map_var.get())
        if not m:
            self._say("pick a map first")
            return
        self._write({"gf_cmd_map": m, "gf_cmd_gametype": self.gt_var.get(),
                     "gf_cmd_stage": int(stage), "gf_cmd_go": 1})

    def _cmd(self, name):
        self._write({"gf_cmd_" + name: 1, "gf_cmd_go": 1})

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
    live = "--live" in sys.argv
    root = tk.Tk()
    App(root, live)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
