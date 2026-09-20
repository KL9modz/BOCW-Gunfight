# dvar-live — read-only live-engine RE kit (2026-09-20, built for docs/notes/slide.md)

Everything here opens `BlackOpsColdWar.exe` with `PROCESS_VM_READ | PROCESS_QUERY_INFORMATION` and
READS. No writes, no remote threads. Run with the game up (any menu or match); outputs land in the
current directory, so run from `C:\bocw\reference` to keep them next to `funcs_cw.csv`.

    python dvar_pool_scan.py --find bg_gravity slide_subsequentslidescale   # hash-scan (12 GB, ~100 s), annotated dvar_t dumps
    python arena_full.py 0xeee0090 dvars_cw_live.csv        # walk the static dvar arena around that dvar_t -> every registered dvar
    python resolve.py                                       # name the hashes (BO4 list + every dump literal) -> dvars_cw_live_named.csv
    python regmap.py                                        # every dvar hash used as a mov r64, imm64 -> registration site (dvar_regmap.csv)
    python code_imms.py 0x93ab000-0x93ae000                 # the dvars registered in one code window, in order (family clustering)
    python xrefs.py 0x121343f0 0x12134428                   # who READS a dvar pointer slot (finds the consuming code)
    python callers.py 0xaf28600                             # E8 callers of a function
    python disasm.py 0xaf28600:0x1e0                        # capstone, annotated with dvar names / rip targets / call targets

Anchors above are for the exe dated 2026-06-12. After a game update: `--find bg_gravity` again, take
the data-region sighting as the new arena anchor, re-run arena_full + resolve + regmap.

CW `dvar_t` (0x40 B): hash@0 · hashnext@8 · DvarData*@0x10 (4 x 0x20: current/latched/reset/spare) ·
type@0x18 (1 BOOL 2 FLOAT 3-5 FLOAT_2/3/4 6 INT 7 ENUM 8 STRING 10 INT64 11 UINT64) · flags@0x1c ·
domain@0x20. Register fns: Bool exe+0xbf9cd30, Float exe+0xbf9d2d0, Int exe+0xbf9d6c0.

`fnv.py` = fnv1a63 (dvar / asset / `#"..."` names). `t89.py` = the T8/T9 SCRIPT hash (builtin and
field names — resolves the engine table's `function_xxxxxxxx` rows; 116 named in
`reference/funcs_cw_resolved.csv`).
