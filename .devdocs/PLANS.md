# PLANS

Forward-looking strategy for items scoped out of DECISIONS_LOG that are not yet
implemented. Last updated: 2026-08-29 08:54.

**Two items pending.** The v1 readiness plan below (D-011) is the active one, approved by
USER and not yet executed. The ecosystem-branding surfaces declined on 2026-08-27 remain
parked beneath it. The archived remediation plan at the bottom has been fully executed and
is kept for its reasoning, not as outstanding work.

---

# EXECUTED 2026-08-29 — v1 Readiness Plan (D-011, D-013)

**All four parts are done.** Retained for its reasoning and for the two places reality
corrected the plan. Results are in the BLUEPRINT §8 registry; narrative in PROGRESS.md.

| Part | Outcome |
| --- | --- |
| 1 — packaging blocker | Done, **but not as written**: `.paths` needs the source *subpaths*, not the directories, because it ignores `.gitignore`. Listing directories gave 1037 files including build cache and vendored deps. See D-013 |
| 2 — the FreeBSD port | Done as `ports/`, **using distfiles rather than a vendored tarball** per USER ruling D-013. `USES=zig` + nine `ZIG_TUPLE` entries |
| 3 — readme | Done. 94/94 options covered; 75 named verbatim, 19 by prefix row. Gained **V14** — the wallpaper needs no font build |
| 4 — three wrong things | Done |

Two assumptions below did not survive contact: **P7** (`vendor.tar.zst` tracked) was
reversed, and the two facts marked "not verifiable from the development host" were both
verified here — the host is FreeBSD (D-012).

---

## The plan as approved

**The goal is `pkg install sakura`.** Two things stand between here and that: the release
copy of Sakura does not build, and the documentation explains about a quarter of the
program. Four parts, in the order they should be done.

**Standing constraints for every part.** Nothing is deleted. No tag is created. Neither
`sakura_version` in `build.zig:22` nor `.version` in `build.zig.zon:3` is touched. No new
documentation folder is created. `res/config.ini` is edited comment-only — it is the
shipped file and its own reference, and people edit it directly.

---

## Part 1 — Fix the packaging blocker · 15 min

`build.zig.zon` carries a `.paths` list naming which folders belong in a release. It lists
`build.zig`, `build.zig.zon`, `install.zig`, `src` and `res`. It does **not** list
`sakura-ui` or `sakura-core` — the two folders the program cannot build without, and which
the same file declares as path dependencies. The release copy of Sakura is therefore a copy
that does not build.

Verified, not inferred: `zig fetch --debug-hash .` emits 92 files and none from either
folder; a tree reconstructed from exactly the declared paths fails with
`unable to open '…/sakura-ui': FileNotFound`.

`license.md` is missing from the list as well, which matters independently — BSD 2-Clause
requires the notice to travel with a redistribution.

| File | Change |
| --- | --- |
| `build.zig.zon` | `.paths` += `sakura-ui`, `sakura-core`, `tools`, `license.md`, `readme.md`. **`.version` untouched.** |

**Verification.** `zig fetch --debug-hash .` lists files under both folders; a packaged
copy configures with `-Dtarget=x86_64-freebsd`.

**Everything in Part 2 depends on this landing first** — a port cannot build from a distfile
that is missing half the source.

---

## Part 2 — Make `pkg install sakura` work · 3–4 h

Today the only way to install Sakura is to clone it and run `zig build installexe`. A
FreeBSD port needs four files in a new `ports/` directory (USER ruling D-011 #2: it lives
here, because there is no port anywhere yet).

| File | Purpose |
| --- | --- |
| `ports/Makefile` | How the ports system builds it. X11 as an on/off OPTION, `LIB_DEPENDS` on `libxcb.so`, and `DESTDIR` wired to the `-Ddest_directory` option `install.zig` already implements |
| `ports/pkg-descr` | The description shown by `pkg search sakura` |
| `ports/pkg-plist` | Every file the package puts on disk. Already known and verified — see BLUEPRINT §5: 14 entries plus the 25 locale files |
| `ports/pkg-message` | The `/etc/gettytab` and `/etc/ttys` instructions |

**Why `pkg-message` is not optional.** `install.zig:56-67` prints those two steps to the
screen at the end of a manual install. In a package install nobody sees them, and without
them Sakura is on disk but never runs. They have to move into the package's own message
channel; the printed copy stays for source installs.

**Three supporting changes:**

1. **The dependency line is not a dependency specification.** `readme.md:116` reads
   `pkg install zig git libxcb xorg xorg-xauth ca_root_nss`, mixing build, runtime and
   X11-only packages into one line. `git` is used only to derive the version string.
   `xorg`/`xorg-xauth` are needed only if you run an X11 session. `python3` is absent
   despite the console-font workflow requiring it, and `pkgconf` is probably required —
   Zig resolves `linkSystemLibrary("xcb")` through pkg-config and `xcb.pc` lives in
   `/usr/local/libdata/pkgconfig`. **The `pkgconf` question needs confirming on a real
   FreeBSD host; it is an inference, not a verified fact.** Split into build / runtime /
   optional.

2. **`vendor.tar.zst` becomes tracked** (D-011 #3), so the port builds with no network.
   `.gitignore` stops ignoring it.

3. **Undocumented build options get documented.** `-Ddest_directory` is the staging
   mechanism a port build depends on and appears nowhere in the readme. Nor do `-Dname`,
   `-Denable_x11_support` or `-Dfallback_tty`. Also note in place that `-Dname` renames only
   the binary and the wrapper — the config directory, both PAM policies and the default
   `service_name` stay `sakura` (`install.zig:83,223-224`).

**Verification.** `zig build installexe -Ddest_directory=/tmp/stage` produces a tree
matching `pkg-plist` exactly, entry for entry.

---

## Part 3 — Make the documentation explain the program · 3–4 h

Sakura has 94 settings. `readme.md` mentions 25. Roughly 17 more are covered by prefix rows
(`doom_*`, `cmatrix_*`, `colormix_*`, `gameoflife_*`, `dur_*`). That leaves about **52
settings documented only inside `res/config.ini`** — a file you can read only after
installing.

The consequence is that entire features are invisible to anyone deciding whether to use
Sakura. All of the following goes into `readme.md`. One file, no `docs/` (D-011 #4).

| Section | What it covers | Why it matters |
| --- | --- | --- |
| **Autologin** | `auto_login_user`, `auto_login_session`, `auto_login_service`, the shipped PAM policy, how to find a session name | Sakura installs a dedicated PAM policy for this and the readme never mentions the feature exists |
| **Keys, including vi mode** | `shutdown_key`, `restart_key`, brightness, `show_password_key`, `vi_mode`, `vi_default_mode` | The vi keys are written down **nowhere** — not the readme, not `config.ini`. They are `I` to start typing, `Esc` to stop, `H`/`L` to move (`main.zig:1283-1284`, `:589-590`) |
| **Corner widgets** | `corner_top_left` … `corner_bottom_right`, `custom_bind_width` | Clock, battery, TTY, version, lock states and your own labels, in any corner, stacked or side by side. The single largest customisation surface in the program |
| **Custom binds and labels** | `[cmd:F8]` and `[lbl:name]` sections, `$lang_key` substitution | Bind a shell command to a function key, or put a command's output on screen and refresh it |
| **Appearance** | `bg`, `fg`, `border_fg`, `error_bg/fg`, `box_title`, `box_position_h/v`, `margin_box_h/v`, `blank_box`, `hide_borders`, `edge_margin`, `text_in_center`, `input_len`, `asterisk`, `full_color` | — |
| **Language** | `lang` | 25 translations install; nothing says how to pick one |
| **Clock and status** | `clock`, `bigclock`, `bigclock_12hr`, `bigclock_seconds`, `battery_sysctl` | — |
| **Sessions and behaviour** | `custom_sessions`, `session_log`, `save_file_dir`, `type_username`, `allow_empty_password`, `auth_fails`, `service_name`, `login_cmd`, `logout_cmd`, `inactivity_cmd`, `inactivity_delay`, `x_cmd`, `xauth_cmd` | — |
| **Command-line reference** | `-h`, `-v`, `-c/--config`, `--validate-config` in one table | All four exist; two are explained in prose and never listed together |
| **Troubleshooting** | Login failing, blank or garbled console, block characters showing as boxes, a session quitting straight back to the login screen, and recovering a machine after breaking `/etc/ttys` | That last warning currently exists only in `contributing.md`, where users will not see it |
| **Writing your own** | Point at `res/example.lua` and `res/custom-sessions/README` | `example.lua`'s header is already a complete API reference for the `sakura` table, `putCell`/`putRect`/`putLabel`/`clock` and the required `draw()`. The readme calls it "a starting point" and never says it is the reference |

**Method.** Every claim read out of `src/config/Config.zig` and `src/main.zig`, not out of
`res/config.ini` — the shipped file is what is being documented, so it cannot be its own
source of truth.

**Verification.** Every one of the 94 options either appears in the readme or is covered by
an explicit prefix row.

---

## Part 4 — Three things that are simply wrong · 30 min

| # | File | Defect |
| --- | --- | --- |
| 1 | `res/config.ini:65-66` | The `auto_login_session` comment tells users to look for session names in `/usr/share/xsessions/` and `/usr/share/wayland-sessions/`. Those are Linux paths. Sakura's own defaults are `$PREFIX_DIRECTORY/share/…` → `/usr/local/share/…` (`:451`, `:475`), and `readme.md:428-429` says so correctly. Anyone following the comment looks in an empty directory |
| 2 | `src/main.zig:163` | `--config` help text gives `/usr/local/share/sakura` as the example. It is `/usr/local/etc/sakura`. The readme is right; the program is not |
| 3 | `create_vendor_tarball.sh` | One line, no explanation of what it does or when to run it, and no `Script function and purpose:` header. It is the mechanism that makes offline port builds possible |

**Note on defect 1.** This is the same root cause as the already-closed B2, recorded as a
permanent hazard in BLUEPRINT §5: `install.zig` substitutes `$PREFIX_DIRECTORY` across the
whole file including comments, so any comment carrying a literal path escapes review. These
two lines are not tokenised, so nothing repairs them. `check_invariants.py` compares keys
only and never reads comment text, so it cannot see this class of defect.

---

## Order and effort

| Order | Part | Effort | Depends on |
| --- | --- | --- | --- |
| 1 | Part 1 — packaging blocker | 15 min | — |
| 2 | Part 4 — three wrong things | 30 min | — |
| 3 | Part 2 — the FreeBSD port | 3–4 h | Part 1 |
| 4 | Part 3 — readme | 3–4 h | — |

**~8 hours total.** Parts 1 and 4 are quick and independent. Part 3 depends on nothing and
can be pulled forward if the documentation should land first.

**Nothing in this plan is blocked, and nothing awaits an answer.** The two items previously
recorded here as "not verifiable from the development host" were both verified on
2026-08-29 — the host is FreeBSD 15.1-RELEASE under the linuxulator, not Linux. See
DECISIONS_LOG **D-012**:

- **`pkgconf` is required** when `-Denable_x11_support` is on. `pkgconf --modversion xcb` →
  `1.17.0`; `xcb.pc` is in `/usr/local/libdata/pkgconfig`. Part 2's dependency split writes
  this as fact.
- **Every stock vt font already carries all 18 wallpaper glyphs** — `spleen-12x24`,
  `spleen-16x32`, `spleen-8x16`, `gallant`, `terminus-b32`, all 5/5 halves, 10/10 quadrants,
  3/3 shades. Part 3 gains **V14**: the readme must lead with "it works out of the box" and
  reframe `mkvtfont.py` as the bring-your-own-font path.

---

## PENDING — Ecosystem branding, the two declined surfaces (D-010)

The 2026-08-27 pass landed the ecosystem framing in `readme.md` only, by USER scope
ruling. Three surfaces were offered and declined. None is urgent while the desktop has no
users; the first becomes actively useful the moment it does.

### 1. `.github/ISSUE_TEMPLATE/bug.yml` and `feature.yml` — issue routing *(highest value)*

Neither template says anything about the desktop, so a hikari-sakura crash or a Sofi menu
bug has no signpost pointing elsewhere and will be filed here. `bug.yml` already asks for
"Desktop environment/Window manager", which is precisely where a user running the Sakura
desktop will type "Hikari Sakura" — into this repository's tracker.

Proposed: a `type: markdown` block above the prerequisites naming the three trackers and
what belongs in each, and a prerequisite checkbox confirming the problem reproduces at the
login screen rather than inside the session. Cost: ~15 min. Risk: none.

### 2. `contributing.md` — which repository owns which change

The file scopes contributions against Ly (send FreeBSD-neutral fixes upstream too) but says
nothing about the sibling repositories. The boundary is clean and worth stating: anything
before authentication is Sakura's; anything about window management is hikari-sakura's;
anything drawn by a layer-shell surface is Sofi's. The one genuinely ambiguous case is
session hand-off, which is Sakura's up to `exec` and the compositor's after it.

Also worth adding to *Things that must stay in step*: the `waylandsessions` default path is
load-bearing for compositor discovery (BLUEPRINT §1.1) — changing it silently removes the
Hikari Sakura entry from the session list. Cost: ~20 min.

### 3. `res/config.ini` and `res/custom-sessions/README` — in-file branding

Lowest value and highest caution. `res/config.ini` is checked key-for-key against
`src/config/Config.zig` by `tools/check_invariants.py`, and it is the shipped file as well
as the documentation, so any edit must stay comment-only. A sentence at
`waylandsessions` noting that hikari-sakura installs its entry into the default path would
be genuinely useful; a general branding banner would not. `custom-sessions/README` needs
nothing — custom entries are orthogonal to the desktop. Cost: ~10 min.

### 4. Cross-repository reciprocity — **REMOVED 2026-08-29**

Closed by USER (D-010 Q1, D-012): the sibling repositories link each other, and their
content is not this repository's concern. **Not an item. Do not re-add.**

---

## ARCHIVED — Remediation Plan, Post-Rebrand Documentation Defects
*Executed 2026-08-24, stages 1–4. Retained for its rationale and risk analysis.*

**Outcome:** all four stages completed. C5 was discovered mid-execution, approved, and
fixed — note that the remedy proposed for it below was refuted by testing (D-006). F2 was
cancelled as an invalid finding (D-007). F1 and the A1 removal option were resolved by
explicit USER instruction. The "Standing Invariant Checks" proposed at the end were
implemented as `tools/check_invariants.py` and wired into CI.

Per-item results are in the BLUEPRINT §8 implementation registry; narrative is in
PROGRESS.md.

Four stages, ordered by user-visible wrongness. Each stage is independently approvable and
independently shippable; later stages do not depend on earlier ones.

### Stage 1 — Correct what is visibly wrong *(recommended first)*

| Item | File | Change |
| --- | --- | --- |
| A1 | `res/example.dur` | Replace Ly logo artwork — **blocked on TODOS A1/Q1** |
| B1 | `res/config.ini:1` | Rewrite the "24-bit true color" claim to match the vt(4) reality stated at :257-260 |
| B2 | `res/config.ini:444,468` | Fix `$PREFIX_DIRECTORY/local/share/…` → valid FreeBSD paths |
| C4 | `res/lang/*.ini` ×24 | Add `err_gif`; run `res/lang/normalize_lang_files.py` |

Rationale: these are the four defects a user can hit without reading source — upstream
artwork on screen, a false statement in line 1 of their config, a documented path that
expands to `/usr/local/local/share`, and an untranslated error on the flagship feature.

Risk: low. A1 is asset work; the rest are text. C4 touches 24 files but adds one line each.
Verification: re-run the `Lang.zig` ↔ locale key diff; expect 82/82 across all 25 files.

### Stage 2 — Make the font toolchain deliver on the wallpaper

| Item | File | Change |
| --- | --- | --- |
| C2 | `tools/mkvtfont.py:39-47` | Extend `BLOCKS` to the 10 missing quadrants |
| C1 | `tools/mkvtfont.py:11-17` | Rewrite the docstring for the quadrant+shade renderer |
| C3 | `readme.md:294-296` | Correct the font glyph requirement list |

Proposed implementation for C2 — derive the predicates from the same 2×2 mask `Gif.zig`
uses rather than hand-writing ten lambdas. Bits UL=8, UR=4, LL=2, LR=1:

```python
def _quad(mask):
    return lambda x, y, w, h: bool(mask & (
        8 if (y < (h+1)//2 and x < (w+1)//2) else
        4 if  y < (h+1)//2 else
        2 if  x < (w+1)//2 else 1))

BLOCKS.update({cp: _quad(m) for cp, m in {
    0x2597:0b0001, 0x2596:0b0010, 0x259D:0b0100, 0x259E:0b0110, 0x259F:0b0111,
    0x2598:0b1000, 0x259A:0b1001, 0x2599:0b1011, 0x259C:0b1101, 0x259B:0b1110,
}.items()})
```

This re-derives U+2580/2584/258C/2590/2588 identically, so the existing five entries can
fold into one table and the glyph set stops being duplicated by hand.

Risk: **this is the only stage that changes behaviour.** It alters generated font
bitmaps. Verification: build a font with `mkvtfont.py`, confirm the reported
`blocks exact` count rises from 8 to 18, and confirm the wallpaper renders without
banding on a real console.

### Stage 3 — Accuracy pass *(mechanical, low risk)*

| Item | File | Change |
| --- | --- | --- |
| D1 | `res/config.ini:105-112` | Drop both stale `# default: 0.5` lines; give `box_position_v` the rationale comment its sibling has |
| D2 | `src/config/Config.zig:52-53` | Align doom defaults to shipped palette — **blocked on TODOS D2/Q1** |
| D3 | `res/config.ini:423-425` | Note `# default: null` above `start_cmd` |
| D-readme | `readme.md:157` | Soften the "includes the default values" claim to match reality |
| E1 | `readme.md:76-86` | Add the 8 missing install-table rows (source table in BLUEPRINT §5) |
| E2 | `readme.md:47` | Replace `<your-clone-url>` with the real remote |
| F3 | `src/main.zig:194` | `"sakura version"` → `"Sakura version"` for consistency with :47 and the UI |

### Stage 4 — New documentation and cleanup

| Item | Change |
| --- | --- |
| E3 | New readme section: "Migrating from Ly" — renames, dropped options, folded keybinds |
| E6 | Document the remaining `animation` values and the `-c/--config` flag |
| E4 | Restore a FreeBSD-specific `contributing.md` |
| E5 | Add `.github/workflows/` with at least a `zig build` job |
| F1 | `res/pixel_sakura_static.png` — was gated on Directive 3; USER instructed removal, verified unreferenced, removed |
| F2 | 13 orphan lang strings — was gated on Directive 3; verification showed they are reachable and documented, so **cancelled** (D-007) |

---

## Standing Invariant Checks — IMPLEMENTED

D-001 surfaced invariants that drift silently. These were implemented as
`tools/check_invariants.py` and run as the first CI job, gating the FreeBSD build:

1. **Config parity.** `Config.zig` field set ≡ `config.ini` key set. ✅
2. **Lang parity.** `Lang.zig` key set ≡ every locale's key set. ✅
3. **Installed locales.** `res/lang/*.ini` ≡ the `languages` array in `install.zig`. ✅
4. **Wallpaper glyph set.** `Gif.zig`'s codepoint tables ≡ `mkvtfont.py`'s `BLOCKS`. ✅

The checker refuses to pass vacuously on empty input, after its own first draft passed a
check it should have failed.

**Still not automated:** the cell-geometry invariant from C5 — that glyphs are synthesised
at the `FONTBOUNDINGBOX` cell and every `DWIDTH` matches it. Recorded in BLUEPRINT §6 as
prose only, since verifying it needs a real font build rather than a text comparison.
