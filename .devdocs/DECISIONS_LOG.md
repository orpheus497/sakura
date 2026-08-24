# DECISIONS LOG

Ledger of architectural and structural decisions, clarified ambiguity, and USER-provided
TODOs scoped into detail. Most recent at top.

---

## D-007 — The 13 "orphan" language strings are not orphans; F2 cancelled
**2026-08-24 09:55 — RESOLVED, no action taken**

TODOS F2 proposed deleting 13 `Lang` strings that no code path appeared to emit
(`err_config`, `err_mlock`, `err_null`, `err_bounds`, `err_domain`, `err_dgn_oob`,
`err_chdir`, `err_perm_group`, `err_perm_user`, `err_xsessions_dir`, `err_xsessions_open`,
`err_sleep`, `err_hibernate`). USER approved the removal, gated on verifying they were no
longer needed.

**They are needed.** `src/main.zig:1223-1224` does an `inline for` over
`@typeInfo(Lang).@"struct".fields` and replaces `$<field>` in every custom keybind name
with that field's value. Every one of the 82 keys is therefore reachable. This is not
incidental: `res/config.ini:485-487` documents it to users — *"'$' in '$brightness_up'
fetches the appropriate string from the specified locale file … You can see the list of
keys in any locale file"* — and `migrator.zig:314-330` relies on it when folding Ly's
`sleep_key`/`hibernate_key` into custom binds.

Deleting them would have broken documented behaviour and removed a feature, contrary to
Directive 3. **No strings were removed.**

**Method note worth carrying forward.** The original finding came from a static grep for
`lang.<key>` and `"<key>"`. That is not sound for a struct consumed by compile-time
reflection: `@typeInfo`/`@field` makes every field reachable without any of them appearing
as a literal. Before declaring any field of a Zig struct dead, check whether the struct is
reflected over. Only `Lang` is, via that one site.

---

## D-006 — Block synthesis was keyed to the wrong width
**2026-08-24 09:17 raised · 09:47 RESOLVED — approved, fixed, verified**

Discovered while verifying C2 end-to-end. `tools/mkvtfont.py` emits synthesised glyphs at
the `FONTBOUNDINGBOX` width, but a console tiles cells at the *advance* width (`DWIDTH`).
`FONTBOUNDINGBOX` is the union of all glyph extents, so it is normally **wider** than the
advance. Result: `vtfontcvt` rejects the file, and the readme's "Console font" workflow
produces nothing. Six of six monospace fonts tested mismatch — see TODOS C5 for the table.

**Structural point worth recording.** This is the third instance of the same root cause
already noted in D-001: the wallpaper's tiling contract is expressed in four places and
they drift. C1/C2/C3 fixed *which* glyphs are synthesised; C5 is about *what size* they are
synthesised at. Both are the tool disagreeing with the renderer about how a cell tiles.
BLUEPRINT §6's invariant should be extended to cover cell geometry, not just the glyph set.

**RESOLVED 2026-08-24 09:47 — approved by USER and fixed. The remedy first proposed was
wrong.**

I proposed synthesising at the advance width. Testing both directions against `vtfontcvt`
showed the opposite: normalising `DWIDTH` up to the bounding-box width is accepted, while
shrinking `FONTBOUNDINGBOX` down to the advance fails, because the glyphs whose overhang
created the mismatch then no longer fit. The bounding box **is** the console cell, so the
existing synthesis width was correct all along and only the advance was wrong.

Recorded because the reasoning generalises: for a fixed-cell console font the cell is the
bounding box, and a source face's own advance is not authoritative. Do not "fix" a width
disagreement by shrinking the box.

Verified: 8 of 8 monospace fonts build, previously 0 of 6.

---

## D-005 — Code Documentation Standards: scope of application
**2026-08-24 08:48 — OPEN, needs USER ruling**

`AGENTS.md` mandates `Script function and purpose:` / `Function purpose:` /
`Action purpose:` prefixes, and for shell scripts placement directly beneath the shebang.
It simultaneously states: *"DO NOT retroactively add commenting unless explicitly
requested by the user."*

The remediation backlog touches five shell/Python files that predate the standard
(`res/setup.sh`, `res/startup.sh`, `res/sakura-wrapper`, `tools/mkvtfont.py`,
`res/lang/normalize_lang_files.py`). None carry the mandated prefixes.

**Reading applied unless overruled:** the prohibition wins. I will bring *existing*
comments into line where a TODO already requires editing them (C1's docstring rewrite,
B1/B2's comment corrections), but will **not** add new `Script function and purpose:`
headers to files the backlog does not otherwise touch.
- Q: Do you want a separate, explicit pass to bring all scripts up to the standard?

---

## D-004 — Project licence (WTFPL) vs Directive 2
**2026-08-24 08:48 — RESOLVED, no action**

Directive 2 constrains **dependencies** to permissive non-copyleft (MIT/BSD). Sakura's own
licence is WTFPL (`license.md`), inherited from Ly. WTFPL is permissive and non-copyleft,
and in any case the directive governs dependencies, not the project's own terms. All ten
dependencies verified MIT or BSD on 2026-08-24 (BLUEPRINT §3). **Compliant.** No change
proposed; `readme.md:340` correctly states the fork retains upstream's licence.

---

## D-003 — `AGENTS.md` FOSS clause names dependencies this project does not have
**2026-08-24 08:48 — OPEN, needs USER ruling**

Directive 2 permits `pango` (LGPL-2.1) and `cairo` (LGPL-2.1 / MPL-1.1) *"as required
graphics/text rendering dependencies per the project's build configuration and README.md"*.

Sakura has **neither**, and no graphics toolkit at all — it is a vt(4) console program
whose entire render path is termbox2 over the FreeBSD console driver. `readme.md:9-11`
explicitly states it "does not depend on a graphical toolkit, a session bus, or a
login-manager framework." The clause appears to have been authored for a different
project in `~/Projects/`.

**Reading applied unless overruled:** the exception is inert here. It grants permission
that is never exercised, and does not license introducing pango/cairo into Sakura.
- Q: Should `AGENTS.md` be amended for this repo? Note it sits at the repo root and is
  **untracked** — see D-002.

---

## D-002 — `AGENTS.md` is untracked and lives in the product root
**2026-08-24 08:48 — OPEN, needs USER ruling**

`AGENTS.md` is present at the repo root but absent from `git ls-files`, and `.gitignore`
does not name it. It is therefore untracked-and-unignored: invisible to clones, and liable
to be swept up by an unqualified `git add`.

This also interacts with Directive 4 (*"Product code resides in the root directory. All AI
process, planning, and tracking documentation must reside exclusively within
`.devdocs/`"*). `AGENTS.md` is process documentation sitting in the product root.

**Reading applied unless overruled:** left exactly as found. It is the governing
directive file and moving it would be a self-modifying act taken without approval.
- Q1: Track it, ignore it, or leave it untracked?
- Q2: Should `.devdocs/` itself be committed or added to `.gitignore`?

---

## D-001 — Post-rebrand documentation audit
**2026-08-24 08:48 — COMPLETE**

USER requested verification that all documentation and details were updated to the Sakura
branding and the FreeBSD-only / GIF-wallpaper focus.

**Method.** Five independent cross-checks rather than a text search for the old name:
1. Every `Config.zig` field **and its default value** against `res/config.ini`.
2. Every `Lang.zig` key against all 25 locale files.
3. Every readme claim against `build.zig`, `install.zig`, `interop.zig`.
4. Every glyph the GIF renderer emits against the font tool documented to produce them.
5. The rebrand diff (`f38fae8`) against what its own surrounding comments still say.

**Outcome.** The rebrand is substantially complete — name-level conversion is clean and
the readme's system-call claims all hold. 20 defects remain, recorded in TODOS.md, of
which one ships upstream artwork (A1), two contradict the FreeBSD premise inside the
shipped config (B1, B2), and three under-deliver on the wallpaper feature the fork is
built around (C1–C3).

**Key structural insight, recorded because it caused two separate defects:**
`install.zig` performs `$PREFIX_DIRECTORY` / `$CONFIG_DIRECTORY` substitution across the
*whole* file, comments included. Upstream's prefix was `/usr`; Sakura's is `/usr/local`.
Any upstream comment containing an example path was therefore silently re-pointed rather
than reviewed. B2 is the surviving instance. Any future prefix change must re-audit
comment text, not just values.

**Second structural insight:** the wallpaper glyph set is duplicated across four
locations (BLUEPRINT §6). Three drifted. This is a standing invariant, not a one-off bug,
and warrants a check rather than a one-time fix.

---

## D-000 — Rebrand to Sakura
**Pre-dates this log — commit `f38fae8`, recorded for continuity**

Ly → Sakura; platform narrowed to FreeBSD only; `animation` default changed `none` → `gif`;
theme inverted to dark ink on light (`bg` `0x00000000` → `0x00FFFFFF`, `fg` `0x00FFFFFF` →
`0x20000000`) to sit on the cherry-blossom wallpaper; login box repositioned (0.5/0.5 →
0.30/0.62); `box_title` `null` → `sakura`; brightness moved from `brightnessctl` to
FreeBSD `backlight(8)`; `PATH` reordered to FreeBSD convention; `battery_id` (Linux sysfs)
replaced by `battery_sysctl` (sysctl MIB); `contributing.md` and `.github/FUNDING.yml`
deleted. Upstream attribution deliberately retained at `readme.md:331-340`.
