"""Python transport for the in-context bridge (docs/notes/in-context-bridge.md).

Writes console command lines into the named shared-memory block that bridge.c polls from
inside the game. No game memory is touched - this is plain shared memory between two
processes in the same session, so it needs no elevation and nothing that can wedge the game.

    python bridge_channel.py "set gf_cmd_go 1"
    python bridge_channel.py switch mp_miami gunfight        # composes the gf_cmd_* set lines
    python bridge_channel.py stage  mp_raid_rm gunfight
    python bridge_channel.py fillbots | removebots | restart
    python bridge_channel.py status                          # is the bridge DLL listening?

The channel carries one or more '\\n'-separated console commands per send; the DLL runs each.
All mod semantics live here and in GSC - the DLL is a generic executor.

⚠ Inert until bridge.c is built and loaded in the game. Safe to run anyway (it just writes
shared memory); `status` reports whether the DLL has stamped the magic.
"""
from __future__ import annotations

import mmap
import struct
import sys

NAME = "gf_bridge"          # must match SHM_NAME in bridge.c (session-local namespace)
SIZE = 4096          # must match SHM_SIZE in bridge.c; holds a full config apply in one message
MAGIC = 0x31424647          # 'GFB1', must match SHM_MAGIC in bridge.c
HDR = 12                    # magic(4) + seq(4) + len(4)


def _map() -> mmap.mmap:
    # tagname opens the existing mapping if the DLL (or a prior run) created it, else creates it.
    return mmap.mmap(-1, SIZE, tagname=NAME)


def send(commands, quiet: bool = False):
    """commands: a string (possibly multi-line) or a list of command strings.

    Returns (seq, listening): the sequence number stamped and whether the DLL's magic was
    already present (i.e. the bridge is loaded). Prints a one-line status unless quiet=True -
    the GUI passes quiet and formats its own log line."""
    if isinstance(commands, (list, tuple)):
        commands = "\n".join(commands)
    payload = commands.encode("ascii")[: SIZE - HDR - 1]
    m = _map()
    try:
        magic, seq, _ = struct.unpack_from("<III", m, 0)
        seq = (seq + 1) & 0xFFFFFFFF
        # write body first, then header, then bump seq last so the DLL never reads a torn command
        m[HDR : HDR + len(payload)] = payload
        struct.pack_into("<III", m, 0, MAGIC, seq, len(payload))
        m.flush()
        listening = (magic == MAGIC)
        if not quiet:
            note = "" if listening else "   (note: DLL magic not seen yet - is bridge.dll loaded?)"
            print(f"sent #{seq}: {commands!r}{note}")
        return seq, listening
    finally:
        m.close()


def probe():
    """(listening, seq, last_len) without printing - the GUI's connect() check."""
    m = _map()
    try:
        magic, seq, ln = struct.unpack_from("<III", m, 0)
        return (magic == MAGIC), seq, ln
    finally:
        m.close()


def status() -> int:
    listening, seq, ln = probe()
    if listening:
        print(f"bridge DLL is listening (seq={seq}, last len={ln}).")
        return 0
    print("bridge DLL not detected (magic unset). Build+load bridge.c in the game.")
    return 1


# -- command composers: mirror the gf_cmd_* channel the GSC cmd_poll() consumes -------------
def _switch(map_name: str, gametype: str, stage: int) -> list[str]:
    lines = []
    if map_name:
        lines.append(f"set gf_cmd_map {map_name}")
    if gametype:
        lines.append(f"set gf_cmd_gametype {gametype}")
    lines.append(f"set gf_cmd_stage {stage}")
    lines.append("set gf_cmd_go 1")
    return lines


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    verb = argv[0]
    if verb == "status":
        return status()
    if verb == "switch":
        send(_switch(argv[1] if len(argv) > 1 else "", argv[2] if len(argv) > 2 else "", 0))
    elif verb == "stage":
        send(_switch(argv[1] if len(argv) > 1 else "", argv[2] if len(argv) > 2 else "", 1))
    elif verb in ("fillbots", "removebots", "restart"):
        send([f"set gf_cmd_{verb} 1", "set gf_cmd_go 1"])
    else:
        # raw passthrough: the whole argv joined is one console command
        send(" ".join(argv))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
