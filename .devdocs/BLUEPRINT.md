# BLUEPRINT — Sakura System Architecture

Last updated: 2026-08-29 09:39

## 0. Development Host — read this before deferring any platform question

**The development host is FreeBSD.** `uname -a` reports
`Linux cyronetics 5.15.0 FreeBSD 15.1-RELEASE releng/15.1-n283562-96841ea08dcf GENERIC`:
a Linux userland under the FreeBSD **linuxulator** (`/compat/linux`), on a FreeBSD 15.1
kernel, with the host's `/usr/local` and `/usr/share` visible.

`uname -s` alone reports `Linux` and has repeatedly misled sessions into recording platform
facts as "unverifiable, needs a FreeBSD box". They are verifiable here. Available directly:
`pkgconf`, `pkg-config`, `vtfontcvt`, `otf2bdf`, the installed ports tree under
`/usr/local`, and `/usr/share/vt/fonts`.

**The one real limit** is that `zig build` links against FreeBSD *base system* headers
(`security/pam_appl.h`, `login_cap.h`, `sys/kbio.h`, `sys/consio.h`) that the Linux userland
does not supply — which is precisely and only what the CI FreeBSD VM exists for (§3, and
PROGRESS 2026-08-24 09:55). Everything else: check it, do not defer it. See D-012.

## 1. Product Identity

Sakura is a lightweight TUI display manager built **exclusively for FreeBSD**. It is a
platform-narrowed fork of [Ly](https://codeberg.org/fairyglade/ly) (the Fairy Glade). The
fork's two defining departures from upstream are:

1. **FreeBSD-only.** `build.zig` refuses any other target. All console, power-management
   and account handling goes through native interfaces rather than a portability layer.
2. **Animated GIF wallpaper.** The default `animation` is `gif`, rendered onto the vt(4)
   console with quadrant and shade glyphs.

Project licence: BSD 2-Clause (`license.md`), relicensed from the inherited WTFPL on
2026-08-25 — see DECISIONS_LOG entry D-009. `res/setup.sh` is carved out and keeps its own
notice; bundled dependencies keep theirs (§3).

### 1.1 Ecosystem Position (D-010)

Sakura is the **login layer of the Sakura desktop**, a three-component Wayland desktop
environment for FreeBSD. The other two are separate repositories with separate build
systems and licences; this repository has **no build-time or run-time dependency on
either**, and the coupling is entirely by freedesktop convention.

| Component | Repository | Layer | Build | Licence |
| --- | --- | --- | --- | --- |
| **Sakura** (here) | `orpheus497/sakura` | Login / session launch, on `vt(4)` | Zig 0.16 | BSD 2-Clause |
| **hikari-sakura** | `orpheus497/hikari-sakura` | Wayland compositor, wlroots 0.20 | `make` | BSD 2-Clause |
| **Sofi** | `orpheus497/sofi` | Layer-shell surfaces, one binary | Meson | MIT/X11 |

**Naming lineage.** Sakura was named first. hikari-sakura = *hikari* (the forked
compositor, `antaz/hikari` by `raichoo`) + *sakura* (this project). Sofi = the **S** of
Sakura substituted for rofi's leading **r**.

**Integration contract — the four points of contact, all conventional:**

1. **Session discovery.** hikari-sakura installs `hikari.desktop` to
   `${PREFIX}/share/wayland-sessions`, which is Sakura's default `waylandsessions`
   (`res/config.ini`). Sakura's existing desktop-entry crawler (`src/main.zig`, `crawl`)
   finds it with no special-casing. **No Sakura code knows the name "hikari".**
2. **Session launch.** The entry's `Exec=start-hikari` — the wrapper, never the `hikari`
   binary, because the wrapper establishes `XDG_RUNTIME_DIR` and the D-Bus session.
3. **Environment.** Sakura's `setup_cmd` (`res/setup.sh`) runs *before* the compositor
   exists. Layer-shell clients (Sofi) therefore belong in hikari-sakura's own
   `~/.config/hikari/autostart`, not here.
4. **Return.** Session exit returns control to Sakura on the same virtual terminal.

**Invariant.** Any change to the default `waylandsessions` path, or to desktop-entry
crawling, breaks discovery of the compositor session silently — the entry simply stops
appearing in the list. This is the only structural coupling worth guarding.

## 2. Module Topology

| Module | Role | Depends on |
| --- | --- | --- |
| `sakura-core/` | Platform interop layer. FreeBSD syscalls/ioctls, PAM, logging, shared error page, UID ranges. | zigini, translate_c |
| `sakura-ui/` | Terminal drawing. Cells, positions, buffer, widgets, components, keyboard. | sakura-core, termbox2, translate_c |
| `src/` | The display manager itself. Auth, session discovery, config, animations, main loop. | sakura-ui, clap, zlua |

Dependency direction is strictly one-way: `src` → `sakura-ui` → `sakura-core`. The GIF
decoder (`src/animations/gif/decoder.zig`) deliberately has **no** UI-layer dependency so
it can be tested standalone.

## 3. Dependency Register (Directive 2 — FOSS Compliance)

All dependencies verified against vendored sources on 2026-08-24. **Zero copyleft, zero
proprietary.**

| Dependency | Licence | Role |
| --- | --- | --- |
| `zig-clap` (Hejsil) | MIT | Command-line argument parsing |
| `zlua` / ziglua (natecraddock) | MIT | LuaJIT bindings for the `lua` animation |
| LuaJIT (Mike Pall) | MIT (`COPYRIGHT`) | Scripted animation runtime |
| `zigini` (Ash Ametrine) | MIT | INI parsing for config, lang, save files |
| `ini` (Felix Queißner) | MIT (`LICENCE`) | Transitive, under zigini |
| `termbox2` (AnErrupTion fork) | MIT | Terminal cell buffer |
| `translate_c` (Zig contributors) | MIT (Expat) | C header translation at build time |
| `aro` (Veikka Tuominen) | MIT | Transitive, under translate_c |
| OpenPAM | BSD | Authentication (FreeBSD base) |
| libxcb | MIT | X11 support (optional, `-Denable_x11_support`) |

**How each is obtained, which matters for packaging (§9):**

- `clap` and `zlua` are fetched by URL from the top-level `build.zig.zon`; `zigini`,
  `termbox2` and `translate_c` from the sub-package manifests; `aro` and `ini` are
  transitive beneath those.
- **LuaJIT is a lazy transitive dependency and appears in no manifest.** It is pulled in
  beneath `zlua` when `.lang = .luajit` is requested, and lands in `zig-pkg/` under a
  content hash. A packager reading `build.zig.zon` alone will under-specify the distfiles.
- `OpenPAM`, `libc` and the FreeBSD headers of §4 come from base — nothing to fetch.
- `libxcb` is the only external system library, resolved through
  `linkSystemLibrary("xcb")`. Zig resolves that through pkg-config, so **`pkgconf` is a
  build dependency whenever `-Denable_x11_support` is on — confirmed 2026-08-29, D-012.**
  `pkgconf --modversion xcb` → `1.17.0`; `--cflags --libs xcb` →
  `-I/usr/local/include -L/usr/local/lib -lxcb`. Note `xcb.pc` lives in
  `/usr/local/libdata/pkgconfig`, **not** `/usr/local/lib/pkgconfig`, which is the FreeBSD
  ports convention and where a packager should expect it.
- The toolchain is Zig ≥ 0.16.0, enforced at comptime in `build.zig:11-20`. `git` is
  optional: without it `getVersionStr` falls back to `sakura_version` verbatim.

## 4. FreeBSD Platform Interfaces

The FreeBSD-only claim is load-bearing; these are the interfaces that make portability
impractical, all reached through `sakura-core/src/interop.zig`:

| Interface | Header | Purpose |
| --- | --- | --- |
| `VT_ACTIVATE` / `VT_WAITACTIVE` / `VT_GETINDEX` | `consio` | Virtual terminal switching and identification |
| `KDGETLED` / `KDSETLED`, `LED_NUM`, `LED_CAP` | `kbio` | Numlock/capslock state and LEDs, in-process |
| `reboot(RB_POWEROFF)` / `reboot(RB_AUTOBOOT)` | `reboot` | Shutdown and restart without a helper binary |
| `sysctl(3)` | `sysctl` | Battery charge via `battery_sysctl` MIB |
| `setusercontext(3)`, `pwd` | `unistd`, `pwd` | Account and login-class handling |
| `utmpx` | `utmp` | Session accounting |
| OpenPAM | `pam` | Authentication; note OpenPAM does not support the `-` module prefix |

Consequence for packaging: no helper binaries are required for power, VT switching or
keyboard LEDs. Only X11 sessions need external commands (`X`, `xauth`).

## 5. Install Topology

Prefix defaults follow the FreeBSD ports layout: `prefix_directory=/usr/local`,
`config_directory=/usr/local/etc`.

| Path | Source | Notes |
| --- | --- | --- |
| `$PREFIX/bin/sakura` | `zig-out/bin/sakura` | The display manager |
| `$PREFIX/bin/sakura_wrapper` | `res/sakura-wrapper` | Strips the `login -fp root` args `getty` appends |
| `$CONFIG/sakura/config.ini` | `res/config.ini` | Patched; `config.ini.example` kept pristine alongside |
| `$CONFIG/sakura/startup.sh` | `res/startup.sh` | Runs before the TTY is claimed |
| `$CONFIG/sakura/setup.sh` | `res/setup.sh` | Shell environment setup after login |
| `$CONFIG/sakura/gettytab.example` | `res/sakura.gettytab` | Ready-made `/etc/gettytab` block |
| `$CONFIG/sakura/ttys.example` | `res/sakura.ttys` | Ready-made `/etc/ttys` line |
| `$CONFIG/sakura/example.dur` | `res/example.dur` | Default `dur_file_path` |
| `$CONFIG/sakura/example.lua` | `res/example.lua` | Default `lua_animation_file` |
| `$CONFIG/sakura/pixel_sakura.gif` | `res/pixel_sakura.gif` | Default wallpaper |
| `$CONFIG/sakura/lang/*.ini` | `res/lang/` | 25 locales, enumerated in `install.zig` |
| `$CONFIG/sakura/custom-sessions/README` | `res/custom-sessions/README` | Desktop-entry key reference |
| `$CONFIG/pam.d/sakura` | `res/pam.d/sakura` | Normal login policy |
| `$CONFIG/pam.d/sakura-autologin` | `res/pam.d/sakura-autologin` | Autologin policy (`pam_permit`) |

Substitution tokens `$PREFIX_DIRECTORY`, `$CONFIG_DIRECTORY`, `$EXECUTABLE_NAME`,
`$WRAPPER_NAME`, `$TTY_DEVICE`, `$DEFAULT_TTY` are patched in by `install.zig` at install
time. **Any example path written inside a comment is subject to the same substitution**,
which is what caused B2: upstream comments carrying `/usr`-relative example paths were
silently re-pointed to `/usr/local` rather than reviewed. B2 is fixed; the hazard is
permanent and applies to any future prefix change.

## 6. Wallpaper Rendering Contract

This is the fork's headline feature and the source of several cross-file invariants.

- The vt(4) console stores a colour in **three bits plus a brightness bit** — sixteen
  colours. True 24-bit output is not possible.
- Each cell is matched against the source at 2×2 resolution. Two glyph families compete:
  - **Quadrant patterns** (15 entries, `src/animations/Gif.zig:46-60`): U+2580, U+2584,
    U+2588, U+258C, U+2590, U+2596, U+2597, U+2598, U+2599, U+259A, U+259B, U+259C,
    U+259D, U+259E, U+259F — two flat colours placed spatially.
  - **Shades** (3 entries, `src/animations/Gif.zig:66-68`): U+2591 (0.444), U+2592
    (0.500), U+2593 (0.667) — two colours dithered to fake an absent tone.
- Mixing is penalised in proportion to colour distance (`gif_stipple`), relaxed where the
  source is strongly chromatic.
- Frames are decoded on demand and cached after first pass.

**Invariant:** the glyph set above is referenced in four places that must agree —
`Gif.zig`, `tools/mkvtfont.py` (`BLOCKS` synthesis + `SUBSET` range), `readme.md` (font
requirements), and any console font the user loads. Three of those four had drifted, which
is what C1–C3 were; all three are fixed and the first three are now enforced by
`tools/check_invariants.py` in CI.

**Second invariant, added after C5:** the glyphs must also be synthesised at the *cell*
size, and for a fixed-cell console font the cell is the BDF `FONTBOUNDINGBOX`, not the
source face's advance. `mkvtfont.py` restates every glyph's `DWIDTH` to the cell for this
reason. This is geometry rather than glyph coverage, so `check_invariants.py` does not
cover it.

**The stock fonts already satisfy the contract — verified 2026-08-29 (D-012).** The
mapping tables of every font FreeBSD 15.1 ships in `/usr/share/vt/fonts` were decoded and
checked against the 18 codepoints above:

| Font | Cell | Halves/full | Quadrants | Shades |
| --- | --- | --- | --- | --- |
| `spleen-12x24` | 12x24 | 5/5 | 10/10 | 3/3 |
| `spleen-16x32` | 16x32 | 5/5 | 10/10 | 3/3 |
| `spleen-8x16` | 8x16 | 5/5 | 10/10 | 3/3 |
| `gallant` | 12x22 | 5/5 | 10/10 | 3/3 |
| `terminus-b32` | 16x32 | 5/5 | 10/10 | 3/3 |

So **the wallpaper renders on a stock FreeBSD install with no font work at all.**
`tools/mkvtfont.py` exists for users who want their *own* font on the console, and is not a
prerequisite for the feature. The readme currently implies the opposite — TODOS V14.

## 7. Configuration Contract

- `src/config/Config.zig` holds the field set and built-in defaults (94 fields).
- `res/config.ini` is both the shipped config **and** the primary user documentation.
- `src/config/Lang.zig` holds 82 UI strings; `res/lang/*.ini` override them per locale.
- `src/config/migrator.zig` accepts legacy Ly configs: renames (`ly_log` → `sakura_log`,
  `min_refresh_delta` → `animation_frame_delay`, `blank_password` → `clear_password`),
  type changes (integer → enum), and drops options with no FreeBSD equivalent
  (`login_defs_path`, `battery_id`). `sleep_*`/`hibernate_*` are folded into custom binds.

**Invariant:** `Config.zig` field set ≡ `config.ini` key set (verified 94/94, both
directions), and `Lang.zig` key set ≡ every `res/lang/*.ini` key set (verified 82/82 across
**all 25 locales**; the 24 that were missing `err_gif` were completed by C4). Values match
too, with one deliberate exception documented in place: `start_cmd` is `null` in
`Config.zig` and points at `startup.sh` in the shipped file.

Both are enforced by `tools/check_invariants.py`.

**Note on `Lang`:** `main.zig:1223-1224` reflects over `@typeInfo(Lang).@"struct".fields`
to expose every key as a `$<key>` substitution in custom keybind names, and
`config.ini:485-487` documents that to users. Every field is therefore reachable, and no
`Lang` field can be treated as dead on the strength of a static grep — see D-007.

## 8. Implementation Registry

This is the registry `AGENTS.md` names as step 3 of the TODOS lifecycle
(backlog → active list → registry). A TODO is recorded here once it is implemented **and**
verified; the evidence column is what was actually run, not what was intended. Working
detail stays in PROGRESS.md; this is the durable index.

| ID | Implemented | Verified by |
| --- | --- | --- |
| A1 | Ly logo replaced by a sakura blossom in `res/example.dur` | 22/22 checks against `DurFile.zig:validate()`; container name now `sakura-blossom.dur` |
| A2 | `res/setup.sh` licence reference corrected to `license.md` | grep: no `the LICENSE file` remains |
| B1 | `res/config.ini:1-4` restated for the vt(4) sixteen-colour reality | grep: no `24-bit true color` claim remains |
| B2 | `res/config.ini` session-directory examples no longer expand to `/usr/local/local/…` | grep: no `$PREFIX_DIRECTORY/local/` remains |
| C1 | `mkvtfont.py` docstring rewritten for the quadrant+shade renderer | matches `Gif.zig:45-68` |
| C2 | `mkvtfont.py` synthesises 18 glyphs, up from 8 | 8 prior predicates byte-identical over 5 cell sizes; tiling algebra holds; 18/18 in an end-to-end BDF |
| C3 | `readme.md` font requirement lists every glyph the renderer emits | cross-checked against `Gif.zig` |
| C4 | `err_gif` translated into all 24 remaining locales | 82/82 × 25 via `check_invariants.py` |
| C5 | `mkvtfont.py` restates `DWIDTH` to the cell width | 8/8 fonts build, previously 0/6; Hurmit reports `advance fixed 0` |
| D1 | Stale `# default: 0.5` comments removed; box-position comments corrected to top/left origin | read against `main.zig:2288-2291` |
| D2 | `Config.zig` doom defaults aligned to the shipped palette | defaults diff: only `start_cmd` diverges |
| D3 | `start_cmd` divergence documented in place | as above |
| E1 | Install table 6 → 14 rows | matches `install.zig` |
| E2 | Clone URL filled in | matches `git remote` |
| E3 | "Migrating from Ly" section | written from `migrator.zig` |
| E4 | `contributing.md` restored for this fork | — |
| E5 | `.github/workflows/ci.yml` + `tools/check_invariants.py` | checker negative-tested; actions pinned to verified SHAs |
| E6 | All eight `animation` values and `-c/--config` documented | `--config` semantics read from `main.zig:185-230` |
| F1 | `res/pixel_sakura_static.png` removed | verified unreferenced before removal |
| F3 | CLI version string capitalisation matched to the UI | `sakura --version` → `Sakura version 1.0.0` |

**v1 readiness — executed 2026-08-29 (D-013):**

| ID | Implemented | Verified by |
| --- | --- | --- |
| P1 | `build.zig.zon` `.paths` names both path dependencies, as subpaths | `zig fetch --debug-hash .`: 89 files, both trees present, 0 cache/vendor leakage (was 92 without them, 1037 with them listed as directories) |
| P2 | `ports/` — `Makefile`, `pkg-descr`, `pkg-plist`, `pkg-message` | Written against `/usr/ports/Mk/Uses/zig.mk` and `devel/zls` as reference |
| P3 | `pkg-plist` — 14 entries + 25 locales, config files as `@sample` | Derived from `install.zig`, matches §5 |
| P4 | gettytab/ttys steps carried as `pkg-message`, install and remove | Read from `res/sakura.gettytab`, `res/sakura.ttys` |
| P5 | All nine `-D` build options documented in a readme table | Read from `build.zig:56-70` |
| P6 | Dependency line split into build / runtime / session / optional | `pkgconf` confirmed on this host, D-012 |
| P7 | `vendor.tar.zst` **not** tracked; added to `.gitignore` | USER ruling D-013 — reverses D-011 #3 |
| P8 | `create_vendor_tarball.sh` header added, scoped as offline-only | — |
| P9 | LuaJIT and `translate_c` 0.0.0 named in `ZIG_TUPLE` | Resolved from the fetched `zig-pkg/` trees, not from manifests |
| V1–V11, V14 | readme extended with autologin, keys and vi mode, corner widgets, custom binds, appearance, language, clock/status, sessions, CLI reference, troubleshooting, reference signposts, and the stock-font correction | 94/94 options covered: 75 named verbatim, 19 by prefix row, 0 uncovered |
| V12 | `res/config.ini` autologin comment tokenised to `$PREFIX_DIRECTORY` | Now expands to the same paths as `:451`/`:475` |
| V13 | `main.zig` `--config` help names `/usr/local/etc/sakura` | — |

**Not implemented, deliberately:**

| ID | Disposition |
| --- | --- |
| F2 | **Cancelled.** The 13 strings are reachable by reflection and documented to users. Removing them would have deleted a feature — see D-007. |

## 9. Distribution Topology

Added 2026-08-29 (D-011). The target is `pkg install sakura`. There are three distinct
notions of "the package" here and they are not the same thing; conflating them is what
produced the defect in §9.1.

| Layer | Defined by | Consumed by |
| --- | --- | --- |
| **Zig package** | `build.zig.zon` `.paths` | `zig fetch`, and any distfile derived from it |
| **Installed tree** | `install.zig` | `zig build installexe`, and `pkg-plist` |
| **FreeBSD package** | `ports/` *(does not exist yet)* | `pkg install sakura` |

### 9.1 The `.paths` invariant

**`build.zig.zon` `.paths` must contain every path dependency the same file declares.**
It currently declares `sakura_ui = .{ .path = "sakura-ui" }` and
`sakura_core = .{ .path = "../sakura-core" }` while listing neither directory, so the
package the manifest describes does not build.

Verified 2026-08-29: `zig fetch --debug-hash .` emits 92 files, none under `sakura-ui/` or
`sakura-core/`; a tree reconstructed from exactly the declared paths fails at configure
time with `unable to open '…/sakura-ui': FileNotFound`.

**FIXED 2026-08-29 (D-013), with a correction to the obvious remedy.**

This is a standing invariant, not a one-off: any future path dependency must be added in
both places. It is not covered by `check_invariants.py`.

**Add path dependencies as their source subpaths, never as the directory.** `.paths` does
**not** honour `.gitignore`. Listing `sakura-ui` and `sakura-core` wholesale pulled
`.zig-cache/` and the vendored `zig-pkg/` trees into the package — 1037 files, of which
roughly 30 were source, shipping machine-specific build cache and a duplicate of every
dependency the port fetches separately. The correct form names
`<dep>/build.zig`, `<dep>/build.zig.zon` and `<dep>/src`, mirroring what each
sub-manifest already declares for itself. Verified: 89 files, zero leakage.

`license.md` belongs in `.paths` for a separate reason — BSD 2-Clause requires the notice
to accompany redistributions, and a Zig package is a redistribution.

### 9.2 Staging

`install.zig` prefixes every write with `dest_directory`, supplied by `-Ddest_directory`
(`build.zig:56`). That is a complete `DESTDIR` equivalent and is what a port build binds
to. It works; it is documented nowhere.

The installer resolves its **sources** through `std.Io.Dir.cwd()`, so `zig build installexe`
must be invoked from the project root. A ports build in `WRKSRC` satisfies this naturally.

### 9.3 Where the post-install instructions live

`install.zig:56-67` prints the `/etc/gettytab` and `/etc/ttys` steps to stdout at the end of
an install. **Sakura does not run until those two steps are done**, so for a package install
the message must also exist as `pkg-message` — stdout from a `pkg install` is not read.

### 9.4 How the port obtains dependencies

**Ordinary distfiles — USER ruling D-013, reversing D-011 #3.** `ports/Makefile` uses
`USES=zig` and lists all nine Zig dependencies in `ZIG_TUPLE` as
`name:url:package-hash-directory`. The ports framework fetches each one like any other
distfile and `zig.mk` places them where Zig's `--system` mode resolves them. Regenerate
with `make make-zig-tuple` (needs `ports-mgmt/zig2tuple`) after any dependency change.

Two entries appear in no manifest a reader would think to check: **LuaJIT**, pulled in
lazily beneath `zlua` because the build requests `.lang = .luajit`, and a **second
`translate_c` at 0.0.0**, which is `zlua`'s own copy distinct from the 1.0.0 that
`sakura-ui` and `sakura-core` use. Both were resolved from the fetched `zig-pkg/` trees.

`create_vendor_tarball.sh` archives `zig-pkg`, `sakura-ui/zig-pkg` and
`sakura-core/zig-pkg` into `vendor.tar.zst`. It is retained as a convenience for
air-gapped builds and is **not** part of the packaging path; `vendor.tar.zst` is
gitignored.

### 9.5 Why the port defines its own `do-install`

`install.zig:117` reads the built binary from the literal relative path
`zig-out/bin/sakura`, not from Zig's `--prefix`. `USES=zig` passes `--prefix ${PREFIX}`
by default, which would write outside the stage directory *and* break that read. The port
therefore supplies its own `do-install` that omits `--prefix`, letting Zig's install step
land in `${WRKSRC}/zig-out`, and stages through `-Ddest_directory=${STAGEDIR}`.

`zig.mk`'s default `do-install` would also run the default `zig build` step, which
installs only the binary — not the configuration, language files, PAM policies or getty
wrapper, all of which `installexe` places.

### 9.6 What a port does not need

Consequence of §4: no helper binaries for power, VT switching or keyboard LEDs, so no
`RUN_DEPENDS` for those. No `rc.d` script — Sakura is started by `getty(8)` from
`/etc/ttys`, not by the service framework. `xorg`/`xorg-xauth` are needed only by X11
sessions, not by Sakura itself.
