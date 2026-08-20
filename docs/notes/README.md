# Notes index

Single-incident deep dives. One file per finding. `.claude/CLAUDE.md` links here with `[[slug]]`,
which resolves to `docs/notes/<slug>.md`.

These are **not** auto-loaded. Open the one you need.

## Index

- [[phase-0-1-test-protocol]] — step-by-step protocol for the Phase 0 and Phase 1 tests.
  Not a finding yet: it carries a **Results** section that gets filled in on the run, at which
  point it becomes the finding record for both gates.

## Conventions

- One finding per file, named `<slug>.md`, same slug as the `[[link]]` that points at it.
- Lead with the conclusion, then the evidence, then the file/line references.
- Record **dead ends** as their own notes. A dead end that isn't written down gets re-researched.
- Cite `bocw-source` paths in full, e.g. `scripts/mp_common/gametypes/gunfight.gsc:1137`.
- ⚠ The dump is a merge across game patches. Line numbers drift between dump revisions. Quote the
  surrounding code, not just the line number.
