# BLUEPRINT — Sakura System Architecture

Last updated: 2026-08-24 08:48

## 1. Product Identity

Sakura is a lightweight TUI display manager built **exclusively for FreeBSD**. It is a
platform-narrowed fork of [Ly](https://codeberg.org/fairyglade/ly) (the Fairy Glade). The
fork's two defining departures from upstream are:

1. **FreeBSD-only.** `build.zig` refuses any other target. All console, power-management
   and account handling goes through native interfaces rather than a portability layer.
2. **Animated GIF wallpaper.** The default `animation` is `gif`, rendered onto the vt(4)
   console with quadrant and shade glyphs.

Project licence: WTFPL (`license.md`). See DECISIONS_LOG entry D-004 regarding the
interaction between this and Directive 2.

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

> NOTE: The FOSS clause in `AGENTS.md` names `pango` and `cairo` as permitted LGPL
> exceptions "per the project's build configuration and README.md". Sakura uses neither
> and has no graphics-toolkit dependency at all. See DECISIONS_LOG D-003.

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
which is the root cause of TODO B2.

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
requirements), and any console font the user loads. TODO C1–C3 exist because three of
those four drifted.

## 7. Configuration Contract

- `src/config/Config.zig` holds the field set and built-in defaults (94 fields).
- `res/config.ini` is both the shipped config **and** the primary user documentation.
- `src/config/Lang.zig` holds 82 UI strings; `res/lang/*.ini` override them per locale.
- `src/config/migrator.zig` accepts legacy Ly configs: renames (`ly_log` → `sakura_log`,
  `min_refresh_delta` → `animation_frame_delay`, `blank_password` → `clear_password`),
  type changes (integer → enum), and drops options with no FreeBSD equivalent
  (`login_defs_path`, `battery_id`). `sleep_*`/`hibernate_*` are folded into custom binds.

**Invariant:** `Config.zig` field set ≡ `config.ini` key set (verified 94/94, both
directions), and `Lang.zig` key set ≡ every `res/lang/*.ini` key set (verified 82/82 for
`en`; 24 locales are one key short — TODO C4).
