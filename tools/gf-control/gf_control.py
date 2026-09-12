"""Gunfight Host Control - a Windows GUI that drives the in-match mod by writing its
gf_* dvars, so the host can run the match from a real window on a second screen / RDP
instead of the ~4-line in-game feed the game caps us to.

HOW IT WORKS. The injected menu (src/gunfight_menu) re-reads its gf_* dvars every round
in mod_apply(). So anything in the CONFIG tab below takes effect next round the moment
the dvar is written - no new in-game code. ACTIONS (map/gametype switch, fill bots,
restart) are not dvars the mod reads yet; they are staged as gf_cmd_* trigger dvars for
a small in-game command-poller (the next increment - see README). Until that poller
ships, the Actions tab writes the trigger dvars but nothing consumes them.

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
    ],
    "Loadout": [
        ("gf_loadout", "Loadout set", "choice",
         [("Default", 0), ("Snipers", 1), ("Blueprints", 2), ("Melee", 3)], 0),
        ("gf_spyplane", "Spy plane", "choice",
         [("Off", 0), ("On", 1), ("Shared (hidden)", 3)], 0),
    ],
    "Match": [
        ("gf_roundwinlimit", "First to N rounds (-1 = leave)", "int", (-1, 50, 1), -1),
        ("gf_roundlimit", "Round cap (-1 = leave)", "int", (-1, 50, 1), -1),
        ("gf_rounds_loadout", "Rounds per loadout (-1 = leave)", "int", (-1, 20, 1), -1),
    ],
    "Spawns / Map method": [
        ("gf_spawn_guard", "Spawn guard (untested)", "toggle", None, 0),
        ("gf_map_method", "Map switch method", "choice",
         [("Session (lobby follows)", 1), ("Carry (load-time)", 0)], 1),
    ],
    "Menu display": [
        ("gf_menu_lines", "In-game rows", "int", (2, 20, 1), 3),
        ("gf_menu_region", "Panel region", "choice",
         [("Lower-left feed", 0), ("Center", 1)], 0),
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
        note = ("Actions write gf_cmd_* trigger dvars. They need the in-game\n"
                "command-poller (next increment) before the game acts on them.")
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
        ttk.Button(box, text="Switch map/gametype", command=self._switch).pack(padx=6, pady=6)

        box2 = ttk.LabelFrame(tab, text="Bots / match")
        box2.pack(fill="x", padx=8, pady=4)
        for text, cmd in [("Fill with bots", "fillbots"),
                          ("Remove all bots", "removebots"),
                          ("Restart match", "restart")]:
            ttk.Button(box2, text=text,
                       command=lambda c=cmd: self._cmd(c)).pack(side="left", padx=6, pady=6)
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

    def _switch(self):
        m = self._maplut.get(self.map_var.get())
        if not m:
            self._say("pick a map first")
            return
        self._write({"gf_cmd_map": m, "gf_cmd_gametype": self.gt_var.get(), "gf_cmd_go": 1})

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
