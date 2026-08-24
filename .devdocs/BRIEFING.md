# BRIEFING — Sakura

Current project status and phase. Last updated: 2026-08-24 08:48.

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
the instruction that removals happen last and only after verifying they are no longer
needed. Stage 1 (A1, A2, B1, B2, C4) landed at 09:08; Stage 2 (C1, C2, C3) at 09:17 —
see PROGRESS.md.

**One new defect, C5, was found while verifying Stage 2 and is NOT fixed.** The font tool
synthesises blocks at the bounding-box width rather than the advance width, which makes the
readme's documented font-building workflow fail on every font tested. It is pre-existing
and unrelated to the C2 change. Tabled for approval — DECISIONS_LOG D-006, TODOS C5.

---

## Project Status

Sakura is a FreeBSD-only TUI display manager, forked from Ly and rebranded in commit
`f38fae8`. The fork's two defining changes are the platform narrowing and the animated GIF
wallpaper. See BLUEPRINT.md for architecture.

**Documentation health after audit D-001: substantially converted, 20 defects open.**

| Area | State |
| --- | --- |
| Name-level rebrand | Clean — 0 defects |
| Config ↔ code parity | Clean — 94/94 keys, both directions |
| Lang ↔ code parity | Clean for `en`; 24 locales missing `err_gif` |
| Readme factual claims | System-call and build claims verified; 6 gaps |
| FreeBSD-only premise | 2 contradictions inside the shipped config |
| GIF-wallpaper focus | 3 defects, incl. 1 behavioural in the font tool |
| Defaults documentation | 3 divergences; readme's blanket claim is false |
| FOSS compliance (Directive 2) | Compliant — all 10 deps MIT/BSD |

---

## Progress

- Audit: **100%** (D-001 complete)
- `.devdocs/` initialization: **100%** (Phase 1 complete)
- Remediation: **0%** — 0 of 20 defects fixed, 0 in progress

---

## Current Blockers

1. **Phase 1.4 halt.** Awaiting approval before executing PLANS.md Stage 1.
2. **3 governance questions** — DECISIONS_LOG D-002 (`AGENTS.md` untracked and in the
   product root), D-003 (FOSS clause names pango/cairo, which this project does not use),
   D-005 (retroactive-commenting prohibition vs the documentation standard).
3. **3 items gated by Directive 3** (Total Feature Retention) — TODOS F1, F2, and the
   "make `dur_file_path` optional" option under A1. All are removals; none will proceed
   without explicit instruction.
4. **1 item needs a direction call** — TODOS D2/Q1, whether to align the doom palette in
   code or in config.

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
| 1 | Rule on the 7 open questions (D-002, D-003, D-005; TODOS A1/Q1-Q2, D2/Q1, F1/Q1, F2/Q1) | 10 min, USER | — |
| 2 | **Stage 1** — B1 config line 1, B2 the two `/usr/local/local/…` paths, C4 `err_gif` × 24 locales | 30 min | approval |
| 3 | **Stage 1** — A1 replace the Ly logo in `res/example.dur` | 45 min | A1/Q1 answered |
| 4 | **Stage 2** — C2 quadrant synthesis in `mkvtfont.py`, C1 docstring, C3 readme glyph list | 45 min | approval; needs console verification |
| 5 | **Stage 3** — accuracy pass: D1, D3, E1, E2, F3 and the `readme.md:157` claim | 40 min | approval |

Stage 4 (new prose, CI, cleanup) follows; scoped in PLANS.md.

---

## Awaiting

Approval to proceed to Phase 3, and rulings on the open questions above. Recommended
starting point is Step 2 — it is text-only, reversible, and clears the two defects that
contradict the project's own FreeBSD premise.
