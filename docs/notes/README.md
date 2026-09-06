# Notes index

Single-incident deep dives. One file per finding. `.claude/CLAUDE.md` links here with `[[slug]]`,
which resolves to `docs/notes/<slug>.md`.

These are **not** auto-loaded. Open the one you need.

## Index

- [test-pc-setup](test-pc-setup.md) — headless closet test box over RDP: reachability, RDP tuning,
  the Activision-account trap, the toolchain mirror, and the ACTS auto-update gotchas.

## Conventions

- One finding per file, named `<slug>.md`, same slug as the `[[link]]` that points at it.
- Lead with the conclusion, then the evidence, then the file/line references.
- Record **dead ends** as their own notes. A dead end that isn't written down gets re-researched.
- Cite `bocw-source` paths in full, e.g. `scripts/mp_common/gametypes/gunfight.gsc:1137`.
- ⚠ The dump is a merge across game patches. Line numbers drift between dump revisions. Quote the
  surrounding code, not just the line number.
