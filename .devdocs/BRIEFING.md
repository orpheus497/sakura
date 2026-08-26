# BRIEFING — Sakura

Current project status and phase. Last updated: 2026-08-27 07:52.

---

## Current Phase

**Phase 4 — Session End. Session 003 (ecosystem branding) complete.**

The 2026-08-27 session established the framing the documentation had never carried: Sakura
is the **login layer of the Sakura desktop**, a three-component Wayland desktop environment
for FreeBSD, alongside `hikari-sakura` (compositor) and `Sofi` (shell). The naming is a
lineage rooted here — hikari-sakura takes its second name from this display manager, Sofi
its leading S. Recorded as **D-010**; architecture in BLUEPRINT §1.1.

Before this pass, `hikari` and `sofi` appeared nowhere in the repository. `readme.md` now
leads with the desktop, carries a §*The Sakura desktop* (component table, naming lineage,
runtime hand-off) and a §*Running hikari-sakura* under Sessions, and credits both siblings'
ancestry and licences. Every integration claim was verified against the sibling working
copies at `/home/orpheus497/Projects/{hikari-sakura,sofi}` — evidence table in D-010.

Scope was `readme.md` only, by USER ruling. `contributing.md`, the `.github/` templates and
`res/` were offered and declined; they are parked in PLANS.md as a pending item, with issue
routing flagged as the one that will matter first. No code changed.

---

## Prior Phase — remediation

**All four stages complete and verified.**

20 of 21 defects fixed; 1 (F2) cancelled on verification as an invalid finding. Tree
state: `zig build` OK · `zig build test` OK · `--validate-config` clean · all invariants
hold · 8/8 fonts build.

Nothing is in progress. A v1 readiness pass on 2026-08-25 re-verified the branding and the
user-facing documentation and closed two of the three governance questions: D-002 (keep
`AGENTS.md` and `.devdocs/` tracked) and D-003 (drop the pango/cairo FOSS exception). Only
D-005 (retroactive-commenting prohibition vs the documentation standard) remains open. That
pass also recorded D-008, a release-mechanics constraint that must be honoured when tagging
v1.0.0. The USER then relicensed the project from WTFPL to BSD 2-Clause (D-009), which
raises one open provenance question against `res/setup.sh`.

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
wallpaper. It is also the login layer of the three-component **Sakura desktop** — see
BLUEPRINT §1.1 for the ecosystem position and the integration contract, and §2 onward for
internal architecture.

**One structural coupling to guard (BLUEPRINT §1.1).** hikari-sakura's session entry is
discovered purely by convention: it installs `hikari.desktop` into
`${PREFIX}/share/wayland-sessions`, which is Sakura's default `waylandsessions`. No Sakura
source file contains the string "hikari". Changing that default, or the desktop-entry
crawler, removes the compositor from the session list **silently**.

**Documentation health after remediation: all audited defects closed.**

| Area | State |
| --- | --- |
| Name-level rebrand | Clean — 0 defects |
| Ecosystem branding | Documented in `readme.md` (D-010); three surfaces deferred to PLANS |
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

None blocking work. One governance question remains for a USER ruling:

1. **D-005** — the mandated comment prefixes versus the prohibition on adding comments
   retroactively. Applied as: bring existing comments into line when already editing them;
   do not retrofit headers onto untouched files.

Closed on 2026-08-25: **D-002** (keep `AGENTS.md` at the root and `.devdocs/` committed,
both public) and **D-003** (drop the pango/cairo exception; Directive 2 is now an
unqualified MIT/BSD rule).

Not a blocker but a release gate: **D-008** — tagging `v1.0.0` without bumping
`sakura_version` breaks `zig build` on the following commit.

Open but not blocking: **D-009 Q1** — `res/setup.sh` derives from kde-workspace
(`kdm/kfrontend/genkdmconf.c`, GPL-2.0-or-later) via a WTFPL relabel made upstream. The
file is carved out of the BSD relicence pending a provenance check.

---

## Recent Architectural Decisions

- **D-010** — Sakura documented as the login layer of the Sakura desktop (Sakura ·
  hikari-sakura · Sofi), with the naming lineage recorded. Integration is by freedesktop
  convention only; independence from both siblings is stated explicitly in the readme so the
  framing does not read as a new dependency. One question open (Q1): the lineage is
  documented in one direction only, as neither sibling repository mentions Sakura.
- **D-001** — Post-rebrand audit complete. Two structural insights recorded: `install.zig`
  substitutes prefix tokens inside *comments* as well as values (root cause of B2, and a
  standing hazard for any future prefix change); and the wallpaper glyph set is duplicated
  across four locations, three of which drifted.
- **D-004** — Directive 2 FOSS compliance verified. All ten dependencies MIT or BSD; zero
  copyleft, zero proprietary. Superseded in part by D-009: the project's own licence is no
  longer WTFPL.
- **D-009** — Project relicensed from WTFPL to BSD 2-Clause, with `res/setup.sh` carved out
  and an open provenance question recorded against it.
- **D-008** — `build.zig:getVersionStr` hard-fails the build when `git describe` finds a
  tagged ancestor that is not strictly older than the in-tree `sakura_version`. The tree
  version must therefore always lead the newest tag.

---

## Next 3–5 Concrete Execution Steps

| # | Step | Est. | Gate |
| --- | --- | --- | --- |
| 1 | Review and commit the working tree: `readme.md` from this pass, plus the still-uncommitted 10:17 review and 2026-08-25 v1 changes | 15 min | — |
| 2 | Rule on D-005, the one remaining governance question | 10 min, USER | — |
| 3 | Add issue routing to `.github/ISSUE_TEMPLATE/*.yml` — PLANS item 1, the declined surface that matters first once the desktop has users | 15 min | — |
| 4 | Confirm the CI workflow actually runs on GitHub — it has never executed, only been validated locally | 15 min | push |
| 5 | Tag `v1.0.0`, then bump `sakura_version` and `build.zig.zon` to 1.0.1 per D-008 | 10 min | tag |
| 6 | Cross-repo reciprocity (D-010 Q1) — link back to Sakura from hikari-sakura and Sofi; batch with v1.0.0 coordination | 20 min | other repos |
| 7 | Optional: extend `check_invariants.py` to the cell-geometry invariant recorded in BLUEPRINT §6 | 30 min | — |

---

## Awaiting

A ruling on D-005, and a review of the uncommitted changes — which now include this
session's `readme.md` rewrite alongside the earlier unreviewed passes. Nothing is blocked on
either. The v1.0.0 tag is the USER's to cut; see D-008 for the two-step sequence it
requires, and D-010 Q1 for the cross-repository linking worth doing in the same window.
