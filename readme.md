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
$ git clone <your-clone-url> sakura
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
| `/usr/local/etc/sakura/` | configuration, language files, examples |
| `/usr/local/etc/sakura/pixel_sakura.gif` | the default wallpaper |
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

All configuration lives in `/usr/local/etc/sakura/config.ini`. The file is
fully commented and includes the default values. A pristine copy is kept next
to it as `config.ini.example`.

You can check the validity of your configuration file (i.e. whether there are
any errors in it) with:

```
$ sakura --validate-config /usr/local/etc/sakura/config.ini
```

Logs are defined by that same file:

- The session log is at `~/.local/state/sakura-session.log` by default.

- The system log is at `/var/log/sakura.log` by default. If set to `null`,
  `syslog(3)` is used instead, under the `sakura` identifier.

## The wallpaper

Sakura draws an animated GIF behind the login box. The console has no
framebuffer, so each character cell is painted as an upper half block
(U+2580): the foreground colour fills the top half of the cell and the
background the bottom, which gives one pixel per column and two per row. On a
1920x1200 panel with the default 8x16 console font that works out to a 240x150
pixel canvas.

Frames are decoded as the animation plays rather than up front, so startup
isn't delayed, and each frame is cached after its first pass.

The relevant options in `config.ini`:

| Option | Meaning |
| --- | --- |
| `animation` | `gif` by default; set to `none` to turn the wallpaper off |
| `gif_file` | which GIF to show |
| `gif_scaling` | `fit` (default), `fill`, `stretch` or `none` |
| `gif_font_aspect` | cell height divided by cell width; see below |

To use your own wallpaper, drop any GIF87a/GIF89a file — animated or still — in
place of `/usr/local/etc/sakura/pixel_sakura.gif`, or point `gif_file` somewhere
else. Nothing needs rebuilding; log out and back in.

> [!IMPORTANT]
> `gif_font_aspect` must match your console font or the image will look
> stretched. Half blocks are only square when a cell is exactly twice as tall
> as it is wide, which is true of the default 8x16 font (hence the `2.0`
> default). For any other font, set it to height divided by width — a 7x17 cell
> is `17 / 7 = 2.43`.

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
(U+2500-U+2518), the block elements (U+2580, U+2588) and the shade characters
(U+2593), or the interface and the wallpaper will show gaps.

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

## License

Sakura, like Ly, is released under the WTFPL. See `license.md`.
