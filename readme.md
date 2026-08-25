# The Sakura display manager

![Sakura screenshot](.github/screenshot.png "Sakura screenshot")

_Note: Sakura ships with an animated wallpaper, drawn on the console with
half-block characters. See [The wallpaper](#the-wallpaper) below._

Sakura is a lightweight TUI (ncurses-like) display manager built exclusively
for FreeBSD. It runs on a virtual terminal, talks to OpenPAM directly, and does
not depend on a graphical toolkit, a session bus, or a login-manager framework.

Sakura only targets FreeBSD. The build refuses any other target on purpose: all
the console, power-management and account handling goes through FreeBSD
interfaces (`vt(4)`, `kbio(4)`, `consio(4)`, `reboot(2)`, `setusercontext(3)`
and `sysctl(3)`) rather than through a portability layer.

## Dependencies

- Compile-time:
  - zig 0.16.x (you must use a **release version** of zig; check that
    `zig version` does not have a `-dev*` suffix)

  - libc and OpenPAM (both part of the FreeBSD base system)

  - xcb (optional, required by default; needed for X11 support)

- Runtime (with the default configuration):
  - xorg

  - xorg-xauth

  - `backlight(8)` (part of the base system, used for the brightness keybinds)

- Optional:
  - otf2bdf, only if you want to build a console font with `tools/mkvtfont.py`
    (`pkg install otf2bdf`; `vtfontcvt` is already in base)

Everything else Sakura needs — shutdown, reboot, virtual terminal switching and
the keyboard LEDs — is handled in-process through FreeBSD system calls, so no
helper binaries are required for those.

```
# pkg install zig git libxcb xorg xorg-xauth ca_root_nss
```

## Building

```
$ git clone https://github.com/orpheus497/sakura.git sakura
$ cd sakura
$ zig build
```

After building, you can (optionally) test Sakura in a terminal emulator,
although authentication will **not** work:

```
$ zig build run
```

> [!IMPORTANT]
> While you can run Sakura in a terminal emulator as root, it is **not**
> recommended. To properly test Sakura, install it, wire it up in `/etc/ttys`
> as described below, and reboot.

> [!NOTE]
> You can, however, test configuration file changes that way. Note that you
> must press Ctrl+C in order to exit Sakura.

## Installing

```
# zig build installexe
```

This installs:

| Path | Contents |
| --- | --- |
| `/usr/local/bin/sakura` | the display manager |
| `/usr/local/bin/sakura_wrapper` | the `getty(8)` wrapper (see below) |
| `/usr/local/etc/sakura/config.ini` | the configuration, with `config.ini.example` kept pristine beside it |
| `/usr/local/etc/sakura/pixel_sakura.gif` | the default wallpaper |
| `/usr/local/etc/sakura/startup.sh` | runs before the terminal is taken over (`start_cmd`) |
| `/usr/local/etc/sakura/setup.sh` | shell environment setup after login (`setup_cmd`) |
| `/usr/local/etc/sakura/gettytab.example` | the `/etc/gettytab` block, filled in (see below) |
| `/usr/local/etc/sakura/ttys.example` | the `/etc/ttys` line, filled in (see below) |
| `/usr/local/etc/sakura/example.dur` | the default `dur_file` animation |
| `/usr/local/etc/sakura/example.lua` | the example `lua` animation |
| `/usr/local/etc/sakura/lang/` | the 25 language files |
| `/usr/local/etc/sakura/custom-sessions/` | your own session entries, plus a `README` on the supported keys |
| `/usr/local/etc/pam.d/sakura` | the PAM policy used for normal logins |
| `/usr/local/etc/pam.d/sakura-autologin` | the PAM policy used for autologin |

The defaults follow the FreeBSD ports layout (`--prefix` is `/usr/local` and
the configuration lives under `/usr/local/etc`). Both can be overridden:

```
# zig build installexe -Dprefix_directory=/usr/local -Dconfig_directory=/usr/local/etc
```

If another display manager is currently enabled, disable it first. For example,
for LightDM:

```
# service lightdm stop
# sysrc lightdm_enable="NO"
```

## Enabling

FreeBSD starts a `getty(8)` on each virtual terminal listed in `/etc/ttys`.
Sakura replaces the login program on one of them. Both snippets below are
installed to `/usr/local/etc/sakura/` as `gettytab.example` and `ttys.example`,
already filled in with the paths you built with.

First, append the Sakura entry to `/etc/gettytab` (see `gettytab(5)`):

```
sakura:\
	:lo=/usr/local/bin/sakura_wrapper:\
	:al=root:
```

`lo` replaces `login(1)` with Sakura's wrapper, and `al` makes `getty` hand the
terminal over without prompting for a user name first.

> [!NOTE]
> The wrapper exists because `getty` appends `login -fp root` to the program
> named by `lo`, which Sakura does not accept. The wrapper drops those
> arguments and then executes Sakura.

Then point a virtual terminal at that entry in `/etc/ttys` (see `ttys(5)`).
FreeBSD numbers virtual terminals from 1 but names their device nodes from 0,
so virtual terminal 2 — Sakura's default — is `/dev/ttyv1`:

```
ttyv1	"/usr/libexec/getty sakura"	xterm	onifexists	secure
```

Finally, make `init(8)` re-read the file:

```
# kill -HUP 1
```

To run Sakura on a different virtual terminal, build with `-Ddefault_tty=N`
(which also adjusts the generated examples) and edit the matching `/etc/ttys`
line instead.

## Updating

You can install Sakura without overriding the current configuration file:

```
# zig build installnoconf
```

## Uninstalling

```
# zig build uninstallexe
```

`uninstallnoconf` does the same but keeps `/usr/local/etc/sakura`. Neither
touches `/etc/gettytab` or `/etc/ttys`, so remember to revert those by hand.

## Configuration

All configuration lives in `/usr/local/etc/sakura/config.ini`. The file is fully
commented and shows the value of every option, which is the built-in default
except where a comment says otherwise. A pristine copy is kept next to it as
`config.ini.example`.

You can check the validity of your configuration file (i.e. whether there are
any errors in it) with:

```
$ sakura --validate-config /usr/local/etc/sakura/config.ini
```

Logs are defined by that same file:

- The session log is at `~/.local/state/sakura-session.log` by default.

- The system log is at `/var/log/sakura.log` by default. If set to `null`,
  `syslog(3)` is used instead, under the `sakura` identifier.

`--config` (`-c`) takes a *directory*, not a file: Sakura reads `config.ini`
inside it, along with `lang/` and the save file. Without it, that directory is
`/usr/local/etc/sakura`, so the configuration is
`/usr/local/etc/sakura/config.ini`. Note that `--validate-config` differs — it
takes the path of the file itself.

### Migrating from Ly

An existing Ly configuration can be used as-is: Sakura migrates it on load, and
the same applies to a Ly save file. Nothing needs converting by hand, but it is
worth knowing what changes, because the migration is silent.

Renamed, with the old name still accepted:

| Ly | Sakura |
| --- | --- |
| `ly_log` | `sakura_log` |
| `min_refresh_delta` | `animation_frame_delay` |
| `blank_password` | `clear_password` |

Dropped, because they have no FreeBSD equivalent:

- `battery_id` — the Linux sysfs identifier. Use `battery_sysctl`, which takes a
  sysctl MIB such as `hw.acpi.battery.life`, instead.
- `login_defs_path` — `/etc/login.defs` is a Linux file. The UID range is fixed at
  build time with `-Duid_min` and `-Duid_max`.

Folded into other options: `sleep_key`/`sleep_cmd` and
`hibernate_key`/`hibernate_cmd` become custom keybinds, since FreeBSD has no
equivalent of the helpers Ly called. `animate` is folded into `animation`, and
`save`/`save_file` into `save_file_dir`.

Options that changed type — `animation`, `bigclock` and `default_input` moved
from integers to names, and the colour options from 16-bit codes to the
`0xSSRRGGBB` form — are converted for you. A configuration whose colours are all
old-style eight-colour codes is taken to predate true-colour support, so
`full_color` is turned off and the remaining colours are set to their
eight-colour equivalents rather than to Sakura's defaults.

Several Ly options no longer exist at all and are ignored if present:
`wayland_specifier`, `wayland_cmd`, `x_cmd_setup`, `mcookie_cmd`,
`term_reset_cmd`, `term_restore_cursor_cmd`, `console_dev`, `shutdown_cmd`,
`restart_cmd`, `load`, `max_desktop_len`, `max_login_len`, `max_password_len`,
`hide_key_hints`, `hide_keyboard_locks`, `hide_version_string` and `show_tty`.
Shutdown and restart are no longer commands because Sakura calls `reboot(2)`
directly.

## The wallpaper

Sakura draws an animated GIF behind the login box. The console has no
framebuffer, so every cell is painted as a block glyph carrying two colours.
Each cell is matched against the source at 2x2 resolution and the closer of two
families wins: the sixteen quadrant patterns, which place two flat colours
spatially, or the shades `U+2591/2/3`, which dither two colours to fake a tone
the console does not have.

That second family is what keeps any colour at all. A vt(4) console stores a
colour in three bits plus a brightness bit -- sixteen colours, no more -- so a
pastel has no flat equivalent and can only be approximated by mixing. Mixing
shows as visible stipple, so it is penalised in proportion to how far apart the
two colours are, and that penalty is relaxed where the source is strongly
coloured. A grey sky stays flat; a pink sun keeps its hue. `gif_stipple` sets
how hard the penalty bites.

Frames are decoded as the animation plays rather than up front, so startup
isn't delayed, and each frame is cached after its first pass.

The relevant options in `config.ini`:

| Option | Meaning |
| --- | --- |
| `animation` | `gif` by default; set to `none` to turn the wallpaper off |
| `gif_file` | which GIF to show |
| `gif_scaling` | `fill` (default), `fit`, `stretch` or `none` |
| `gif_font_aspect` | cell height divided by cell width; see below |
| `gif_stipple` | how readily two colours are dithered together (default `0.2`) |

To use your own wallpaper, drop any GIF87a/GIF89a file — animated or still — in
place of `/usr/local/etc/sakura/pixel_sakura.gif`, or point `gif_file` somewhere
else. Nothing needs rebuilding; log out and back in.

### Other backgrounds

`animation` selects what is drawn behind the login box. `gif` is the default and
everything above describes it, but the animations Sakura inherited from Ly are
all still available, each with its own `config.ini` options:

| `animation` | What it draws |
| --- | --- |
| `gif` | the animated wallpaper described above (default) |
| `none` | nothing; the plain background colour |
| `doom` | the PSX DOOM fire effect (`doom_*`) |
| `matrix` | falling CMatrix glyphs (`cmatrix_*`) |
| `colormix` | a slow three-colour shader (`colormix_*`) |
| `gameoflife` | Conway's Game of Life (`gameoflife_*`) |
| `dur_file` | a [durdraw](https://github.com/cmang/durdraw) animation (`dur_file_path`, `dur_*`) |
| `lua` | your own animation written in LuaJIT (`lua_animation_file`) |

`dur_file` defaults to the sakura blossom in
`/usr/local/etc/sakura/example.dur`, and `lua` to the bouncing squares in
`example.lua`, which is commented as a starting point for writing your own. Note
that a `.dur` file saved with a 256-colour range will not draw while
`full_color` is off.

> [!IMPORTANT]
> `gif_font_aspect` must match your console font or the image will look
> stretched. Set it to the cell's height divided by its width: `2.0` for an
> 8x16 or 12x24 font (the default), `17 / 7 = 2.43` for a 7x17 one.

The wallpaper's detail is set by how many cells the console has, so the console
font matters more than anything else here. On a 1920x1200 panel a 16x32 font
gives 120x37 cells, 12x24 gives 160x50, and 8x16 gives 240x75 — each step
roughly doubling the resolution at the cost of smaller text. The shipped
defaults are tuned for 12x24:

```
# sysrc allscreens_flags="-f /usr/share/vt/fonts/spleen-12x24.fnt"
```

## Console font

vt(4) only loads bitmap fonts, so a scalable font has to be rasterised first.
`tools/mkvtfont.py` does that, and also fixes up the two things that would
otherwise spoil the wallpaper: `vtfontcvt` rejects the zero-sized glyphs
`otf2bdf` emits for blanks, and block elements rasterised from outlines rarely
tile the character cell exactly, which bands the image. The block elements are
synthesised at the exact cell size instead.

```
$ python3 tools/mkvtfont.py -p 11 -o sakura-console.fnt \
    /usr/local/share/fonts/nerd-fonts/Hurmit/HurmitNerdFontMono-Regular.otf
# cp sakura-console.fnt /usr/share/vt/fonts/
```

Load it for the current session, or for every terminal at boot:

```
# vidcontrol -f /usr/share/vt/fonts/sakura-console.fnt < /dev/ttyv1
# sysrc allscreens_flags="-f /usr/share/vt/fonts/sakura-console.fnt"
```

Whatever font you choose must contain the box drawing characters
(U+2500-U+2518) that the interface is drawn with, and every glyph the wallpaper
is composed from, or the interface and the wallpaper will show gaps. The
wallpaper needs the halves and the full block (U+2580, U+2584, U+2588, U+258C,
U+2590), the quadrants (U+2596-U+259F) and the three shades (U+2591-U+2593).

No font is bundled: rasterising someone else's typeface and shipping the result
is a licensing question best left to whoever installs it.

## Controls

Use the Up/Down arrow keys to change the current field, and the Left/Right
arrow keys to scroll through the different values (whether it be the info line,
the desktop environment, or the username). The info line is where messages and
errors are displayed.

## Sessions

Every environment that works with other login managers should work with Sakura.

- Unlike most login managers, Sakura has an xinitrc and a shell entry.

- Sakura does not refresh itself, so a newly installed environment only shows
  up after Sakura restarts (log out, or reboot).

- If your environment is still missing, check `/usr/local/share/xsessions` or
  `/usr/local/share/wayland-sessions` for a `.desktop` file.

- If there is no `.desktop` file, create one in
  `/usr/local/etc/sakura/custom-sessions` that launches your environment. Those
  entries are only visible to Sakura; put them in the directories above instead
  if you want them system-wide. See the `README` in that directory for the
  supported keys.

### A note on X11

Handing Xorg the same virtual terminal Sakura runs on can make the console and
the X server fight over it. If X fails to start or the screen is left in a bad
state, point the `x_vt` option at a spare virtual terminal.

### A note on .xinitrc

If your `.xinitrc` file doesn't work, make sure it is executable and includes a
shebang. This file is supposed to be a shell script! Quoting from `xinit`'s man
page:

> If no specific client program is given on the command line, xinit will look
> for a file in the user's home directory called .xinitrc to run as a shell
> script to start up client programs.

A typical shebang for a shell script looks like this:

```
#!/bin/sh
```

## Tips

- The numlock and capslock states are printed in the top-right corner.

- Use the F1 and F2 keys to respectively shut down and reboot. These call
  `reboot(2)` directly, so no external helper is needed.

- Battery status is off by default. Set `battery_sysctl = hw.acpi.battery.life`
  to show it.

- The default colours are dark ink on a light box, to sit on the light
  wallpaper. Note that `0x00000000` means "the terminal's default colour", so
  black has to be asked for as `0x20000000` (the `TB_HI_BLACK` style bit).

- Take a look at your `.xsession` file if X doesn't start, as it can interfere
  (this file is launched with X to configure the display properly).

- Set `animation = none` if you would rather have a plain background; the
  wallpaper costs a few MB of memory and a little CPU while it plays.

- `/usr/local/etc/sakura/startup.sh` runs before Sakura takes control of the
  terminal, which is a good place for `vidcontrol(1)` tweaks such as loading a
  larger console font.

## Credits

Sakura is a FreeBSD-only fork of [Ly](https://codeberg.org/fairyglade/ly), the
TUI display manager by the Fairy Glade. All the groundwork — the TUI, the
animations, the session handling and the Zig rewrite — comes from Ly and its
contributors. Sakura narrows that work down to a single platform.

The theming is heavily inspired by
[sddm-astronaut-theme](https://github.com/Keyitdev/sddm-astronaut-theme), and the
default wallpaper `pixel_sakura.gif` comes directly from there.

## License

Sakura is released under the BSD 2-Clause License. See `license.md`.

Ly is released under the WTFPL, which permits redistribution under any terms,
so the inherited work is re-released here under BSD 2-Clause. Two exceptions
are noted in `license.md`: `res/setup.sh` keeps its own notice, and the bundled
dependencies keep their own licenses (MIT and BSD).
