# BRIEFING — Sakura

Current project status and phase. Last updated: 2026-08-29 09:39.

> **To the next session: there are no open questions.** Six were closed on 2026-08-29
> (D-012) after being re-asked across multiple sessions because they were left labelled
> `OPEN` in this file and in DECISIONS_LOG after having been answered. Report outstanding
> **work**; do not resurface settled decisions as blockers. The host is FreeBSD under the
> linuxulator (BLUEPRINT §0) — verify platform facts here rather than deferring them.

---

## Current Phase

**Phase 3 complete → Phase 4. Session 005 — the v1 readiness plan is executed in full.**

All four parts done, **23 of 23 backlog items closed**, active list empty. Nothing is
committed; review and commit is USER's call.

**The goal was `pkg install sakura`, and USER's ruling on how: a normal package.** The port
fetches its dependencies as ordinary distfiles via `USES=zig` and `ZIG_TUPLE` — no vendored
blob. `vendor.tar.zst` is *not* tracked, reversing D-011 #3. See **D-013**.

| Part | Result |
| --- | --- |
| 1 — packaging blocker | `build.zig.zon` `.paths` fixed. The release copy builds |
| 2 — the port | `ports/` — `Makefile`, `pkg-descr`, `pkg-plist`, `pkg-message` |
| 3 — documentation | readme covers **94/94** options; 11 new sections |
| 4 — three wrong things | All corrected |

**Two places reality corrected the plan, both recorded in D-013:**

1. **`.paths` does not honour `.gitignore`.** Listing `sakura-ui`/`sakura-core` as
   directories, as the plan said, swept `.zig-cache/` and the vendored `zig-pkg/` trees
   into the package — **1037 files for ~30 files of source**. Naming the source subpaths
   gives **89 files, zero leakage**. This recurs with any future path dependency.
2. **`install.zig:117` hardcodes `zig-out/bin/sakura`.** `USES=zig` passes
   `--prefix ${PREFIX}` by default, which would write outside the stage directory *and*
   break that read. The port supplies its own `do-install`.

**The finding users will feel most (V14):** every stock FreeBSD console font already
carries all 18 wallpaper glyphs, so **no font build is needed**. The readme had presented a
Python toolchain as setup for a feature that works out of the box.

**Standing constraint, honoured throughout: nothing is deleted.** No tag was created;
`sakura_version` and `build.zig.zon`'s `.version` are untouched.

---

## Prior Phase — Session 003, ecosystem branding

**Complete.**

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
`AGENTS.md` and `.devdocs/` tracked) and D-003 (drop the pango/cairo FOSS exception). That
pass also recorded D-008, a release-mechanics constraint that must be honoured when tagging
v1.0.0, and the USER relicensed the project from WTFPL to BSD 2-Clause (D-009).

*(This paragraph previously ended by naming D-005 and a D-009 provenance question as open.
Both were closed on 2026-08-29 — D-012. Nothing here is outstanding.)*

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
| Invariant drift | Enforced by `tools/check_invariants.py`; all four families hold |

**v1 readiness after execution (D-013): ready, pending one build test.**

| Area | State |
| --- | --- |
| Zig package integrity | **Fixed** — 89 files, both path dependencies, no cache or vendor leakage |
| FreeBSD port | **Exists** — `ports/` with `Makefile`, `pkg-descr`, `pkg-plist`, `pkg-message` |
| Build-option documentation | **Complete** — all nine `-D` options in a readme table |
| Dependency specification | **Split** build / runtime / session / optional; `pkgconf` confirmed |
| Dependency fetching | **Distfiles** via `ZIG_TUPLE`, nine entries incl. LuaJIT and the second `translate_c` |
| Settings documented to users | **94 of 94** — 75 named verbatim, 19 by prefix row, 0 uncovered |
| Autologin, vi keys, corner widgets, custom binds, appearance, language, clock, sessions | **Documented** |
| Command-line reference | **Present** — all four options in one table |
| Troubleshooting guidance | **Present**, including single-user recovery from a broken `/etc/ttys` |
| Known-wrong text | **Corrected** — `config.ini` autologin comment, `main.zig` `--config` help, vendor script header |
| Console font | **Corrected** — leads with "no font build needed" plus the stock-font table |
| Build verification | **Outstanding** — needs a native FreeBSD userland (BLUEPRINT §0) |
| `distinfo` | **Absent by design** — `make makesum` generates it, and that needs the `v1.0.0` tag |

---

## Progress

- Audit (D-001, post-rebrand): **100%**
- `.devdocs/` initialization: **100%** (Phase 1 complete)
- Remediation: **100%** — 20 of 21 defects fixed, 1 (F2) cancelled as an invalid finding
- Ecosystem branding (D-010): **100%** for `readme.md`; 3 surfaces parked in PLANS
- **v1 audit (D-011): 100%** — 19 items scoped into TODOS Groups P and V
- **v1 execution: 100%** — all four parts done, 23 of 23 items closed (D-013)

---

## Current Blockers

**None. There are zero open questions and nothing awaiting an answer.**

All six items that previous briefings carried here were closed on 2026-08-29 — see
DECISIONS_LOG **D-012**, which also records why they kept recurring and the convention that
stops it. **Do not re-table any of them, and do not reproduce this list as "open" in a
future briefing:**

| Was listed as open | Actual status |
| --- | --- |
| D-005 — retroactive commenting | `AGENTS.md` states the rule outright. Never was a question |
| D-009 Q1 — `res/setup.sh` provenance | The `license.md` carve-out **is** the disposition, taken at the time |
| D-010 Q1 — cross-repo linking | Closed by USER: the siblings link each other; other repos are not this repo's concern |
| D-011 Q1 — `tools/` working tree | Closed by fact: `git diff -- tools/` is empty, both files present |
| P6 Q1 — is `pkgconf` required | **Yes**, verified: `pkgconf --modversion xcb` → `1.17.0` |
| Stock font glyph coverage | **Complete**, verified: all 5 stock vt fonts carry all 18 glyphs |

**The host is FreeBSD 15.1-RELEASE under the linuxulator** (BLUEPRINT §0). `uname -s` says
`Linux` and has misled prior sessions into deferring platform checks. Run the check instead.

**D-008 is recorded, not scheduled.** USER ruled tags and versions out of scope entirely
(D-011 #7): no tag is created, and neither `sakura_version` in `build.zig:22` nor
`.version` in `build.zig.zon:3` is touched by any part of the v1 plan. D-008 remains on
file as a constraint for whoever eventually cuts a release. No tag exists today —
`git describe` finds nothing, so `sakura --version` reports `1.0.0` verbatim.

Closed earlier, on 2026-08-25: **D-002** (keep `AGENTS.md` at the root and `.devdocs/`
committed, both public) and **D-003** (drop the pango/cairo exception; Directive 2 is now an
unqualified MIT/BSD rule).

---

## Recent Architectural Decisions

- **D-011** — v1 readiness. Goal is `pkg install sakura`; the port is created in this
  repository. Nine rulings taken, the overriding one being that **nothing is deleted** and
  no tag or version is touched. Records the Python provenance audit USER asked for
  (`normalize_lang_files.py` upstream · `mkvtfont.py` project, added with the wallpaper ·
  `check_invariants.py` agent-created), with **no disposition taken on any of the three**.
  Also records a prior-session failure: TODOS E4 classified a deliberate USER deletion of
  `contributing.md` as a defect and reversed it. New rule — check whether a file's removal
  was intentional before recording its absence as a finding.
- **BLUEPRINT §9** — Distribution Topology added. Separates the three distinct meanings of
  "package" (Zig package · installed tree · FreeBSD package), records the `.paths` invariant
  as standing rather than one-off, and documents `-Ddest_directory` as the staging
  mechanism a port binds to.
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

From PLANS.md *PENDING — v1 Readiness Plan*. Steps 1–4 are the plan; 5–7 remain from
earlier passes.

Parts 1–4 are **done**. What remains:

| # | Step | Est. | Gate |
| --- | --- | --- | --- |
| 1 | **Review and commit** the 8 modified product files and the 4 new `ports/` files | USER | — |
| 2 | **Build-test `ports/`** on a native FreeBSD userland; confirm the staged tree matches `pkg-plist` entry for entry | 30 min | a FreeBSD userland |
| 3 | `make makesum` to generate `distinfo` | 5 min | needs the `v1.0.0` tag to exist |
| 4 | Optional — issue routing in `.github/ISSUE_TEMPLATE/*.yml`; matters once the desktop has users | 15 min | — |

Step 3 is a **USER decision, not a task**: tags are out of scope per D-011 #7, and the
port cannot fetch until `v1.0.0` exists. D-008 records the sequence for cutting it.

---

## Awaiting

**Review and commit.** The v1 work is done and verified as far as this host allows;
nothing is committed.

One thing genuinely needs USER: **whether to cut the `v1.0.0` tag.** The port's
`USE_GITHUB` fetch and `make makesum` both depend on it, and tags were ruled out of scope
in D-011 #7 — so the port is written ready for it and stops there. D-008 records the exact
sequence (tag at the release commit, then immediately bump `build.zig:22` **and**
`build.zig.zon:3` together).

No question is open, no ruling is pending, and no fact awaits a different host.
