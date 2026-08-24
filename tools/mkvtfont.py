#!/usr/bin/env python3
"""Build a FreeBSD vt(4) console font for Sakura from a scalable font.

vt(4) only loads bitmap fonts, so an OTF/TTF has to be rasterised to BDF
(otf2bdf) and then converted to the vt font format (vtfontcvt, in base).

Three fixups happen in between, all of which matter for Sakura:

  * vtfontcvt rejects zero-sized glyphs, which otf2bdf emits for blanks.

  * vtfontcvt also rejects the file outright unless every glyph advances by the
    cell width. otf2bdf emits the source face's own advance, which is narrower
    than FONTBOUNDINGBOX whenever a glyph overhangs it, so the advance is
    restated as the cell. See rewrite() for why the box cannot shrink instead.

  * Sakura draws its wallpaper by matching each cell against the source at 2x2
    resolution and picking either one of the fifteen quadrant patterns (the
    quadrants, the halves and the full block) or one of the three shades, which
    dither two colours to fake a tone the sixteen-colour console lacks. That
    only reads as a continuous image if those glyphs tile the character cell
    exactly. Outlines rounded to a small pixel grid usually don't -- Hurmit at
    11pt leaves the top pixel row of every cell empty, which bands the whole
    image. All eighteen are geometric, so this script synthesises them at the
    exact cell size instead of trusting the rasteriser. (Gif.zig counts sixteen
    quadrant patterns; the sixteenth is the space, which needs no synthesising.)

    The glyph set here must stay in step with src/animations/Gif.zig:45-68.

Requires: otf2bdf (pkg install otf2bdf), vtfontcvt (base system).
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

# Codepoint ranges worth having on a console: ASCII, Latin-1, Latin Extended-A,
# Greek, Cyrillic (Sakura ships translations using all of these), a few
# punctuation marks, and the box drawing + block element ranges the UI draws
# with. Nerd Font icon glyphs are deliberately excluded: they are far wider
# than the text advance and would inflate the fixed cell size.
SUBSET = "32_126,160_255,256_383,880_1023,1024_1279,8211_8226,9472_9631"

# The fifteen quadrant patterns Gif.zig draws, as 2x2 masks over the cell.
# Bit weights: upper-left 8, upper-right 4, lower-left 2, lower-right 1 -- the
# same numbering Gif.zig:46-60 uses, so the two tables can be read side by side.
QUADRANTS = {
    0x2597: 0b0001,  # lower right
    0x2596: 0b0010,  # lower left
    0x2584: 0b0011,  # lower half
    0x259D: 0b0100,  # upper right
    0x2590: 0b0101,  # right half
    0x259E: 0b0110,  # upper right + lower left
    0x259F: 0b0111,
    0x2598: 0b1000,  # upper left
    0x259A: 0b1001,  # upper left + lower right
    0x258C: 0b1010,  # left half
    0x2599: 0b1011,
    0x2580: 0b1100,  # upper half
    0x259C: 0b1101,
    0x259B: 0b1110,
    0x2588: 0b1111,  # full block
}

# The three shades Gif.zig:66-68 dithers with, at roughly 44%, 50% and 67% ink.
SHADES = {
    0x2591: lambda x, y, w, h: (x + y * 2) % 4 == 0,       # light shade
    0x2592: lambda x, y, w, h: (x + y) % 2 == 0,           # medium shade
    0x2593: lambda x, y, w, h: (x + y * 2) % 4 != 0,       # dark shade
}


# Function purpose: turn a 2x2 quadrant mask into a per-pixel predicate, so all
# fifteen patterns come from one rule instead of fifteen hand-written lambdas
# that could drift out of agreement with each other or with Gif.zig.
def _quadrant(mask):
    def pred(x, y, w, h):
        top, left = y < (h + 1) // 2, x < (w + 1) // 2
        bit = 8 if (top and left) else 4 if top else 2 if left else 1
        return bool(mask & bit)
    return pred


# Block elements, as fractions of the cell. Each entry is a predicate over
# (x, y, w, h) deciding whether that pixel is inked.
BLOCKS = {cp: _quadrant(mask) for cp, mask in QUADRANTS.items()}
BLOCKS.update(SHADES)


def run(cmd, produces=None):
    """Run a tool. If `produces` is given, judge success by that file being
    written rather than by the exit status -- otf2bdf exits with the number of
    glyphs it warned about, which is not a failure."""
    proc = subprocess.run(cmd, capture_output=True, text=True)
    ok = (os.path.exists(produces) and os.path.getsize(produces) > 0) \
        if produces else proc.returncode == 0
    if not ok:
        sys.exit("error: %s failed (exit %d):\n%s"
                 % (cmd[0], proc.returncode, proc.stderr.strip() or proc.stdout.strip()))
    return proc.stdout


def parse_bbox(lines):
    for line in lines:
        if line.startswith("FONTBOUNDINGBOX"):
            return [int(v) for v in line.split()[1:]]
    sys.exit("error: BDF has no FONTBOUNDINGBOX")


def synth_bitmap(cp, w, h):
    """Render one block element as BDF hex rows covering the whole cell."""
    pred = BLOCKS[cp]
    stride = (w + 7) // 8 * 2
    rows = []
    for y in range(h):
        bits = 0
        for x in range(w):
            if pred(x, y, w, h):
                bits |= 1 << (w - 1 - x)
        # BDF pads each row out to a whole number of bytes, left aligned.
        bits <<= (w + 7) // 8 * 8 - w
        rows.append(("%0*X" % (stride, bits)))
    return rows


def rewrite(bdf_text):
    lines = bdf_text.split("\n")
    bw, bh, _bxo, byo = parse_bbox(lines)

    out = []
    i = 0
    blanks = 0
    synthed = 0
    widened = 0
    cell_advance = "DWIDTH %d 0" % bw
    while i < len(lines):
        line = lines[i]
        if not line.startswith("STARTCHAR"):
            out.append(line)
            i += 1
            continue

        # Buffer one whole glyph so it can be rewritten as a unit.
        start = i
        while i < len(lines) and lines[i] != "ENDCHAR":
            i += 1
        glyph = lines[start:i]
        i += 1  # step past ENDCHAR

        # Action purpose: a vt(4) font is fixed-cell, so every glyph has to advance
        # by the cell width, and the cell is FONTBOUNDINGBOX. otf2bdf instead emits
        # the source face's own advance, which is narrower whenever any glyph
        # overhangs it -- DejaVu Sans Mono at 12pt is 7 wide in a 10 wide box. That
        # disagreement makes vtfontcvt reject the entire file, so restate the
        # advance as the cell. Shrinking the box to match instead does not work:
        # the glyphs that caused the overhang no longer fit and vtfontcvt fails on
        # those.
        for n, g in enumerate(glyph):
            if g.startswith("DWIDTH "):
                if g.strip() != cell_advance:
                    widened += 1
                glyph[n] = cell_advance
                break

        enc = None
        for g in glyph:
            m = re.match(r"^ENCODING\s+(-?\d+)", g)
            if m:
                enc = int(m.group(1))
                break

        head = []
        for g in glyph:
            if g.startswith("BBX") or g == "BITMAP":
                break
            head.append(g)

        if enc in BLOCKS:
            # Replace the rasterised outline with an exact, cell-filling one.
            out.extend(head)
            out.append("BBX %d %d 0 %d" % (bw, bh, byo))
            out.append("BITMAP")
            out.extend(synth_bitmap(enc, bw, bh))
            out.append("ENDCHAR")
            synthed += 1
            continue

        body = glyph[len(head):]
        if body and body[0].startswith("BBX 0 0 0 0"):
            # vtfontcvt refuses empty glyphs; give it a 1x1 blank.
            out.extend(head)
            out.append("BBX 1 1 0 0")
            out.append("BITMAP")
            out.append("00")
            out.append("ENDCHAR")
            blanks += 1
            continue

        out.extend(glyph)
        out.append("ENDCHAR")

    return "\n".join(out), bw, bh, blanks, synthed, widened


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("font", help="source OTF/TTF (e.g. HurmitNerdFontMono-Regular.otf)")
    ap.add_argument("-p", "--pointsize", type=int, default=11,
                    help="point size at 72dpi, i.e. pixels (default: 11)")
    ap.add_argument("-o", "--output", default="sakura-console.fnt",
                    help="output vt font (default: sakura-console.fnt)")
    ap.add_argument("--keep-bdf", metavar="PATH",
                    help="also write the intermediate BDF here")
    args = ap.parse_args()

    for tool in ("otf2bdf", "vtfontcvt"):
        if shutil.which(tool) is None:
            sys.exit("error: %s not found (pkg install otf2bdf; vtfontcvt is in base)" % tool)
    if not os.path.exists(args.font):
        sys.exit("error: no such font: %s" % args.font)

    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "raw.bdf")
        fixed = os.path.join(tmp, "fixed.bdf")

        # -r 72 makes point size equal pixel size; -c C marks the font as
        # character-cell spaced, which vtfontcvt requires.
        run(["otf2bdf", "-r", "72", "-p", str(args.pointsize),
             "-c", "C", "-l", SUBSET, args.font, "-o", raw], produces=raw)

        with open(raw) as fh:
            text, bw, bh, blanks, synthed, widened = rewrite(fh.read())
        # Close before vtfontcvt reads it: relying on refcount finalisation to
        # flush is a CPython implementation detail.
        with open(fixed, "w") as fh:
            fh.write(text)
        if args.keep_bdf:
            shutil.copy(fixed, args.keep_bdf)

        run(["vtfontcvt", "-o", args.output, fixed], produces=args.output)

    print("wrote %s" % args.output)
    print("  cell            %dx%d px" % (bw, bh))
    print("  blanks patched  %d" % blanks)
    print("  blocks exact    %d" % synthed)
    print("  advance fixed   %d" % widened)
    print("  console grid    %dx%d at 1920x1200, %dx%d at 1920x1080"
          % (1920 // bw, 1200 // bh, 1920 // bw, 1080 // bh))


if __name__ == "__main__":
    main()
