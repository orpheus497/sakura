# Contributing to Sakura

Sakura is developed at <https://github.com/orpheus497/sakura>. Open a pull
request there, using the template, and please read the rest of this file first.

Sakura is a FreeBSD-only fork of [Ly](https://codeberg.org/fairyglade/ly). If
your change is not FreeBSD-specific and would benefit Ly too, consider sending
it upstream as well — it will reach many more people there.

## Scope

The build refuses any target other than FreeBSD, and that is deliberate. Console
handling, power management and account handling all go through native interfaces
(`vt(4)`, `kbio(4)`, `consio(4)`, `reboot(2)`, `setusercontext(3)`, `sysctl(3)`)
rather than a portability layer. Changes that reintroduce a portability layer, or
that add a dependency on a graphical toolkit, a session bus or a login-manager
framework, are out of scope.

## Testing on FreeBSD

The pull request template asks you to confirm you tested on FreeBSD. Here is what
that means in practice.

`zig build run` starts Sakura in a terminal emulator, which is enough for
configuration and layout work, but **authentication will not work** there and you
must press Ctrl+C to get out. Anything touching `src/auth.zig`, session
launching, PAM, virtual terminals or power keys has to be tested on a real
console:

```
# zig build installexe
```

Then wire it up as described in the readme — append the block from
`/usr/local/etc/sakura/gettytab.example` to `/etc/gettytab`, replace the matching
line in `/etc/ttys` with the one from `ttys.example`, and run `kill -HUP 1`.
Switch to that virtual terminal and log in for real.

Keep a second, working way into the machine while you do this. A broken
`/etc/ttys` or a display manager that fails to start can leave you without a
console.

Useful while testing:

- `sakura --validate-config res/config.ini` checks a configuration file parses.
- The system log is at `/var/log/sakura.log`, the session log at
  `~/.local/state/sakura-session.log`.
- `zig build installnoconf` reinstalls without overwriting your configuration.

## Things that must stay in step

Some invariants span several files and are easy to break in one place only:

- **Configuration.** Every field in `src/config/Config.zig` must appear in
  `res/config.ini` with the same default, and vice versa. `res/config.ini` is the
  user-facing documentation as well as the shipped file.
- **Translations.** Every key in `src/config/Lang.zig` must exist in all 25 files
  in `res/lang/`. `res/lang/normalize_lang_files.py` reorders them to match and
  leaves a blank line where a translation is missing.
- **Wallpaper glyphs.** The codepoints in `src/animations/Gif.zig` must match what
  `tools/mkvtfont.py` synthesises and what the readme tells users their console
  font needs.
- **Installed files.** Anything added to `res/` needs a corresponding entry in
  `install.zig` and a row in the readme's install table. New language files must
  also be added to the list in `install.zig`.
- **Removed options.** If you rename or drop a configuration option, handle the
  old name in `src/config/migrator.zig` and note it in the readme's "Migrating
  from Ly" section.

## Code style

Follow Zig's [style guide](https://ziglang.org/documentation/master/#Style-Guide).
Running `zig fmt` covers most of it, but not naming or line length.

Keep lines to a maximum of **80 characters**. For calls with many arguments, a
trailing comma lets `zig fmt` split them across lines for you.

Comment only where the code is not self-explanatory, and explain *why* rather
than restating *what*. Do not add comments to existing code you are not otherwise
changing.

## Commits

1. **Write descriptive commit names.** Put the detail in the description if the
   name would get too long. No particular prefix or emoji convention is required.
2. **Do not force push.** Pull requests are squashed on merge anyway, and force
   pushing destroys the history of what changed during review.
3. **Consider signing your commits** with an SSH or GPG key.

## Reporting bugs

Use the issue template. It asks for `sakura --version`, `freebsd-version -kru`
and `uname -a`, your desktop environment, and the relevant logs. Please
reproduce against the default configuration first — a surprising number of
reports turn out to be a local `config.ini` change.
