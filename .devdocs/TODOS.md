# TODOS

Last updated: 2026-08-24 08:48

Source: USER/DEVELOPER request 2026-08-24 — *"make sure all documentation and details have
been completely updated to the new branding and focus"*, followed by *"be more
comprehensive and detailed"*.

Findings below come from the audit recorded in DECISIONS_LOG D-001. Each carries the
evidence that established it. Questions tabled under each item are for USER resolution
before that item is scoped into PLANS.md.

---

## ACTIVE LIST

*(empty — all approved work complete)*

---

## COMPLETED — Stage 4 (2026-08-24 09:55)

- **E3** ✅ "Migrating from Ly" section written from `migrator.zig`.
- **E6** ✅ "Other backgrounds" section — all eight `animation` values; `-c/--config` documented.
- **E4** ✅ `contributing.md` restored and rewritten for this fork, including how to
  actually test on FreeBSD and the cross-file invariants.
- **E5** ✅ `.github/workflows/ci.yml` (invariants on Ubuntu, build+test in a FreeBSD VM)
  and `tools/check_invariants.py`, negative-tested.
- **F1** ✅ `res/pixel_sakura_static.png` removed after verifying it was unreferenced;
  readme credit rewritten.
- **F2** ❌ **CANCELLED — the premise was wrong.** The 13 strings are reachable via
  compile-time reflection at `main.zig:1223-1224` and documented at `config.ini:485-487`.
  Nothing removed. See DECISIONS_LOG D-007.

---

## COMPLETED — C5 + Stage 3 (2026-08-24 09:47)

- **C5** ✅ Fixed. Note the proposed remedy in Q1 below was **wrong** and was refuted by
  testing — see PROGRESS 09:47 and DECISIONS_LOG D-006. The bounding box is the console
  cell; only `DWIDTH` was wrong. 8/8 fonts now build (was 0/6). Q2 subsumed; Q3 moot.
- **D1** ✅ Stale `# default: 0.5` comments gone; `box_position_v` rationale added.
- **D2** ✅ `Config.zig` doom defaults aligned to the shipped palette (USER: "align to what
  ships"). Q1 resolved.
- **D3** ✅ `start_cmd` divergence documented.
- **D-readme** ✅ "includes the default values" claim corrected.
- **E1** ✅ Install table 6 → 14 rows.
- **E2** ✅ Clone URL filled in.
- **F3** ✅ CLI version string capitalisation matched to the UI.

Whole-tree verification at this point: `zig build` OK, `zig build test` OK,
`--version` → `Sakura version 1.0.0`, `--validate-config res/config.ini` → no errors.

---

## RESOLVED — C5 (kept for the record)

**C5. `tools/mkvtfont.py` synthesises block glyphs at the wrong width, and the documented
font-building workflow fails outright.**

The script writes synthesised glyphs as `BBX <bw> <bh> 0 <byo>` where `bw`/`bh` come from
the BDF's `FONTBOUNDINGBOX` (`mkvtfont.py:89`, `:125`). But `FONTBOUNDINGBOX` is the union
of every glyph's extents — accents, descenders, box-drawing overhang — whereas the console
tiles cells at the **advance width**, which is what `DWIDTH` carries. The two are rarely
equal.

Two consequences:
1. `vtfontcvt` rejects the whole file: *"bitmap with unsupported DWIDTH 7 0 (not 10 or
   20)"*. So the workflow in `readme.md` "Console font" produces nothing.
2. Were it accepted, every synthesised block would be drawn at the bounding-box width
   inside a narrower cell — overrunning its neighbour. That is the same tiling failure the
   script exists to prevent, in a different form.

Measured at `-p 12` across every monospace font available on this machine:

| Font | bbox width | DWIDTH | Result |
| --- | --- | --- | --- |
| DejaVuSansMono | 10 | 7 | blocks 10px in a 7px cell |
| NotoSansMono-Thin | 20 | 7 | blocks 20px in a 7px cell |
| NotoSansMono-CondensedThin | 19 | 6 | blocks 19px in a 6px cell |
| NotoSansMono-ExtraCondensedBlack | 19 | 6 | blocks 19px in a 6px cell |
| NotoSansMono-CondensedBlack | 20 | 6 | blocks 20px in a 6px cell |
| NotoSansMono-ExtraCondensed | 18 | 6 | blocks 18px in a 6px cell |

Six of six mismatch. This is the normal case, not an edge case.

**Pre-existing, not introduced by C2.** The rejection is raised at the *space* glyph (BDF
line 33), before any block glyph, and occurs identically with the old 8-entry table. C2
neither caused nor worsened it.

**Not verifiable against the documented font.** `readme.md` uses Hurmit Nerd Font Mono,
which is not installed here. If Hurmit's bbox width happens to equal its advance the
workflow would work for that one font, which may be why this was never noticed.

- Q1: Approve fixing it? Proposed: synthesise at the advance width and emit
  `BBX <dwidth> <bh> 0 <byo>`, reading `DWIDTH` per glyph instead of using `bw`.
- Q2: The blank-patching path (`:136`) has the same inconsistency — it writes `BBX 1 1 0 0`
  while leaving the original `DWIDTH`. Include it in the same fix?
- Q3: Should the tool hard-fail with a clear message when bbox width != DWIDTH, rather
  than letting `vtfontcvt` produce a cryptic line-number error?

---

## COMPLETED — Stage 2 (2026-08-24 09:17)

- **C1** ✅ Docstring rewritten for the quadrant-plus-shade renderer.
- **C2** ✅ 8 → 18 cell-exact glyphs; the ten quadrants U+2596-U+259F now synthesised.
  All 8 prior predicates byte-identical across 5 cell sizes; partition and complement
  invariants verified; 18/18 present in an end-to-end BDF.
- **C3** ✅ `readme.md:251-253` font requirement now matches what `Gif.zig` actually draws.

---

## COMPLETED — Stage 1 (2026-08-24 09:08)

- **A1** ✅ Ly logo replaced with a five-petal sakura blossom. 22/22 `DurFile.zig`
  validation checks pass. Stored gzip filename `fairy-glade-logo3.dur` →
  `sakura-blossom.dur`. Q1/Q2 resolved by USER: replace, do not remove.
- **A2** ✅ `res/setup.sh:11` → `license.md`. Fairy Glade *copyright* line retained as
  required attribution — it is the only `fairy` string remaining in `res/`.
- **B1** ✅ `res/config.ini:1-2` 24-bit claim replaced with the vt(4) sixteen-colour reality.
- **B2** ✅ `res/config.ini:444,468` no longer expand to `/usr/local/local/share/…`.
- **C4** ✅ `err_gif` translated into all 24 remaining locales. Parity verified 82/82 × 25.

---

## BACKLOG

*(Group C — C1, C2, C3, C4 all completed; see COMPLETED sections above. C5 raised.)*

### Group D — Defaults documented wrong

`readme.md:157` claims `config.ini` "is fully commented and includes the default values."
Three items falsify it.

**D1. `res/config.ini:105-112` — stale `# default: 0.5` under both box positions.**
`f38fae8` moved the login box (`box_position_h` 0.5 → 0.30, `box_position_v` 0.5 → 0.62)
and updated `Config.zig` to match, but left the old default annotations. `_h` gained a
rationale comment ("Offset from centre so the box sits clear of the wallpaper's branch");
`_v` got the value change and the stale line but no rationale.

**D2. Doom palette diverges from `Config.zig`.**
`doom_top_color` ships `0x009F2707` vs default `0x00FF0000`; `doom_middle_color` ships
`0x00C78F17` vs default `0x00FFFF00`. Pre-existing upstream drift (`99f3ab9 changes fire
parameters`), not rebrand damage.
- Q1: Align `Config.zig` to the shipped palette (what users actually see), or align
  `config.ini` to the code defaults? Recommend the former.

**D3. `start_cmd` ships a path; `Config.zig` defaults to `null`.** Intentional, but
undocumented as a divergence.

### Group E — Missing documentation

**E1.** `readme.md:76-86` install table lists 6 paths. `installexe` also writes
`startup.sh`, `setup.sh`, `gettytab.example`, `ttys.example`, `example.dur`, `example.lua`,
`lang/`, `custom-sessions/`. See BLUEPRINT §5 for the full verified table.

**E2.** `readme.md:47` still reads `git clone <your-clone-url> sakura`. The remote is
`https://github.com/orpheus497/sakura.git`. No project URL appears anywhere in the repo.

**E3.** No migration documentation. `src/config/migrator.zig` handles `ly_log` →
`sakura_log` (:175), drops `login_defs_path`/`battery_id` as Linux-only (:57-60), and folds
`sleep_key`/`hibernate_key` into custom binds (:191-210). The readme positions Sakura as a
Ly fork, so Ly users are the one audience guaranteed to arrive with a legacy config.

**E4.** No `contributing.md` — deleted in `f38fae8` — yet
`.github/pull_request_template.md` asks contributors to confirm they tested on FreeBSD,
with no guidance on how.

**E5.** No `.github/workflows/`. Nothing enforces that the FreeBSD-only build still
compiles.

**E6.** Readme documents only `gif` and `none`. `src/enums.zig:3-12` also has `doom`,
`matrix`, `colormix`, `gameoflife`, `dur_file`, `lua`. The `-c/--config` flag
(`src/main.zig:163`) is undocumented too.

### Group F — Dead weight *(gated on Directive 3)*

**F1. `res/pixel_sakura_static.png`** — 543 KB, tracked, credited at `readme.md:336`,
never installed by `install.zig`, referenced by no code or config.
- Q1: Wire it in (e.g. as a documented still-image alternative) or delete it and the
  credit line? Deletion is a removal under Directive 3 → needs explicit instruction.

**F2. 13 orphan lang strings across all 25 locale files** (325 dead lines):
`err_config`, `err_mlock`, `err_null`, `err_bounds`, `err_domain`, `err_dgn_oob`,
`err_chdir`, `err_perm_group`, `err_perm_user`, `err_xsessions_dir`, `err_xsessions_open`,
`err_sleep`, `err_hibernate`. The last two are dead because sleep/hibernate became
migrated custom binds.
- Q1: Removal is gated by Directive 3 → needs explicit instruction. Retention-safe
  alternative: leave them and note the status in BLUEPRINT.
- Caution: `err_pam` **is** live (16 references) — do not batch it with these.

**F3. Version-string capitalisation splits.** `src/main.zig:194` prints
`"sakura version …"`; `src/main.zig:47` renders `"Sakura version …"` in the UI (visible
bottom-left in `.github/screenshot.png`). `.github/ISSUE_TEMPLATE/bug.yml` asks reporters
to paste the lowercase one.

---

## VERIFIED CLEAN — no action required

Recorded so later sessions do not re-audit:

- 94/94 `Config.zig` fields ≡ `res/config.ini` keys, both directions.
- 82/82 `Lang.zig` keys ≡ `res/lang/en.ini` keys.
- 25/25 locale files present and all 25 enumerated in `install.zig`.
- All readme build steps and options exist in `build.zig`.
- All readme install paths match `install.zig`.
- Readme system-call claims verified: `reboot(2)` at `interop.zig:215-221`, VT switching at
  `interop.zig:103-106`, keyboard LEDs at `interop.zig:115-131`.
- No systemd / openrc / runit / dinit / elogind remnants anywhere.
- No `ly`/`Ly`/`fairyglade` text outside the deliberate `readme.md:331-340` credits and the
  intentional `ly_log` migration key.
- `.github/screenshot.png` is current Sakura.
- All dependencies MIT/BSD — see BLUEPRINT §3.
