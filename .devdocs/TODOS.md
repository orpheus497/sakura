# TODOS

Last updated: 2026-08-29 09:39

**ACTIVE LIST EMPTY — all 23 v1 items implemented 2026-08-29 (D-013).**

Group **P** (packaging, P1–P9) and Group **V** (documentation, V1–V14) were executed in
full. Per-item results are in the BLUEPRINT §8 implementation registry; the original
findings are retained below as the evidence record.

**Zero open questions.** Every question this backlog ever carried is closed — see
DECISIONS_LOG **D-012**. Do not re-table D-005, D-009 Q1, D-010 Q1, D-011 Q1, P6 Q1, or the
stock-font question.

*(The count read "19" from 2026-08-29 08:54 until corrected; the list held 22 at that
point, and V14 was added at 09:21.)*

| Item | Disposition |
| --- | --- |
| P1 | ✅ `.paths` fixed — **as subpaths**, not directories; see D-013 finding 1 |
| P2 | ✅ `ports/` created: `Makefile`, `pkg-descr`, `pkg-plist`, `pkg-message` |
| P3 | ✅ `pkg-plist` derived from `install.zig` — 14 entries + 25 locales |
| P4 | ✅ gettytab/ttys steps now in `pkg-message`, plus a removal message |
| P5 | ✅ Build-options table in the readme, all nine options |
| P6 | ✅ Dependencies split build/runtime/session/optional. Q1 answered: `pkgconf` required |
| P7 | ✅ **Reversed by USER (D-013): NOT tracked.** The port uses distfiles; added to `.gitignore` |
| P8 | ✅ `create_vendor_tarball.sh` given its header and scoped as an offline convenience |
| P9 | ✅ LuaJIT and the second `translate_c` both named in `ports/Makefile`'s `ZIG_TUPLE` |
| V1 | ✅ 94/94 options covered — 75 named verbatim, 19 by prefix rows |
| V2–V8 | ✅ Autologin, keys + vi mode, corner widgets, custom binds, appearance, language, clock/status, sessions |
| V9 | ✅ Command-line reference table |
| V10 | ✅ Troubleshooting section, including `/etc/ttys` recovery |
| V11 | ✅ `example.lua`, `example.dur` and `custom-sessions/README` signposted as references |
| V12 | ✅ `res/config.ini` autologin comment now tokenised, so it expands correctly |
| V13 | ✅ `main.zig` `--config` help text corrected |
| V14 | ✅ Console-font section leads with "no font build needed" and the stock-font table |

Source of the active work: USER/DEVELOPER request 2026-08-29 — *"analyse all the user
facing docs and explanations and guides and the code to ensure that everything is
comprehensive and detailed for users to understand how to use and configure and customise
this display manager"*, and *"ensure the pkgconfig is going to get all dependencies and
install everything as a whole"*. Goal clarified by USER as **`pkg install sakura`**.

Source of the historical work: USER/DEVELOPER request 2026-08-24 — *"make sure all
documentation and details have been completely updated to the new branding and focus"*,
followed by *"be more comprehensive and detailed"*.

---

## ACTIVE LIST

**Standing constraints on every item (D-011).** Nothing is deleted. No tag is created.
`sakura_version` and `build.zig.zon`'s `.version` are not touched. No new documentation
folder. `res/config.ini` edits are comment-only.

### Group P — Packaging · `pkg install sakura`

**P1. `build.zig.zon` `.paths` omits both path dependencies.** The list names `src` and
`res` but not `sakura-ui` or `sakura-core`, which the same file declares as path
dependencies — so the release copy of Sakura does not build. `license.md` is absent too,
which BSD 2-Clause does not permit for a redistribution.
*Evidence:* `zig fetch --debug-hash .` emits 92 files, none from either folder; a tree
rebuilt from exactly the declared paths fails `unable to open '…/sakura-ui': FileNotFound`.
*Blocks P2–P5.*

**P2. No FreeBSD port exists.** No `Makefile`, `pkg-descr`, `pkg-plist`, `pkg-descr` or
`distinfo` anywhere in the tree. Installation is source-only.
*USER ruling:* the port lives in this repository, in `ports/`.

**P3. `pkg-plist` has to be derived from `install.zig`.** 14 entries plus 25 locale files;
the verified table is BLUEPRINT §5.

**P4. Post-install instructions have no package carrier.** `install.zig:56-67` prints the
`/etc/gettytab` and `/etc/ttys` steps to the screen. A package install shows nobody, and
without them Sakura is installed but never runs. They belong in `pkg-message`; the printed
copy stays for source installs.

**P5. `-Ddest_directory` is undocumented.** It is the staging mechanism a port build
depends on, it works, and it appears nowhere in the readme. Same for `-Dname`,
`-Denable_x11_support` and `-Dfallback_tty`.

**P6. The `pkg install` line is not a dependency specification.** `readme.md:116` mixes
build, runtime and X11-only packages. `git` is used only for the version string;
`xorg`/`xorg-xauth` only for X11 sessions; `python3` is missing though the console-font
workflow needs it.
- Q1 — **ANSWERED 2026-08-29, no longer open (D-012).** `pkgconf` **is** required when
  `-Denable_x11_support` is on. Verified on this host: `pkgconf --modversion xcb` → `1.17.0`,
  `--cflags --libs xcb` → `-I/usr/local/include -L/usr/local/lib -lxcb`, with `xcb.pc` in
  `/usr/local/libdata/pkgconfig`. Write it into the build-dependency list as fact.

**P7. `vendor.tar.zst` is gitignored.** USER ruling: track it, so the port builds offline.

**P8. `create_vendor_tarball.sh` is undocumented.** One line, no `Script function and
purpose:` header, referenced by no document and no build step. It is the offline-distfile
mechanism.

**P9. LuaJIT is a lazy transitive dependency named in no manifest.** It arrives beneath
`zlua`. BLUEPRINT §3 records it correctly; a packager reading `build.zig.zon` alone will
under-specify the distfiles.

### Group V — User-facing documentation

**V1. 25 of 94 settings appear in the readme.** ~17 more are covered by prefix rows
(`doom_*`, `cmatrix_*`, `colormix_*`, `gameoflife_*`, `dur_*`). About **52 are documented
only inside `res/config.ini`**, which can only be read after installing.

**V2. Autologin is undocumented.** Sakura installs a dedicated PAM policy
(`res/pam.d/sakura-autologin`) for a feature the readme never mentions.
`auto_login_user`, `auto_login_session`, `auto_login_service`.

**V3. The vi keys are written down nowhere.** Not the readme, not `config.ini`. They are
`I` to start typing, `Esc` to stop, `H`/`L` to move — `main.zig:1283-1284` and `:589-590`.
A user who sets `vi_mode = true` cannot find out how to type.

**V4. The corner widgets are undocumented.** `corner_top_left` … `corner_bottom_right`,
`custom_bind_width`. Clock, battery, TTY, version, lock states and custom labels, in any
corner, stacked or side by side. The largest customisation surface in the program.

**V5. Custom binds and labels are undocumented.** `[cmd:F8]` and `[lbl:name]` sections and
the `$lang_key` substitution, documented only at the bottom of `config.ini`.

**V6. Appearance settings are undocumented.** `bg`, `fg`, `border_fg`, `error_bg/fg`,
`box_title`, `box_position_h/v`, `margin_box_h/v`, `blank_box`, `hide_borders`,
`edge_margin`, `text_in_center`, `input_len`, `asterisk`, `full_color`.

**V7. Nothing says how to change the language.** 25 translations install; `lang` is never
mentioned.

**V8. Clock, status and session behaviour undocumented.** `clock`, `bigclock*`,
`battery_sysctl`, `custom_sessions`, `session_log`, `save_file_dir`, `type_username`,
`allow_empty_password`, `auth_fails`, `service_name`, `login_cmd`, `logout_cmd`,
`inactivity_cmd`, `inactivity_delay`, `x_cmd`, `xauth_cmd`.

**V9. No command-line reference.** Four options exist (`main.zig:160-164`); two are
explained in prose and never listed together.

**V10. No troubleshooting section.** Nothing on login failing, a blank or garbled console,
block characters rendering as boxes, a session quitting straight back to the login screen,
or recovering a machine after breaking `/etc/ttys`. That last warning exists only in
`contributing.md`, where users will not see it.

**V11. The Lua API reference is not signposted.** `res/example.lua`'s header is a complete
reference — the `sakura` table, `putCell`/`putRect`/`putLabel`/`clock`, the required
`draw()`, the available libraries. The readme calls it "a starting point". Same for
`res/custom-sessions/README`.

**V12. `res/config.ini:65-66` sends autologin users to Linux paths.** The comment names
`/usr/share/xsessions/` and `/usr/share/wayland-sessions/`. Sakura's own defaults are
`$PREFIX_DIRECTORY/share/…` → `/usr/local/share/…` (`:451`, `:475`). Not tokenised, so
install-time substitution does not repair them. Same root cause as closed item B2 and the
permanent hazard in BLUEPRINT §5; `check_invariants.py` compares keys only and cannot see
comment text.

**V13. `--config` help text names the wrong directory.** `main.zig:163` gives
`/usr/local/share/sakura`; it is `/usr/local/etc/sakura`.

**V14. The readme implies a font build is required for the wallpaper. It is not.** Verified
2026-08-29 (D-012): every stock FreeBSD vt font — `spleen-12x24`, `spleen-16x32`,
`spleen-8x16`, `gallant`, `terminus-b32` — already carries all 18 glyphs `Gif.zig` emits
(5 halves/full, 10 quadrants, 3 shades). The wallpaper works out of the box with no
`vidfont` change at all. The "Console font" section must say so first, and reframe
`tools/mkvtfont.py` as the path for using *your own* font. This removes the single largest
piece of apparent setup friction in the project.

---

## ANSWERED — Python provenance (D-011)

USER asked which Python is project work and which was agent-created. Answered in full in
DECISIONS_LOG D-011. Summary: `res/lang/normalize_lang_files.py` is upstream Ly
(Moritz Reinel, 2024-10-12); `tools/mkvtfont.py` is project work added with the wallpaper
in the rebrand commit `f38fae8`; `tools/check_invariants.py` is agent-created in `4a3cdbd`.
**No disposition taken — nothing is deleted.**

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

**Confirmed against the documented font at 10:00.** Hurmit Nerd Font Mono *was* installed;
`find` missed it, `fc-list` found it. At `-p 11` the tool reports `advance fixed 0` — its
bounding box already equals its advance. The hypothesis above was therefore right: Hurmit
was the one font C5 never broke, which is why it went unnoticed.

- Q1 — **answered, and the proposal was wrong.** Synthesising at the advance width is the
  wrong direction. Testing showed normalising `DWIDTH` *up* to the bounding box is accepted
  while shrinking the box to the advance fails, because the overhanging glyphs no longer
  fit. The bounding box is the console cell. See D-006.
- Q2 — **subsumed.** The normalisation runs over the whole glyph buffer before branching,
  so the blank-patching path is covered without a separate change.
- Q3 — **moot.** The mismatch is corrected rather than fatal, so there is nothing to
  hard-fail on; the tool reports an `advance fixed` count instead.

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

## BACKLOG — EMPTY

Every item below is **closed**; the original text is retained as the evidence record for
what was found and why. Nothing here is outstanding. Disposition:

| Group | Items | Disposition |
| --- | --- | --- |
| A | A1, A2 | Fixed — Stage 1 |
| B | B1, B2 | Fixed — Stage 1 |
| C | C1–C4 | Fixed — Stages 1–2 · C5 fixed after being raised mid-execution |
| D | D1–D3 | Fixed — Stage 3 |
| E | E1–E6 | Fixed — Stages 3–4 |
| F | F1, F3 | Fixed — Stages 3–4 |
| F | F2 | **Cancelled** — invalid finding, see D-007 |

---

## HISTORICAL RECORD — the original findings

*(Group C — C1, C2, C3, C4 all completed; see COMPLETED sections above. C5 raised and
since fixed.)*

### Group D — Defaults documented wrong *(all fixed)*

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

### Group E — Missing documentation *(all fixed)*

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

### Group F — Dead weight *(F1/F3 fixed; F2 cancelled — D-007)*

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
