#!/usr/bin/env python3
"""Check the cross-file invariants that a rebrand or a rename quietly breaks.

Each of these spans two or more files that have to agree, and each has been out
of step at least once. They are cheap to verify and need no FreeBSD, so CI can
run them on any host before spending a VM on the real build.

Exits non-zero on the first failing invariant, listing every discrepancy.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="UTF-8") as fh:
        return fh.read()


# Function purpose: report one invariant's outcome and remember any failure, so
# every invariant runs and the whole picture is reported in a single CI run
# rather than one failure per push.
FAILED = []


def check(name, missing_a, missing_b, label_a, label_b):
    if not missing_a and not missing_b:
        print("  ok    %s" % name)
        return
    print("  FAIL  %s" % name)
    if missing_a:
        print("          %s: %s" % (label_a, ", ".join(sorted(missing_a))))
    if missing_b:
        print("          %s: %s" % (label_b, ", ".join(sorted(missing_b))))
    FAILED.append(name)


def zig_fields(text):
    """Top-level `name: Type = default,` declarations, which is how both
    Config.zig and Lang.zig declare their field sets."""
    return {m.group(1) for m in re.finditer(r"^([a-z0-9_]+):", text, re.M)}


def ini_keys(text):
    return {m.group(1) for m in re.finditer(r"^([a-z0-9_]+)\s*=", text, re.M)}


print("Configuration: src/config/Config.zig <-> res/config.ini")
cfg = zig_fields(read("src", "config", "Config.zig"))
ini = ini_keys(read("res", "config.ini"))
check("every option is documented and every documented option exists",
      cfg - ini, ini - cfg, "in Config.zig but not config.ini",
      "in config.ini but not Config.zig")

print("Translations: src/config/Lang.zig <-> res/lang/*.ini")
lang = zig_fields(read("src", "config", "Lang.zig"))
locales = sorted(f for f in os.listdir(os.path.join(ROOT, "res", "lang"))
                 if f.endswith(".ini"))
for name in locales:
    keys = ini_keys(read("res", "lang", name))
    check("%s carries every Lang.zig key" % name,
          lang - keys, keys - lang, "missing", "unknown")

print("Installed files: res/lang/*.ini <-> install.zig")
# Action purpose: scope the search to the `languages` array. install.zig names
# config.ini and config.ini.example elsewhere, and a file-wide search picks those
# up and reports them as stray locales.
block = re.search(r"const languages = \[_\]\[\]const u8\{(.*?)\};",
                  read("install.zig"), re.S)
if block is None:
    sys.exit("error: could not find the `languages` array in install.zig")
listed = set(re.findall(r'"([A-Za-z_]+\.ini)"', block.group(1)))
check("every language file is installed",
      set(locales) - listed, listed - set(locales),
      "present but not installed", "installed but missing")

print("Wallpaper glyphs: src/animations/Gif.zig <-> tools/mkvtfont.py")
gif = {int(c, 16) for c in
       re.findall(r"\.codepoint = 0x([0-9A-Fa-f]{4})", read("src", "animations", "Gif.zig"))}
gif |= {int(c, 16) for c in
        re.findall(r"\.codepoint = 0x([0-9A-Fa-f]{4}), \.ratio", read("src", "animations", "Gif.zig"))}
mk = read("tools", "mkvtfont.py")
synth = {int(c, 16) for c in re.findall(r"^\s*0x([0-9A-Fa-f]{4}):", mk, re.M)}
# Action purpose: the space carries the empty pattern in Gif.zig but is blank by
# definition, so it is the one glyph the font tool must not synthesise.
need = gif - {0x20}
check("every glyph the renderer draws is synthesised cell-exact",
      {"U+%04X" % c for c in need - synth},
      {"U+%04X" % c for c in synth - need},
      "drawn but not synthesised", "synthesised but never drawn")

# Action purpose: an empty set on both sides satisfies every check above
# vacuously, so a broken regex would read as a pass. Assert the inputs were
# actually parsed before trusting the result.
for label, size, least in (("Config.zig fields", len(cfg), 50),
                           ("config.ini keys", len(ini), 50),
                           ("Lang.zig keys", len(lang), 50),
                           ("locale files", len(locales), 20),
                           ("installed locales", len(listed), 20),
                           ("Gif.zig codepoints", len(gif), 18),
                           ("synthesised glyphs", len(synth), 18)):
    if size < least:
        sys.exit("error: only parsed %d %s, expected at least %d -- the checker "
                 "is broken, not the tree" % (size, label, least))

if FAILED:
    print("\n%d invariant(s) broken." % len(FAILED))
    sys.exit(1)
print("\nAll invariants hold.")
