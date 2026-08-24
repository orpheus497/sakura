# BRIEFING — Sakura

Current project status and phase. Last updated: 2026-08-24 10:17.

---

## Current Phase

**Phase 4 — Session End. All four stages complete and verified.**

20 of 21 defects fixed; 1 (F2) cancelled on verification as an invalid finding. Tree
state: `zig build` OK · `zig build test` OK · `--validate-config` clean · all invariants
hold · 8/8 fonts build.

Nothing is in progress. Three governance questions remain open for a USER ruling and are
carried forward: D-002 (`AGENTS.md` untracked, in the product root), D-003 (FOSS clause
names pango/cairo, which this project does not use), D-005 (retroactive-commenting
prohibition vs the documentation standard).

USER approved execution on 2026-08-24 and lifted the Directive 3 gate on removals, with
the instruction that removals happen last and only after verifying they were still
unneeded. Stage 1 landed at 09:08, Stage 2 at 09:17, C5 and Stage 3 at 09:47, Stage 4 at
09:55, and the Hurmit verification at 10:00 — see PROGRESS.md.

The work is committed as `e510739` and `0f668ff`; `AGENTS.md` and `.devdocs/` are now
tracked. A later review pass (10:17) corrected tracker staleness, pinned the CI actions to
commit SHAs, gated the FreeBSD build on the invariant job, and fixed two verified
documentation errors: `--config` takes a directory rather than a file, and the box-position
options are measured from the top/left rather than the bottom/end.

---

## Project Status

Sakura is a FreeBSD-only TUI display manager, forked from Ly and rebranded in commit
`f38fae8`. The fork's two defining changes are the platform narrowing and the animated GIF
wallpaper. See BLUEPRINT.md for architecture.

**Documentation health after remediation: all audited defects closed.**

| Area | State |
| --- | --- |
| Name-level rebrand | Clean — 0 defects |
| Config ↔ code parity | Clean — 94/94 keys and values, `start_cmd` the one documented override |
| Lang ↔ code parity | Clean — 82/82 across all 25 locales |
| Readme factual claims | Verified against `build.zig`, `install.zig`, `interop.zig`, `main.zig` |
| FreeBSD-only premise | Consistent; no other-OS support remains |
| GIF-wallpaper focus | Font tool synthesises all 18 glyphs; 8/8 fonts build |
| Defaults documentation | Reconciled; the one divergence is documented in place |
| FOSS compliance (Directive 2) | Compliant — all 10 deps MIT/BSD |
| Invariant drift | Now enforced in CI by `tools/check_invariants.py` |

---

## Progress

- Audit: **100%** (D-001 complete)
- `.devdocs/` initialization: **100%** (Phase 1 complete)
- Remediation: **100%** — 20 of 21 defects fixed, 1 (F2) cancelled as an invalid finding,
  0 in progress

---

## Current Blockers

None blocking work. Three governance questions remain for a USER ruling:

1. **D-002** — `AGENTS.md` sits in the product root while Directive 4 reserves the root for
   product code. It is now tracked (committed in `0f668ff`), so the tracking half of the
   question is settled by fact; the *location* question is not.
2. **D-003** — the Directive 2 FOSS clause names `pango`/`cairo`, which this project does
   not use and has no route to using. Treated as inert.
3. **D-005** — the mandated comment prefixes versus the prohibition on adding comments
   retroactively. Applied as: bring existing comments into line when already editing them;
   do not retrofit headers onto untouched files.

None of the three blocks further work; each is an editorial call for the owner.

---

## Recent Architectural Decisions

- **D-001** — Post-rebrand audit complete. Two structural insights recorded: `install.zig`
  substitutes prefix tokens inside *comments* as well as values (root cause of B2, and a
  standing hazard for any future prefix change); and the wallpaper glyph set is duplicated
  across four locations, three of which drifted.
- **D-004** — Directive 2 FOSS compliance verified. All ten dependencies MIT or BSD; zero
  copyleft, zero proprietary. WTFPL applies to the project itself, not a dependency, and
  is permissive regardless.

---

## Next 3–5 Concrete Execution Steps

| # | Step | Est. | Gate |
| --- | --- | --- | --- |
| 1 | Rule on D-002, D-003, D-005 | 10 min, USER | — |
| 2 | Review and commit the working-tree changes from the 10:17 review pass (5 files) | 10 min | — |
| 3 | Confirm the CI workflow actually runs on GitHub — it has never executed, only been validated locally | 15 min | push |
| 4 | Decide whether `contributing.md` should carry an AI-usage policy; it deliberately carries none | 10 min, USER | — |
| 5 | Optional: extend `check_invariants.py` to the cell-geometry invariant recorded in BLUEPRINT §6 | 30 min | — |

---

## Awaiting

Rulings on D-002, D-003 and D-005, and a review of the uncommitted changes. Nothing is
blocked on them; the remediation itself is complete and verified.
