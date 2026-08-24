# PLANS

Forward-looking strategy for items scoped out of DECISIONS_LOG that are not yet
implemented. Last updated: 2026-08-24 08:48.

**Status: awaiting approval.** Nothing here is authorised for execution. Per Directive 1
and Phase 1.4, execution halts until the USER approves.

---

## Remediation Plan — Post-Rebrand Documentation Defects

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
| F1 | `res/pixel_sakura_static.png` — **blocked on Directive 3**, needs explicit instruction |
| F2 | 13 orphan lang strings — **blocked on Directive 3**, needs explicit instruction |

---

## Standing Invariant Checks *(proposed, not scheduled)*

D-001 surfaced two invariants that drift silently. Worth automating rather than
re-auditing each session:

1. **Config/lang parity.** `Config.zig` field set ≡ `config.ini` key set; `Lang.zig` key
   set ≡ every locale's key set. Both are currently checkable in a few lines and both
   caught real defects (C4).
2. **Wallpaper glyph set.** `Gif.zig`'s codepoint tables ≡ `mkvtfont.py`'s `BLOCKS` ≡ the
   readme's stated requirement. Three of four drifted (C1–C3).

Natural home is Stage 4's CI job (E5).
