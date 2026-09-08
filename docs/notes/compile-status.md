# Compile status — stages 1–2

`check-gsc.ps1 -CompileOnly` on the Windows Remote Control box **`vmi3404923`**, 2026-09-08.

| | |
|---|---|
| Result | **All five compiled and round-tripped.** |
| ACTS version | ⚠ **not recorded** — see below |
| Provenance | ⚠ **relayed by klaze, not verified here** — see below |

| Project | Stages 1–2 | Stages 3–4 (`check-dump.py`) | Arity (`check-args.py`) |
|---|---|---|---|
| `lobby_probe` | ✅ compiled | ✅ clean (1 unused-by-stock) | ✅ 0 mismatches |
| `test_switchmap` | ✅ compiled | ✅ clean | ✅ 0 mismatches |
| `test_addclients` | ✅ compiled | ✅ clean | ✅ 0 mismatches |
| `test_teamfill` | ✅ compiled | ✅ clean | ✅ 0 mismatches |
| `test_maprestart` | ✅ compiled | ✅ clean | ✅ 0 mismatches |

**What this closes.** Dialect and syntax were the last unchecked class, and the one that caused two of
this project's three game-crashing defects. Every offline check the project has now runs green on all
five.

---

## ⚠ Two caveats on this record, both about provenance

**1 · The VPS could not push, so this file was written by the cloud session from a relayed summary.**
A fresh clone over anonymous HTTPS can read but not push. Nobody in this conversation has seen the
ACTS output; the result is klaze's report of what that session printed. It is recorded because it is
almost certainly right and useful, **not** because it was verified here.

**2 · The ACTS version is unknown.** The bootstrap asked for it and it did not come back. The project
pins **v3.3.0** (`.claude/CLAUDE.md` → *Toolchain*). If the box installed a newer release, these
results are from a different compiler than the one the project claims to use, and a future
discrepancy would be very hard to explain. **Cheap to fix:** on that box,

```powershell
& $HOME\ACTS\bin\acts.exe --version
```

## Still not a PASS

⚠ `-CompileOnly` runs stages 1–2 only. It compiles and round-trips; it does **not** resolve API calls
against the dump. That is deliberate — the script refuses to print `PASS` without stages 3–4.

Those stages did run, separately, via [`../../tools/check-dump.py`](../../tools/check-dump.py) against
`ate47/bocw-source` in the cloud session, and came back with **0 fatal, 1 unused-by-stock**
(`isvalidgametype`, a real engine builtin with no stock caller — `lobby_probe` already emits it last).

**So all four stages have now passed, across two machines, rather than in one harness run.** A single
full `check-gsc.ps1` on the dev PC would be one command and would supersede this whole file.

## Fixing the push, if this becomes routine

The gate is only useful long-term if its results land in the repo without a human relaying them.
Options, cheapest first:

1. **Relay by hand** — what happened here. Fine once, poor as a habit: the provenance caveats above
   are the cost.
2. **Give that box a credential** for `KL9modz/BOCW-Gunfight` — a deploy key or a fine-grained PAT
   scoped to this repo only. ⚠ **Do not paste a token into a chat session.** Configure it on the box
   directly.
3. **Have it emit the report to stdout** and paste the whole thing rather than a summary. No secrets,
   and it preserves the verbatim ACTS output, which is the part that actually matters when something
   fails.

⚠ Option 3 is the right default. The value of a compile gate is the **error text** when it goes red;
a green summary is the case where the detail matters least.
