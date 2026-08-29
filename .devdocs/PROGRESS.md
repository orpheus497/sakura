# PROGRESS

Macro progress tracking of completed, superseded, removed, or otherwise archived todos.
Most recent at top.

---

## 2026-08-29 10:24 — Review findings: six fixed, one inverted on verification

Seven review findings against the v1 work. Each was checked against source before acting;
**one had its claim backwards and one turned out to be a code defect rather than a doc
defect.**

| Finding | Verified against | Action |
| --- | --- | --- |
| `pkg-descr` overstates "no helper binaries" | `install.zig`, `res/sakura.gettytab` | Fixed — the claim is about syscalls, but `sakura_wrapper` *is* installed and named by `/etc/gettytab`. Now says so |
| `pkg-message` passes a directory to `--validate-config` | `main.zig:163` | Fixed — it takes a file; now `…/etc/sakura/config.ini` |
| `default_input` missing `info_line` | `enums.zig` `Input` | Fixed — the enum is `info_line, session, login, password` |
| F7 "while held" | `main.zig:1440` `togglePasswordMask` | Fixed — it toggles |
| `animation_frame_delay` "frames to wait" | `res/config.ini:34` | Fixed — milliseconds |
| Corner commas/spaces | `positionCorner` / `positionItem` | Fixed, **but the finding had it backwards** — see below |
| Label `refresh` off-by-one | `main.zig:1845-1887` | Fixed **in code**, not docs — see below |

### The finding that was inverted

It asked for the docs to say spaces place entries side by side and commas stack them. The
code does the **opposite**: `positionCorner` tokenises on spaces/tabs/brackets and bumps
`y_offset` per token — so a space starts a new line — while `positionItem` splits a token
on commas and advances a shared `line_x`, so commas sit side by side.

My original text was wrong too, in the same direction, *and* misread the shipped default.
`corner_top_left = shutdown,restart,britup,britdown,password battery` is **two lines**: the
five hints on the first, `battery` on the second. Now documented as the code behaves.

### The finding that was a real bug

`refresh` was documented as "frames to wait", and the counter did not deliver that. The
counter was reset to `refresh` and then decremented in the **same** pass, so `refresh = N`
waited `N-1` frames, and `refresh = 1` fell straight to 0 and never repeated — identical to
`refresh = 0`.

The finding permitted fixing either side. Documenting it would have meant writing "N waits
N-1, and 1 means never", i.e. publishing the bug as an interface. Fixed in
`src/main.zig` instead by making the reset and the tick mutually exclusive
(`else if`), which is a four-line change that leaves `refresh = 0` running exactly once as
before. The stale comment above it was rewritten, which is in scope under D-005 because the
task already required editing that logic.

**This is the session's only change to runtime behaviour.** `zig ast-check src/main.zig`
passes, but that is parse-and-AST only — **it has not been compiled or run**, and it needs
`zig build` plus `zig build test` on a native FreeBSD userland (BLUEPRINT §0).

**Verification:** `check_invariants.py` all four families · option coverage still 94/94
(75 verbatim, 19 prefix, 0 uncovered) · `zig ast-check` clean.

**Files modified: 4** — `readme.md`, `ports/pkg-descr`, `ports/pkg-message`,
`src/main.zig`.

---

## 2026-08-29 09:39 — v1 readiness plan executed in full (D-013)

USER: *"proceed - i want this to be a normal pkg not something complicated"*. All four
parts of the v1 plan executed. **23 of 23 backlog items closed.**

### The ruling that shaped it

**A normal port fetches distfiles.** `vendor.tar.zst` is not tracked — this reverses
D-011 #3. `/usr/ports/Mk/Uses/zig.mk` already provides exactly the mechanism: `USES=zig`
plus a `ZIG_TUPLE` list naming each Zig dependency as an ordinary distfile. No blob in the
repository. `create_vendor_tarball.sh` is kept and documented as an air-gapped convenience
only, and `vendor.tar.zst` was added to `.gitignore`, which had never named it.

### Part 1 — and the correction the plan needed

PLANS said to add `sakura-ui` and `sakura-core` to `.paths`. Done literally, that produced
**1037 files** in the package: `.paths` does not honour `.gitignore`, so `.zig-cache/` and
the vendored `zig-pkg/` trees came with them — machine-specific build cache plus a
duplicate of every dependency the port fetches separately, for roughly 30 files of actual
source.

Naming the subpaths instead — `<dep>/build.zig`, `<dep>/build.zig.zon`, `<dep>/src`,
mirroring what each sub-manifest declares for itself — gives **89 files, zero leakage**,
with both dependency trees, `license.md` and `readme.md` present. The blocker is fixed and
the invariant in BLUEPRINT §9.1 now states the correct form.

### Part 2 — the port

Written against the real convention, not invented: `zig.mk` was read in full and
`devel/zls` used as the reference port. `lang/zig` is 0.16.0, matching
`minimum_zig_version` exactly.

All nine dependencies were resolved from the fetched `zig-pkg/` trees rather than guessed,
which is the only way two of them surface at all — **LuaJIT**, lazy beneath `zlua` because
the build requests `.lang = .luajit`, and a **second `translate_c` at 0.0.0**, zlua's own
copy alongside the 1.0.0 that sakura-ui and sakura-core use.

**One trap found and commented in the Makefile.** `install.zig:117` reads the binary from
the literal path `zig-out/bin/sakura`, not from Zig's `--prefix`. `USES=zig` passes
`--prefix ${PREFIX}` by default, which would both write outside the stage directory and
break that read. The port defines its own `do-install` that omits `--prefix` and stages
through `-Ddest_directory=${STAGEDIR}`.

Config files ship as `.sample` so an upgrade cannot overwrite an edited `config.ini`.

### Part 3 — the readme

**94/94 options now covered: 75 named verbatim, 19 by explicit prefix row, 0 uncovered**
(measured, not asserted). New sections: command-line reference, language, autologin,
appearance, corner widgets, custom commands and labels, clock and status, sessions and
behaviour, writing your own animations, a full key table with vi mode, and troubleshooting
including single-user recovery from a broken `/etc/ttys`.

`animation_timeout_sec` was the one option with neither a mention nor a prefix family; the
coverage check caught it and it now has a row.

### Part 4 and V14

`res/config.ini` autologin comment now uses `$PREFIX_DIRECTORY`, so install-time
substitution points it at the same paths as the options themselves — turning the
BLUEPRINT §5 hazard into the fix. `main.zig` `--config` help corrected.
`create_vendor_tarball.sh` documented.

**V14 is the finding users will feel most.** The console-font section now leads with the
fact that no font build is needed, with the stock-font coverage table. The prior text
presented a Python toolchain as part of setup for a feature that works out of the box.

### Verification

`check_invariants.py` — all four families hold. `zig fetch --debug-hash .` — 89 files,
both path dependencies, no cache or vendor leakage. Option coverage — 94/94.

**Not built.** `zig build` needs FreeBSD base headers the linuxulator's Linux userland
does not supply (BLUEPRINT §0), so the port needs one build test on a native FreeBSD
userland before it can be called proven. `distinfo` is absent by design — always generated
with `make makesum`, and that needs the `v1.0.0` tag, which is out of scope (D-011 #7).

**Files modified: 8 product files + 7 trackers.** `build.zig.zon`, `src/main.zig`,
`res/config.ini`, `readme.md`, `create_vendor_tarball.sh`, `.gitignore`, and four new
files under `ports/`.

---

## 2026-08-29 09:21 — Every open question closed; the host is FreeBSD (D-012)

USER, on being asked about D-005 again: *"why are you asking me about retroactive commenting
again — what for, why does this keep coming up, I answer it every fucking time"*, and on the
set as a whole: *"all these questions have me responding … we need to resolve them before
anything, I'm sick of them coming up every session"*.

**They were right, and the cause was a tracker defect rather than a gap in their answers.**
Four of the six had already been answered, and were left with the word `OPEN` beside them.
Each new session read the trackers, saw `OPEN`, and re-asked. The briefing then reprinted
them under *Current Blockers*, which guaranteed the loop.

### The host fact that invalidated two of them

`uname -s` reports `Linux`; `uname -a` reports
`FreeBSD 15.1-RELEASE releng/15.1-n283562-96841ea08dcf`. This is the **linuxulator** — a
Linux userland on a FreeBSD kernel, with `/usr/local` and `/usr/share` visible. It was
recorded once at PROGRESS 2026-08-24 10:00 and then lost. Two "needs a FreeBSD box" items
were answerable on the spot. Now recorded permanently as **BLUEPRINT §0**.

### Both verified, not asserted

**`pkgconf` is required** with `-Denable_x11_support`: `/usr/local/bin/pkgconf` present,
`pkgconf --modversion xcb` → `1.17.0`, `--cflags --libs xcb` →
`-I/usr/local/include -L/usr/local/lib -lxcb`, `xcb.pc` in `/usr/local/libdata/pkgconfig`
(**not** `lib/pkgconfig` — the ports convention, and what a packager needs to know).
Closes TODOS P6/Q1.

**Every stock vt font already carries all 18 wallpaper glyphs.** The `.fnt` mapping tables
were decoded directly (`VFNT0002` header, bitmap block, then big-endian `{src,dst,len}`
entries) and checked against the codepoints `Gif.zig` emits:

| Font | Cell | Halves/full | Quadrants | Shades |
| --- | --- | --- | --- | --- |
| `spleen-12x24` | 12x24 | 5/5 | 10/10 | 3/3 |
| `spleen-16x32` | 16x32 | 5/5 | 10/10 | 3/3 |
| `spleen-8x16` | 8x16 | 5/5 | 10/10 | 3/3 |
| `gallant` | 12x22 | 5/5 | 10/10 | 3/3 |
| `terminus-b32` | 16x32 | 5/5 | 10/10 | 3/3 |

**This is a finding, not just a closure.** The wallpaper — the feature the fork exists for —
works on a stock FreeBSD install with no font build whatsoever. The readme's "Console font"
section presents that build as setup, which overstates the friction of adopting Sakura by a
wide margin. Raised as new backlog item **V14**: lead with "it works out of the box" and
reframe `tools/mkvtfont.py` as the bring-your-own-font path.

### Six closures

D-005 (the rule is written in `AGENTS.md`; never was a question) · D-009 Q1 (the
`license.md` carve-out **is** the disposition, taken when the entry was written) · D-010 Q1
(closed by USER — the siblings link each other; other repositories are not this one's
concern) · D-011 Q1 (closed by fact — `git diff -- tools/` empty, both files on disk) ·
P6 Q1 · the stock-font question. **Zero open questions remain.**

### The convention that stops the recurrence

Recorded in D-012 and echoed at the head of BRIEFING.md: an answered question is rewritten
*as its answer*, marked `CLOSED` with date and basis, and carries *"Do not re-table."* It is
never left phrased as a question. A question whose answer is already in `AGENTS.md` is not a
question. Nothing about another repository is ever an open item here. Briefings report
outstanding **work**, not resolved history.

**Also corrected:** the backlog count read "19" in three trackers while Groups P and V held
22 items; now 23 with V14.

**Files modified: 7 — all `.devdocs/`.** No product file was touched.

---

## 2026-08-29 08:54 — v1 readiness audit complete; plan approved, not yet executed (D-011)

USER: *"analyse all the user facing docs and explanations and guides and the code to ensure
that everything is comprehensive and detailed for users to understand how to use and
configure and customise this display manager"*, plus *"ensure the pkgconfig is going to get
all dependencies and install everything as a whole"*. Goal clarified mid-session as
**`pkg install sakura`**.

**Analysis only. No product file was modified.** Deliverable is the plan now in PLANS.md
and the 19-item backlog now in TODOS.md (Groups P and V).

### What the audit established

**One defect blocks packaging outright, and it was proved rather than argued.**
`build.zig.zon` `.paths` omits `sakura-ui` and `sakura-core`, the two path dependencies the
same file declares. `zig fetch --debug-hash .` emits 92 files and none from either
directory; a tree reconstructed from exactly the declared paths fails at configure time with
`unable to open '…/sakura-ui': FileNotFound`. `license.md` is absent from the list too,
which BSD 2-Clause does not permit for a redistribution. Recorded as BLUEPRINT §9.1.

**No FreeBSD port exists at all.** No `Makefile`, `pkg-descr`, `pkg-plist`, `pkg-message`
or `distinfo` anywhere in the tree; the only such filenames are inside vendored LuaJIT and
termbox2. Installation is source-only.

**`-Ddest_directory` — a complete `DESTDIR` equivalent — works and is documented nowhere.**
So are `-Dname`, `-Denable_x11_support` and `-Dfallback_tty`.

**The documentation covers about a quarter of the program.** 25 of 94 settings appear in
`readme.md`; ~17 more are covered by prefix rows; ~52 exist only as comments inside
`res/config.ini`, readable only after installing. Autologin ships its own PAM policy and is
never mentioned. The vi-mode keys (`I`, `Esc`, `H`, `L`) are written down in no file at all.

**Three outright errors.** `res/config.ini:65-66` sends autologin users to
`/usr/share/{x,wayland}sessions/` — Linux paths, untokenised, so install-time substitution
cannot repair them; same root cause as closed item B2 and the permanent hazard in
BLUEPRINT §5. `main.zig:163` gives the wrong config directory in `--config`'s help text.
`create_vendor_tarball.sh` has no explanation of what it is for.

### The Python provenance question, answered

USER asked which Python is project work and which was agent-created, and objected to
`tools/` existing at all. Determined from `git log`, not assumed. Upstream Ly at the fork
point (`db7f8ac`) held **one** Python file and **no `tools/` directory**.

| File | Origin | Verdict |
| --- | --- | --- |
| `res/lang/normalize_lang_files.py` | `06e2839`, 2024-10-12, Moritz Reinel | Project — upstream Ly |
| `tools/mkvtfont.py` | `f38fae8` — the rebrand commit, alongside `Gif.zig` | Project — serves the wallpaper |
| `tools/check_invariants.py` | `4a3cdbd` — the process-scaffolding commit | Agent-created |

All three were read in full before classifying. Detail in DECISIONS_LOG D-011.

### A prior-session failure recorded

TODOS item **E4** logged the absence of `contributing.md` as a defect and restored the file.
That deletion was deliberate — D-000 records it as part of the rebrand, and USER confirmed
they *"keep deleting it as trash"*. A USER decision was classified as a bug and reversed.
Rule added in D-011: check whether a file's removal was intentional in the commit that
removed it before recording its absence as a finding.

### Nine rulings taken

`pkg install sakura` is the goal · the port lives in this repository · `vendor.tar.zst`
tracked · readme stays one file, no `docs/` · `res/config.ini` stays its own reference,
comment-only edits · no man pages for v1 · **no tags and no version edits** · CI toolchain
pinning left alone · BRIEFING's stale SHAs left alone. Over all of it:
**nothing is deleted.**

### Not verifiable from this host — **WRONG; SUPERSEDED 2026-08-29 09:21 (D-012)**

> Both were verifiable here and are now answered: `pkgconf` **is** required, and every stock
> vt font **already carries** all 18 glyphs. The premise below — that this host is not
> FreeBSD — was false. It is FreeBSD 15.1 under the linuxulator. See BLUEPRINT §0.

Whether `pkgconf` is genuinely required for `linkSystemLibrary("xcb")`, and whether the
stock `spleen-12x24.fnt` the readme recommends already carries the quadrant and shade
glyphs. Both need a FreeBSD box. Both flagged in PLANS and TODOS rather than assumed.

---

## 2026-08-27 07:52 — Ecosystem branding landed in the readme (D-010)

USER: *"the predominant focus of this session is to ensure the branding the documentation
(readme and user facing) is all completely detailed and comprehensive"* — Sakura,
hikari-sakura and Sofi are three components of one FreeBSD Wayland desktop, and the naming
of the other two derives from this one.

**Starting state: the framing was entirely absent.** A grep for `hikari|sofi|layer.?shell`
across all product docs returned nothing — the only `wayland` hits were the generic session
plumbing (`res/config.ini`, `res/lang/*.ini`, `src/`). Sakura was documented purely as a
standalone Ly fork. Meanwhile sofi's readme cross-links hikari-sakura throughout, and
hikari-sakura's default `hikari.conf` already binds four `sofi` actions, so the ecosystem
was real in the code and invisible in this repository's documentation.

**Delivered — `readme.md`, four changes:**

| Change | Detail |
| --- | --- |
| Opening rewritten | Leads with Sakura as the desktop's login layer, then states plainly that it depends on neither sibling and launches any session another login manager would |
| New §*The Sakura desktop* | Component table (layer/role/licence), why the split falls on process and privilege boundaries, §*Where the names come from*, and a six-step runtime hand-off from `init(8)` to logout |
| New §*Running hikari-sakura* | Under Sessions: zero-config discovery, why `start-hikari` and not `hikari`, the two FreeBSD Wayland prerequisites, where Sofi's daemons go, and why `x_vt` does not apply |
| Credits + License extended | Sibling ancestry (`raichoo`; rofi/simpleswitcher) and the three licences, noting all are permissive so the desktop redistributes as a whole |

**Every integration claim was verified against the sibling working copies**, not asserted —
the evidence table is in DECISIONS_LOG D-010. The two most useful additions are negative
claims, because both are mistakes a reader would otherwise make: Sofi's daemons must *not*
go in Sakura's `setup.sh` (it runs before the compositor exists), and `x_vt` does *not*
apply to a Wayland compositor.

**Scope.** USER selected `readme.md` only. `contributing.md`, the `.github/` issue
templates and `res/` were offered and declined; they are parked in PLANS.md rather than
dropped. No code changed, so no build verification was required.

**Left open.** The lineage is documented in one direction only — neither sibling repository
mentions Sakura. Recorded as D-010 Q1.

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
