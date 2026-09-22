"""Decode a Cold War crash report's sre_stack against a compiled payload.

usage: python tools/sre-decode.py <payload.gscc> <offset> [<offset> ...]

The report (info.json in %LOCALAPPDATA%/Activision/Call Of Duty Black Ops Cold War/crash_reports/*.zip)
carries `sre_stack` lines like `[124cecff7280be52.3380156066.56:128255] (bytecode offset)`:
  124cecff7280be52 = the script's name hash (this one = clientids_shared.gsc, the injector's
                     replace target, i.e. OUR payload); 1686c9a67db75fae = player_vtol.gsc etc.
  3380156066       = the crc ACTS writes (0xc97916a2) - CONSTANT across our builds, it does not
                     identify the build
  56               = the VM (0x38)
  128255           = a FILE offset into the .gscc, pointing at the last byte of the call
                     instruction of that frame; the FIRST line is the innermost frame (the call
                     that was executing when the error fired), the next lines are its callers.
Calibrated on the 2026-09-19 map-scan crash (58199 -> mod_apply's call, 59831 -> mod_movement's)
and the 2026-09-21 forge crash (sethighlighted in forge_spawn_preview <- forge_enter <-
menu_run_item <- menu_think). If the frames do NOT form a caller chain, the game was running a
DIFFERENT build than the payload you decoded against - try the payloads/*.bak.gscc history.
Function names are the t89 script hash of the current source + a few git revisions.
"""
import os, re, subprocess, sys, tempfile
sys.path.insert(0, r'C:\bocw\BOCW-Gunfight\tools\dvar-live')
from t89 import t89scr

payload = sys.argv[1]
offs = [int(x) for x in sys.argv[2:]]
out = os.path.join(tempfile.gettempdir(), 'sre_dis_' + os.path.basename(payload))
os.makedirs(out, exist_ok=True)
subprocess.run([r'C:\bocw\ACTS\bin\acts.exe', 'gscd', '-a', '-l', '-L', '-H', '-o', out, payload],
               capture_output=True, cwd=r'C:\bocw\ACTS\bin')
dis = [f for f in os.listdir(out) if f.endswith('.gsc')][0]
lines = open(os.path.join(out, dis), encoding='utf-8', errors='replace').read().split('\n')

# name table: current source + a few commits back
names = set()
repo = r'C:\bocw\BOCW-Gunfight'
srcs = [open(os.path.join(repo, r'src\gunfight_menu\scripts\gunfight_menu.gsc'), encoding='utf-8').read()]
for rev in ('HEAD', 'HEAD~3', 'HEAD~8', '454705d'):
    r = subprocess.run(['git', '-C', repo, 'show', rev + ':src/gunfight_menu/scripts/gunfight_menu.gsc'], capture_output=True)
    if r.returncode == 0:
        srcs.append(r.stdout.decode('utf-8', 'replace'))
for s in srcs:
    names |= set(re.findall(r'^function (?:private )?(?:autoexec )?(\w+)\s*\(', s, re.M))
table = {t89scr(n): n for n in names}
# engine builtins (funcs_cw.csv, read off the live exe) so a hashed callee like sethighlighted resolves
try:
    import csv
    for r in csv.DictReader(open(r'C:\bocw\reference\funcs_cw.csv', encoding='utf-8', errors='replace')):
        table.setdefault(t89scr(r['func']), r['func'])
except OSError:
    pass
def nm(fn):
    m = re.match(r'function_([0-9a-f]{1,8})$', fn or '')
    return table.get(int(m.group(1), 16), fn) if m else fn

recs = []; name = None
for l in lines:
    m = re.match(r'function (?:private )?(?:autoexec )?(\w+)\(', l)
    if m: name = m.group(1); continue
    m = re.match(r'\.([0-9a-f]{8})\.([0-9a-f]{8}): (.*)', l)
    if m:
        t = re.sub(r'function_([0-9a-f]{1,8})(?![0-9a-f])', lambda mm: nm(mm.group(0)), m.group(3).strip())
        recs.append((int(m.group(1), 16), name, t))
hdr = [l for l in lines[:12] if 'size' in l or 'cseg' in l]
print(os.path.basename(payload), '|', ' '.join(h.strip('/ ') for h in hdr))
for o in offs:
    cands = [i for i, (a, _, _) in enumerate(recs) if a <= o]
    if not cands:
        print(o, 'before code'); continue
    i = max(cands)
    a, f, t = recs[i]
    print('  %6d 0x%05x  %-28s +%-3d %s' % (o, o, nm(f), o - a, t[:90]))
