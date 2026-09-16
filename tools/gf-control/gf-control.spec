# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the standalone Gunfight Host Control .exe.
#
#   cd tools/gf-control
#   pyinstaller gf-control.spec           # -> dist/gf-control/  (onedir; zip + share)
#
# Bundles the PREBUILT runtime artifacts so the target machine needs only the game:
#   - the control app (this + gf_native + roster_scan + bridge_channel)
#   - gunfight_menu.gscc   (prebuilt payload)      -> payloads/
#   - gf_bridge.dll        (prebuilt native bridge)-> gf-bridge/
#   - cwpatch DLL          (irreplaceable binary)  -> vendor/
#   - ACTS bin             (the injectcw injector) -> acts/
# NONE of the dev toolchain (zig/ACTS-to-build/Python) is needed on the target.
#
# Rebuild the two payload/bridge artifacts first (they must be current):
#   ..\..\bootstrap.ps1 -SkipDump         # rebuilds payloads
#   cd ..\gf-bridge && zig cc -target x86_64-windows-gnu -shared -O2 -o gf_bridge.dll bridge.c

import os
from PyInstaller.building.datastruct import Tree

HERE = os.path.abspath(SPECPATH) if 'SPECPATH' in dir() else os.path.abspath('.')  # tools/gf-control
REPO = os.path.dirname(os.path.dirname(HERE))     # tools/gf-control -> BOCW-Gunfight
ROOT = os.path.dirname(REPO)                       # ...\bocw  (siblings live here)
BRIDGE = os.path.join(REPO, 'tools', 'gf-bridge')

datas = [
    (os.path.join(HERE, 'assets', 'logo.png'), 'assets'),
    (os.path.join(HERE, 'assets', 'logo.ico'), 'assets'),
    (os.path.join(BRIDGE, 'bridge_channel.py'), 'gf-bridge'),
    (os.path.join(BRIDGE, 'gf_bridge.dll'), 'gf-bridge'),
    (os.path.join(ROOT, 'payloads', 'gunfight_menu.gscc'), 'payloads'),
    (os.path.join(ROOT, 'vendor-backup', 'discord_game_sdk.CWPATCH-13824.dll'), 'vendor'),
]
# ACTS is the injector (acts injectcw). Bundle its whole bin\ recursively into acts\.
acts_tree = Tree(os.path.join(ROOT, 'ACTS', 'bin'), prefix='acts')

a = Analysis(
    ['gf_control.py'],
    pathex=[HERE],
    binaries=[],
    datas=datas,
    hiddenimports=['gf_native', 'roster_scan'],   # roster_scan: the Connected-players sweep
    hookspath=[],
    excludes=['dvar_backend'],   # optional dev-only backend; app runs on BridgeBackend
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name='gf-control',
    debug=False,
    console=False,               # windowed GUI, no console
    icon=os.path.join(HERE, 'assets', 'logo.ico'),
)
coll = COLLECT(
    exe, a.binaries, a.datas, acts_tree,
    name='gf-control',
)
