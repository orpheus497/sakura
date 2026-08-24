# SESSION HANDOFF

Session-to-session continuity and task persistence. Reverse-chronological — newest first.

---

## 2026-08-24 10:17 — Session 001 (continued) — review pass

**Objective.** Act on a set of review findings against the committed work.

**Accomplishments**
1. **CI hardening.** Both actions pinned to verified full-length commit SHAs resolved from
   the upstream repos — `actions/checkout` `11d5960a…` (v4.4.0) and `vmactions/freebsd-vm`
   `d0518f91…` (v1.5.4). Added `needs: invariants` so the FreeBSD VM only starts once the
   cheap text checks pass, which the workflow comment already claimed but did not enforce.
2. **Two documentation errors corrected, both verified against source first.**
   `--config` takes a *directory*, not a file — `main.zig:185-230` joins it with
   `config.ini`, `lang/` and `save.ini`. And `box_position_h`/`_v` are measured from the
   **top-left**, not "the bottom"/"the end of the screen": `main.zig:2288-2291` feeds them
   into `.addX`/`.addY` from `START_POSITION`, so larger values move the box right and down.
3. **`contributing.md`** configuration rule relaxed to match reality: values must match
   *unless* `config.ini` documents a deliberate shipped override, which `start_cmd` is.
4. **`check_invariants.py`** — added the mandated `Function purpose:` headers to `read`,
   `zig_fields` and `ini_keys`, and moved the existing one, which sat above `FAILED = []`
   instead of above the `check` function it described.
5. **Trackers reconciled** with the executed state: BLUEPRINT audit statements moved to
   past tense with a new §8 implementation registry, BRIEFING rewritten, PLANS archived,
   D-006 marked RESOLVED, TODOS backlog cleared.

**Files modified:** 5 — `.github/workflows/ci.yml`, `readme.md`, `res/config.ini`,
`contributing.md`, `tools/check_invariants.py` — plus the six `.devdocs/` trackers.
`.coderabbit.yaml` is untracked and was not authored here; left alone.

**Correction to the previous entry.** It stated "nothing has been committed; all 37 paths
are working-tree changes". That is no longer true: the work was committed as `e510739`
(static PNG removal) and `0f668ff` (everything else). `AGENTS.md` and `.devdocs/` are now
tracked, which settles the tracking half of D-002 by fact. The *location* question — process
documentation in the product root, against Directive 4 — remains open.

**Verification:** `check_invariants.py` passes; `sakura --validate-config res/config.ini`
clean after the comment edits; workflow pins re-resolved against the upstream repos.

**Blockers.** None. D-002, D-003, D-005 still await a USER ruling.

**Next steps.**
1. Rule on D-002, D-003, D-005.
2. Review and commit the 5 changed files.
3. Push so the CI workflow actually runs — it has been validated locally but never executed
   on GitHub.

---

## 2026-08-24 10:00 — Session 001 (continued) — Hurmit verification

**Objective.** Close the one caveat left open at Phase 4: the font toolchain had been
verified against DejaVu and Noto but not against Hurmit Nerd Font Mono, the font
`readme.md` documents. USER pointed out it was installed and that this host is a
linuxulator — which explains `uname -s` reporting Linux while zig targets freebsd. `find`
had not surfaced it; `fc-list` did.

**Findings**
1. The readme's exact command runs clean: cell 7x17, 18 blocks exact, 2 blanks patched,
   console grid 274x70 at 1920x1200.
2. **C5 never affected Hurmit** — `advance fixed 0`, its bounding box already equals its
   advance. This confirms the hypothesis recorded when C5 was raised: the documented font
   was the one font the bug never broke, which is why it went unnoticed.
3. **The docstring's claim is empirically true.** Raw `otf2bdf` output has the two halves
   covering rows 0-15 of a 17-row cell; **row 16 is never inked by either**.
4. **Corrected my own mis-reading.** I had recorded a "1px vertical seam". Wrong —
   horizontally the raw glyphs tile fine (left half cols 0-2, right half 3-6). The defect
   is purely the missing top row. Before C2 the 10 quadrants kept their rasterised form and
   left row 16 empty while the 5 halves/full block were already correct, so the banding was
   *intermittent* — on the 10 of 15 patterns that use a quadrant.

**Files modified:** none. Verification only; trackers updated at PROGRESS 10:00.

**Blockers.** None.

---

## 2026-08-24 09:55 — Session 001 (continued) — Phase 3 executed, Phase 4 reached

**Objective.** USER approved execution, lifted the Directive 3 gate on removals with the
condition that removals come last and only after verifying they were still unneeded, and
asked for a report at each phase completion.

**Accomplishments.** All four PLANS stages executed. 20 of 21 defects fixed, 1 cancelled.

| Stage | Items | Outcome |
| --- | --- | --- |
| 1 | A1, A2, B1, B2, C4 | Ly logo replaced; config's false 24-bit claim and broken paths fixed; `err_gif` translated ×24 |
| 2 | C1, C2, C3 | Font tool 8 → 18 cell-exact glyphs; docstring and readme corrected |
| — | C5 | Found during Stage 2 verification, approved, fixed |
| 3 | D1, D2, D3, D-readme, E1, E2, F3 | Accuracy pass; defaults reconciled |
| 4 | E3, E4, E5, E6, F1 | New docs, contributing guide, CI + invariant checker, dead asset removed |
| 4 | F2 | **Cancelled** — verification showed the finding was invalid |

**Three of my own conclusions were overturned by testing, which is the main lesson here:**

1. **C5's proposed fix was backwards.** I proposed synthesising at the advance width;
   testing showed the bounding box is the console cell and only `DWIDTH` was wrong.
   Shrinking the box fails outright. (D-006)
2. **F2 was an invalid finding.** The 13 "orphan" strings are reachable through
   compile-time reflection and are documented user-facing API. A static grep cannot
   establish deadness for a struct that is reflected over. (D-007)
3. **The invariant checker's first draft passed a check it should have failed** — a
   file-wide regex matched `config.ini` outside the languages array. It now scopes the
   search and refuses to pass vacuously on empty input.

In all three cases the static reading was plausible and wrong. Verification was not a
formality.

**Files modified: 42 individual files** — 31 changed, 1 deleted, 10 added.

- *Changed (31):* `readme.md`, `res/config.ini`, `res/example.dur`, `res/setup.sh`,
  24 × `res/lang/*.ini`, `src/config/Config.zig`, `src/main.zig`, `tools/mkvtfont.py`,
  `.gitignore`.
- *Deleted (1):* `res/pixel_sakura_static.png`.
- *Added (10):* `contributing.md`, `tools/check_invariants.py`,
  `.github/workflows/ci.yml`, and the seven `.devdocs/` trackers — `BLUEPRINT.md`,
  `BRIEFING.md`, `DECISIONS_LOG.md`, `PLANS.md`, `PROGRESS.md`, `SESSION_HANDOFF.md`,
  `TODOS.md`.

Counted as files, not directories; an earlier draft counted `.devdocs/` as a single entry
and so understated the total.

**Verification performed:** `zig build`, `zig build test`, `sakura --version`,
`sakura --validate-config res/config.ini`, `tools/check_invariants.py` (positive and
negative), `mkvtfont.py` end-to-end across 8 fonts, and a structural audit of the
regenerated `res/example.dur` against `DurFile.zig:validate()`.

**Blockers.** None for the approved work. Three governance questions still need a USER
ruling: D-002, D-003, D-005.

**Next steps.**
1. Rule on D-002, D-003, D-005.
2. Review and commit. *(Superseded: committed as `e510739` and `0f668ff` — see the 10:17
   entry. `.devdocs/` and `AGENTS.md` are now tracked.)*
3. `contributing.md` deliberately omits the upstream AI-usage policy rather than
   inheriting or dropping it silently — that is an editorial call for the owner.
4. Optional follow-up: verify against Hurmit. *(Done — see the 10:00 entry.)*

---

## 2026-08-24 08:48 — Session 001

**Objective.** USER: *"make sure all documentation and details have been completely
updated to the new branding and focus - analyse and report"*, then *"be more comprehensive
and detailed"*, then *"proceed and make sure you stick to the agents.md"*.

**Accomplishments**
1. Completed a five-method post-rebrand audit (DECISIONS_LOG D-001). 20 defects found and
   evidenced to file:line.
2. Discovered `AGENTS.md` on the third instruction and switched to its operational cycle.
   `.devdocs/` was absent → Phase 1 Initialization triggered.
3. Created and populated `.devdocs/` — 7 files.
4. Verified Directive 2 FOSS compliance across all 10 dependencies. All MIT/BSD.
5. Halted per Phase 1.4 without modifying any product file.

**Files modified**
- Created: `.devdocs/BRIEFING.md`, `PROGRESS.md`, `SESSION_HANDOFF.md`,
  `DECISIONS_LOG.md`, `TODOS.md`, `PLANS.md`, `BLUEPRINT.md`.
- **Product files modified: none.** Working tree outside `.devdocs/` is untouched.

**Decisions taken**
- D-001 audit complete; D-004 FOSS compliance resolved clean.
- D-002, D-003, D-005 tabled as governance ambiguities rather than resolved unilaterally.
- Directive 3 (Total Feature Retention) applied to gate F1, F2 and one A1 option — these
  are removals and will not proceed without explicit instruction.

**Process note.** The first audit pass checked names only and missed value-level and
behavioural drift. The second pass — comparing *default values*, and comparing emitted
glyphs against the tool documented to produce them — is what surfaced B1, B2, C2, D1 and
D2. Name-level greps are not sufficient for a rebrand audit of this kind; record this for
future sessions.

**Blockers**
- Phase 1.4 halt: awaiting USER approval to begin Stage 1 of PLANS.md.
- 3 governance questions (D-002, D-003, D-005) and 4 item questions (TODOS A1/Q1-Q2,
  D2/Q1, F1/Q1, F2/Q1) outstanding.

**Next steps for the following session**
1. Obtain rulings on the 7 open questions.
2. On approval, execute PLANS Stage 1 (A1, B1, B2, C4) — announce, justify, execute,
   update trackers per Phase 3.
3. Then Stage 2 (C1–C3), the only behaviour-changing work; requires a real-console
   verification of the wallpaper after the font rebuild.
