#!/usr/bin/env python3
"""Arm / re-arm the gf_luiload test by setting the gf_luiload_go dvar through cwpatch's command executor.

    python tools/lui/luigo.py 1    # -> the gated gf_luiload CSC fires luiload ONCE on the present pool chunk
    python tools/lui/luigo.py 0    # falling edge: re-arms so a later `1` fires again (after re-injecting the pool)

Runs `set gf_luiload_go <val>` via cwpatch's executor on a remote thread (the same route the gf-control app
uses). Needs cwpatch loaded (else it says so). This is a memory write + CreateRemoteThread - klaze runs it.
Order for the test: inject the pool chunk FIRST (luapool.py --inject), confirm the HUD reads go:0, THEN `1`.
"""
import importlib.util, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    'dvar_backend', os.path.join(HERE, '..', 'gf-control', 'dvar_backend.py'))
db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(db)


def main():
    val = sys.argv[1] if len(sys.argv) > 1 else '1'
    b = db.DvarBackend(dry_run=False)
    b.attach()                                   # opens the game, reads cwpatch's pointer slots (no code runs)
    try:
        ok = b.exec_command('set gf_luiload_go %s' % val)  # resolves executor/slot itself; raises if no cwpatch
    finally:
        b.close()
    print('set gf_luiload_go %s: %s' % (val, 'OK' if ok else 'FAILED'))
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
