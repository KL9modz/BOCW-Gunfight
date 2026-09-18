"""config_scan.py - read the mod's LIVE config out of the running game. READ-ONLY.

roster_scan.py / mapdata_scan.py's sibling. gunfight_menu.gsc's config_publish() keeps one
marked string alive in level.gf_cfgpub, refreshed every 2 s:

    GFCFG|<tick>|<c0>|<c1>|...|<c8>|oob=<n>|bot=<f0,..,f7>|bot2=<f8,..,f14>|veh=<mode,lock,hp,alt>|END

<c0>..<c8> are the RAW packed chunk dvars gf_c0..gf_c8 (6 fields each, the last short) - the
same chunks the app writes and the in-game menu writes via cfg_write_chunk, so this reflects
BOTH. An empty field (a chunk the game never wrote) resolves to the field's app default, exactly
as the GSC's cfg_load does. This is the ONLY way the app can know what is actually set: without
it, every field is just the app's launch default and a menu pick (or a previous app run) is
invisible.

Same read-only primitive as the roster sweep (OpenProcess VM_READ + VirtualQueryEx +
ReadProcessMemory; no thread, no write). The newest tick wins over a stale pool copy.

    python config_scan.py            # one sweep, print the resolved config
    python config_scan.py --raw      # also print the raw marker string

The app imports read_config() for its Config -> "Load current" button.
"""
from __future__ import annotations

import ctypes
import sys
import time

import roster_scan as rs

MARK = b"GFCFG|"
END = b"|END"
MAX_LEN = 4096

# The packed ORDER is pinned below, matching the app's PACKED and the GSC cfg_spec(); a chunk
# is split back into these keys by position. Per-field DEFAULTS (for resolving an empty chunk
# field the same way the app would) are passed in by the app, or lazily read from gf_control
# for standalone CLI use - a lazy import, so the app importing this module is not circular.

# The 52 packed keys, in the SORTED order the app and GSC agree on (gf_control.py PACKED).
PACKED = ['gf_autoswitch', 'gf_bot_diff_allies', 'gf_bot_diff_axis', 'gf_bot_passive', 'gf_camo',
          'gf_camo_pool', 'gf_camo_split', 'gf_caster_probe', 'gf_census', 'gf_customcac',
          'gf_dbg_assets', 'gf_dbg_families', 'gf_dbg_flags', 'gf_dbg_match', 'gf_dbg_spawn',
          'gf_dbg_structs', 'gf_falldamage', 'gf_feed_lines', 'gf_fly_fast', 'gf_fly_speed',
          'gf_gravity', 'gf_jump', 'gf_jump_boost', 'gf_loadout', 'gf_map_method', 'gf_menu_hspan',
          'gf_menu_lines', 'gf_menu_region', 'gf_prematch', 'gf_preround', 'gf_profile',
          'gf_roundlimit', 'gf_rounds_loadout', 'gf_roundwinlimit', 'gf_spawn_autospread',
          'gf_spawn_diag', 'gf_spawn_family', 'gf_spawn_gap', 'gf_spawn_guard', 'gf_spawn_pick',
          'gf_spec_slots', 'gf_speed', 'gf_spyplane', 'gf_strike', 'gf_switch_sides',
          'gf_switch_wait', 'gf_team_size', 'gf_timer_seconds', 'gf_zone', 'gf_zone_capture',
          'gf_zone_overtime', 'gf_zone_radius']

# The 15 bot-knob keys, in the order the app packs them into gf_bot (0-7) and gf_bot2 (8-14).
BOT_PACK = ['gf_bot_hit', 'gf_bot_head', 'gf_bot_react', 'gf_bot_fire', 'gf_bot_hip',
            'gf_bot_far', 'gf_bot_semi', 'gf_bot_burst', 'gf_bot_moveshoot', 'gf_bot_fastaim',
            'gf_bot_sprint', 'gf_bot_melee', 'gf_bot_prone', 'gf_bot_slide', 'gf_bot_crouch']


def _defaults() -> dict[str, int]:
    """Field -> app default, lazily read from gf_control.CONFIG (never drifts from the app).
    Lazy so the app can `import config_scan` without a circular import."""
    try:
        from gf_control import CONFIG
    except Exception:
        return {}
    return {dv: default for fields in CONFIG.values() for dv, _l, _k, _s, default in fields}


def parse(body: str, defaults: dict[str, int] | None = None) -> tuple[int, dict[str, int]] | None:
    """Parse one GFCFG body into (tick, {dvar: int}); None if malformed."""
    if defaults is None:
        defaults = _defaults()
    parts = body.split("|")
    if len(parts) < 10:
        return None
    try:
        tick = int(parts[0])
    except ValueError:
        return None
    chunks = parts[1:10]                       # gf_c0..gf_c8, raw (may be empty / short)
    extras = parts[10:]
    out: dict[str, int] = {}
    for i, key in enumerate(PACKED):
        fields = chunks[i // 6].split(",")
        pos = i % 6
        cell = fields[pos] if pos < len(fields) else ""
        if cell == "":
            if key not in defaults:
                return None
            out[key] = defaults[key]
        else:
            try:
                out[key] = int(cell)
            except ValueError:
                out[key] = defaults.get(key, 0)
    for e in extras:
        if e.startswith("oob="):
            try:
                out["gf_oob"] = int(e[4:])
            except ValueError:
                pass
        elif e.startswith("bot="):
            _unpack_bots(e[4:], BOT_PACK[:8], out, defaults)
        elif e.startswith("bot2="):
            _unpack_bots(e[5:], BOT_PACK[8:], out, defaults)
        elif e.startswith("veh="):
            # vehicle mode: mode,lock,hp,alt (plain dvars, docs/notes/vehicle-mode.md)
            _unpack_bots(e[4:], ["gf_vehmode", "gf_veh_lock", "gf_veh_hp", "gf_veh_alt"], out, defaults)
    return tick, out


def _unpack_bots(raw: str, keys: list[str], out: dict, defaults: dict) -> None:
    fields = raw.split(",") if raw else []
    for i, key in enumerate(keys):
        if i < len(fields) and fields[i] != "":
            try:
                out[key] = int(fields[i])
                continue
            except ValueError:
                pass
        if key in defaults:
            out[key] = defaults[key]


class ConfigScanner(rs.Scanner):
    """One sweep = the newest GFCFG marker across private writable regions, exe-range first."""

    def sweep(self) -> tuple[int, dict[str, int], bytes] | None:
        step = rs.Scanner._STEP
        buf = (ctypes.c_char * (step + MAX_LEN))()
        mv = memoryview(buf)
        got = ctypes.c_size_t(0)
        if self.module is None:
            self.module = rs.module_range(self.pid)
        regions = list(self._regions())

        def rank(r):
            b, s = r
            if self.module is not None and self.module[0] <= b < self.module[0] + self.module[1]:
                return (0, -s)
            return (1, b)

        regions.sort(key=rank)
        best_tick = -1
        best = None
        defaults = getattr(self, "_defaults_override", None)
        if defaults is None:
            defaults = _defaults()
        t0 = time.perf_counter()
        for base, size in regions:
            off = 0
            while off < size:
                want = min(step + MAX_LEN, size - off)
                if rs._k32.ReadProcessMemory(self.h, base + off, buf, want, ctypes.byref(got)) and got.value:
                    n = got.value
                    start = 0
                    while True:
                        i = buf.raw.find(MARK, start, n)
                        if i == -1:
                            break
                        j = buf.raw.find(END, i, min(n, i + MAX_LEN))
                        if j != -1:
                            body = buf.raw[i + len(MARK): j].decode("utf-8", "replace")
                            r = parse(body, defaults)
                            if r is not None and r[0] > best_tick:
                                best_tick = r[0]
                                best = (r[0], r[1], buf.raw[i: j + len(END)])
                        start = i + len(MARK)
                off += step
            # config_publish re-interns GFCFG every 2 s into the SAME string pool, which lives in
            # the exe-range private-RW region ranked first - so the newest tick is in the FIRST
            # region that yields any hit. Stop there instead of scanning all ~12k regions for a
            # marginally-newer copy. ~1 s vs ~50-70 s: the full sweep is what made the app's
            # pre-apply auto-sync (F4) delay EVERY Apply-now by ~a minute (klaze 2026-09-18). A
            # copy up to ~2 s old is fine for reading neighbour values that barely change.
            if best is not None:
                break
        self.last_sweep_s = time.perf_counter() - t0
        return best


def read_config(pid: int | None = None,
                defaults: dict[str, int] | None = None) -> tuple[int, dict[str, int]] | None:
    """One-shot: (tick, {dvar: int}) of the live config, or None if not found. The app passes
    its own defaults so this never imports gf_control (no circular import)."""
    if pid is None:
        pid = rs.find_game_pid()
    if not pid:
        return None
    sc = ConfigScanner(pid)
    sc._defaults_override = defaults
    try:
        r = sc.sweep()
    finally:
        sc.close()
    return None if r is None else (r[0], r[1])


def main() -> int:
    try:
        pid = rs.find_game_pid()
    except Exception as e:
        print("game not found:", e)
        return 1
    if not pid:
        print("game not running (BlackOpsColdWar.exe not found)")
        return 1
    sc = ConfigScanner(pid)
    try:
        r = sc.sweep()
        if r is None:
            print(f"no GFCFG string in memory ({sc.last_sweep_s:.1f} s) - is the menu injected and a match loaded?")
            return 0
        tick, cfg, raw = r
        print(f"live config (tick {tick}, swept {sc.last_sweep_s:.1f} s):")
        for k in sorted(cfg):
            print(f"  {k:24} {cfg[k]}")
        if "--raw" in sys.argv:
            print("\nraw:", raw.decode("utf-8", "replace"))
    finally:
        sc.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
