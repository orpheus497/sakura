# PLANS

Forward-looking strategy for items scoped out of DECISIONS_LOG that are not yet
implemented. Last updated: 2026-08-24 10:17.

**Nothing is currently pending.** The one plan below has been fully executed; it is kept
as a historical record of the reasoning, not as outstanding work.

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
