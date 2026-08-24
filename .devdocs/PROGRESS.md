# PROGRESS

Macro progress tracking of completed, superseded, removed, or otherwise archived todos.
Most recent at top.

---

## 2026-08-24 10:00 — Verified against Hurmit, the font the readme documents

USER pointed out Hurmit Nerd Font is installed and that this host is a linuxulator — which
explains `uname -s` reporting Linux while zig targets freebsd. `find` had not surfaced the
font; `fc-list` did. It is at
`/usr/local/share/fonts/nerd-fonts/Hurmit/HurmitNerdFontMono-Regular.otf`.

The readme's exact documented command now runs clean:

```
  cell            7x17 px
  blanks patched  2
  blocks exact    18
  advance fixed   0
  console grid    274x70 at 1920x1200
```

**Three things this settles.**

1. **C5 never affected the documented font.** `advance fixed 0` — Hurmit's bounding box
   already equals its advance. The hypothesis recorded in TODOS C5 ("if Hurmit's bbox
   width happens to equal its advance the workflow would work for that one font, which may
   be why this was never noticed") is confirmed. The C5 fix is a no-op for Hurmit and a
   rescue for everything else.

2. **The docstring's claim is empirically true.** It asserts Hurmit at 11pt "leaves the top
   pixel row of every cell empty, which bands the whole image". Measured on the raw
   otf2bdf output: the two half-blocks cover rows 0-15 of a 17-row cell, and **row 16 is
   never inked by either**. The full block likewise covers rows 0-15. Synthesised versions
   cover 0-17.

3. **C2 fixed a real defect for the documented font, and my first reading of it was
   wrong.** I initially recorded a "1px vertical seam" from the raw quadrant being 3px
   wide. That was incorrect: horizontally the raw glyphs tile fine — left half covers cols
   0-2, right half 3-6, no gap. The defect is purely the missing **top row**. Before C2 the
   10 quadrants kept their rasterised form and so left row 16 empty, while the 5
   halves/full block were already synthesised and correct. The banding was therefore
   *intermittent* — present only on cells that happened to select a quadrant, which is 10
   of the 15 patterns. Irregular banding rather than uniform. Now all 18 fill the cell.

Readme cross-check: `gif_font_aspect` note says "17 / 7 = 2.43 for a 7x17 one" — Hurmit at
11pt measures exactly 7x17, so that guidance is correct as written.

---

## 2026-08-24 09:55 — PLANS Stage 4 complete; F2 CANCELLED on verification

**Completed**
- **E3** — new "Migrating from Ly" section in the readme: the three renames still
  accepted, the two options dropped as having no FreeBSD equivalent, what gets folded
  into what, the type conversions, the eight-colour fallback, and the 16 options now
  ignored outright. Written from `migrator.zig`, not from memory.
- **E6** — new "Other backgrounds" section documenting all eight `animation` values, and
  a line documenting `--config`/`-c`.
- **E4** — `contributing.md` restored, rewritten for this fork: scope (what is out of
  bounds for a FreeBSD-only project), **how to actually test on FreeBSD** — which is what
  the PR template asks for and previously gave no guidance on — the cross-file invariants,
  Zig style, commits, and bug reporting.
- **E5** — `.github/workflows/ci.yml` with two jobs, plus `tools/check_invariants.py`.
- **F1** — `res/pixel_sakura_static.png` removed (543 KB). Verified first: not in
  `install.zig`, no code reference, no config default, referenced only by the readme
  credit, which was rewritten.

**F2 — CANCELLED. The premise was wrong.**
The 13 strings were *not* orphans. `src/main.zig:1223-1224` iterates **every** field of
`Lang` and exposes each as a `$<key>` substitution token in custom keybind names, and
`res/config.ini:485-487` documents this to users in as many words: *"You can see the list
of keys in any locale file"*. Removing them would have broken documented, user-facing
behaviour and deleted a feature. See DECISIONS_LOG D-007.

**Why CI is a FreeBSD VM and not a cross-compile.** `sakura-core/build.zig:29-53` translates
FreeBSD *base system* headers — `security/pam_appl.h`, `login_cap.h`, `sys/kbio.h`,
`sys/consio.h` — which are not part of the libc headers Zig bundles. A Linux runner cannot
supply them without a sysroot, so the build job runs under `vmactions/freebsd-vm`. The
invariant job needs no toolchain and runs on Ubuntu first, so cheap drift is caught before
a VM is spent.

**`tools/check_invariants.py`** encodes the four invariants this audit kept finding broken:
Config.zig ↔ config.ini, Lang.zig ↔ all 25 locales, res/lang ↔ install.zig, and Gif.zig ↔
mkvtfont. It was tested negatively — injecting an undocumented option and deleting a
translation made it fail with the right diagnosis — and it guards against parsing
vacuously, after its own first draft passed a check it should have failed.

**Other-OS sweep (USER instruction).** No other-OS support remains. Every surviving
mention of Linux is an explanation of *why* something was dropped (migration docs, code
comments); `os.tag` appears only in the FreeBSD gate at `build.zig:97`.

**Final verification:** `zig build` OK · `zig build test` OK · `--validate-config` clean ·
all invariants hold · 8/8 fonts build.

**Counts:** 21 defects → 20 complete · 1 cancelled as invalid (F2) · 0 open.

---

## 2026-08-24 09:47 — C5 fixed; PLANS Stage 3 complete

**C5 — fixed, and the originally proposed remedy was wrong**

TODOS C5/Q1 proposed synthesising blocks at the *advance* width. Testing both directions
against `vtfontcvt` refuted that:

| Hypothesis | Result |
| --- | --- |
| Normalise `DWIDTH` to the bounding-box width | **ACCEPTED** — 22234-byte font |
| Shrink `FONTBOUNDINGBOX` to the advance | **FAILED** — *"broken bitmap with BBX 9 10 -2 0"*; glyphs that overhang no longer fit |

So the bounding box *is* the console cell and the existing synthesis width was already
correct. The defect was solely that `DWIDTH` was left disagreeing with it. Fixed by
restating every glyph's advance as the cell width, which also subsumes Q2 (the
blank-patching path) since the normalisation is applied to the whole glyph buffer before
branching. Q3 (hard-fail on mismatch) is now moot — the mismatch is corrected, not fatal —
so the summary reports an `advance fixed` count instead.

Verified: **8 of 8 monospace fonts now build; previously 0 of 6.** In the emitted BDF all
791 glyphs advance by the cell width, all 18 blocks occupy the full cell, and the bitmaps
satisfy the tiling algebra — `U+2598|259D|2596|2597 == U+2588`, upper|lower == full,
left|right == full, U+2598 and U+2597 disjoint, U+2588 inks every pixel of all 15 rows.

**Stage 3 — completed and verified**
- **D1** — the two stale `# default: 0.5` comments removed; `box_position_v` given the
  rationale its sibling already had.
- **D2** — `Config.zig:52-53` doom defaults aligned **to what ships** per USER instruction
  (`0x00FF0000`→`0x009F2707`, `0x00FFFF00`→`0x00C78F17`), resolving TODOS D2/Q1.
- **D3** — `start_cmd` divergence now documented in place.
- **D-readme** — the false "includes the default values" claim replaced with an accurate one.
- **E1** — install table 6 → **14** rows, matching `install.zig`.
- **E2** — `readme.md` clone URL filled in.
- **F3** — `main.zig:194` `"sakura version"` → `"Sakura version"`, matching `:47` and the UI.

**Verification of the whole tree at this point**
- `zig build` — succeeds, binary produced.
- `zig build test` — passes.
- `./zig-out/bin/sakura --version` → `Sakura version 1.0.0` (capitalisation now consistent).
- `./zig-out/bin/sakura --validate-config res/config.ini` → **no errors detected**, which
  exercises every config edit made in Stages 1 and 3.
- Defaults parity: 94/94 keys both directions; the only shipped-value/default divergence
  left is `start_cmd`, now documented.

**Counts:** 21 defects → 5 open · 16 complete.
Remaining: E3, E4, E5, E6 (new documentation) and F1, F2 (the removals, deferred to last
per USER instruction).

---

## 2026-08-24 09:17 — PLANS Stage 2 complete; new defect C5 raised

**Completed and verified**
- **C2** — `tools/mkvtfont.py` now synthesises **18** cell-exact glyphs, up from 8. The ten
  quadrants U+2596-U+259F, which carry ten of the fifteen patterns the wallpaper is built
  from, were previously left to the rasteriser. Implemented by deriving every predicate
  from one 2×2 mask table mirroring `Gif.zig:45-60`, rather than fifteen hand-written
  lambdas. Verified: BLOCKS set == Gif.zig's glyph set exactly (space excluded, it needs
  no synthesis); all 8 previously-synthesised predicates **byte-identical** across five
  cell sizes (7×17, 8×16, 12×24, 16×32, 11×23); the four single quadrants tile the cell
  exactly once; U+2588 == their union; U+2598 and U+259F are complements. End-to-end run
  against DejaVu Sans Mono emits 18/18 block glyphs into the BDF.
- **C1** — docstring rewritten. It described a renderer that used only U+2580 plus the cell
  background; it now describes the quadrant-plus-shade matcher actually in `Gif.zig`, and
  states the tables must stay in step.
- **C3** — `readme.md:251-253` font requirement corrected. Was U+2500-U+2518, U+2580,
  U+2588, U+2593. Now names the halves and full block, the quadrants U+2596-U+259F and the
  three shades U+2591-U+2593, so a font that passes the documented check can actually
  render the wallpaper.

**Files modified:** `tools/mkvtfont.py`, `readme.md`.

**New defect discovered — C5, NOT fixed, awaiting approval per Directive 1.**
Running the tool end-to-end (both `otf2bdf` and `vtfontcvt` are present on this machine)
showed it cannot produce a font from any of six monospace fonts tested. It synthesises
blocks at the **FONTBOUNDINGBOX** width but the console tiles at the **advance** width.
Pre-existing — the failure is at the space glyph, before any block, and is identical with
the old 8-glyph table. See TODOS C5 and DECISIONS_LOG D-006.

**Counts:** 20 defects → 11 open (+1 new = 12) · 9 complete · 0 in progress.

---

## 2026-08-24 09:08 — PLANS Stage 1 complete

**Completed and verified**
- **A1** — `res/example.dur` replaced. The Ly / Fairy Glade logo is gone; the file now
  carries a five-petal sakura blossom (bright-magenta petals, magenta edges, yellow
  stamen, white ground) across 3 frames with drifting petals. Regenerated from a
  parametric rose curve rather than hand-drawn. Verified against every rule in
  `DurFile.zig:validate()` — 22/22 checks pass. Uses only space + U+2588/2593/2592/2591,
  all of which the readme already requires of the console font. Container's stored
  filename is now `sakura-blossom.dur` (was `fairy-glade-logo3.dur`). 2061 → 1112 bytes.
- **A2** — `res/setup.sh:11` "the LICENSE file" → "license.md". The
  `Copyright (C) 2024 The Fairy Glade` line above it is **retained**: it is upstream
  authorship attribution, not branding, and is the only `fairy` string left in `res/`.
- **B1** — `res/config.ini:1-2` no longer claims 24-bit true colour. Rewritten to state
  the 0xSSRRGGBB format and that values are mapped onto the vt(4) console's sixteen
  colours, agreeing with `:257-260` and `readme.md:180-183`.
- **B2** — `res/config.ini:444,468` no longer suggest `$PREFIX_DIRECTORY/local/share/…`,
  which expanded to `/usr/local/local/share/…`. Both now point at a valid second tree.
- **C4** — `err_gif` added to all 24 remaining locales, each translated in that file's own
  register rather than left as English. Parity re-verified: **all 25 locales carry all 82
  `Lang.zig` keys**, exactly one `err_gif` per file.

**Files modified:** `res/config.ini`, `res/example.dur`, `res/setup.sh`, and all 24
non-English `res/lang/*.ini`.

**Superseded:** TODOS A1/Q1-Q2 — resolved by USER instruction ("replace the ly logo art"),
so the nullable-`dur_file_path` option was not taken and no feature was removed.

**Counts:** 20 defects → 14 open · 6 complete · 0 in progress.

---

## 2026-08-24 08:48 — `.devdocs/` initialised

**Completed**
- Phase 1.1 — read all existing project documentation and code.
- Phase 1.2 — generated `.devdocs/` and populated the full file set (BRIEFING, PROGRESS,
  SESSION_HANDOFF, DECISIONS_LOG, TODOS, PLANS, BLUEPRINT).
- Phase 1.3 — created `BRIEFING.md`.
- D-001 — post-rebrand documentation audit. 20 defects identified and evidenced.
- D-004 — Directive 2 FOSS compliance verified across all 10 dependencies. Compliant.
- BLUEPRINT §1-§7 — architecture, dependency register, platform interfaces, install
  topology, wallpaper rendering contract, configuration contract, all documented from
  source rather than from prose.

**Archived / no action**
- Name-level rebrand verification: 0 defects. Recorded under TODOS "VERIFIED CLEAN" so
  future sessions do not repeat it.
- D-004 — WTFPL vs Directive 2. Resolved, no action.

**Open, blocking**
- Phase 1.4 halt in effect. Awaiting USER approval before any product-code change.
- D-002, D-003, D-005 — three governance ambiguities tabled for USER ruling.
- TODOS A1/Q1-Q2, D2/Q1, F1/Q1, F2/Q1 — four item-level questions tabled.

**Implementation registry:** empty. Nothing has moved from TODOS to BLUEPRINT yet.

**Counts:** 20 defects open · 0 in progress · 0 complete · 3 blocked on Directive 3 or
asset decisions.
