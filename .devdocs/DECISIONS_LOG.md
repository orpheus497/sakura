# DECISIONS LOG

Ledger of architectural and structural decisions, clarified ambiguity, and USER-provided
TODOs scoped into detail. Most recent at top.

---

## D-013 — A normal package: distfiles, not a vendored blob
**2026-08-29 09:39 — RESOLVED by USER instruction; v1 plan executed**

USER: *"proceed - i want this to be a normal pkg not something complicated"*.

### The ruling, and what it overturned

**`vendor.tar.zst` is NOT tracked.** This reverses D-011 #3, which had ruled it
tracked so the port could build offline. A normal FreeBSD port fetches its
dependencies as ordinary distfiles, and the framework already has the mechanism:
`USES=zig` plus a `ZIG_TUPLE` list, with each Zig dependency named as a distfile that
`make fetch` retrieves like any other. No blob in the repository, no offline
special-casing.

`create_vendor_tarball.sh` stays — nothing is deleted — but is now documented for what
it actually is: an optional convenience for air-gapped builds, explicitly *not* the
port's dependency mechanism. `vendor.tar.zst` was added to `.gitignore`, which
previously did not name it, so it cannot be committed by accident.

### The packaging mechanism, verified against the ports tree on this host

`/usr/ports/Mk/Uses/zig.mk` exists and `lang/zig` is **0.16.0**, matching
`minimum_zig_version` exactly. `devel/zls` was read as the reference implementation of
a Zig port. Every dependency was resolved from the fetched packages in `zig-pkg/`
rather than guessed — including the two a reader would not find in any manifest:
**LuaJIT**, which arrives lazily beneath `zlua` because the build requests
`.lang = .luajit`, and a **second `translate_c` (0.0.0)**, which is `zlua`'s own copy
alongside the 1.0.0 that `sakura-ui` and `sakura-core` use. Nine tuples in total.

### Two findings that changed the plan as written

**1. `.paths` does not honour `.gitignore`.** PLANS Part 1 said to add `sakura-ui` and
`sakura-core` to `build.zig.zon`'s `.paths`. Done literally, that swept `.zig-cache/`
and the vendored `zig-pkg/` trees into the package: **1037 files, of which about 30
were source.** The distfile would have shipped machine-specific build cache and a
duplicate of every dependency the port fetches separately.

The fix is to name the subpaths individually — `sakura-ui/build.zig`,
`sakura-ui/build.zig.zon`, `sakura-ui/src`, and the same three for `sakura-core` —
mirroring what the sub-manifests already do for themselves. Result: **89 files, zero
cache or vendor leakage**, both path dependencies present with their full source.

Recorded as an extension of the BLUEPRINT §9.1 invariant: a path dependency must be
added to `.paths`, and it must be added *as its source subpaths*, never as the
directory.

**2. `install.zig:117` hardcodes `zig-out/bin/sakura`.** The installer reads the built
binary from that literal relative path, not from Zig's `--prefix`. `USES=zig` passes
`--prefix ${PREFIX}` by default, which would both write outside the stage directory and
break that read. The port therefore defines its own `do-install` and deliberately does
not pass `--prefix`, letting Zig's install step land in `${WRKSRC}/zig-out` where
`install.zig` expects it. This is commented in `ports/Makefile` because it is precisely
the kind of thing a later edit would "clean up" and break.

### Package layout decisions

Configuration files the administrator edits — `config.ini`, `startup.sh`, `setup.sh`
and both PAM policies — are installed as `.sample` and materialised by pkg on first
install only, so an upgrade cannot overwrite an edited file. `config.ini.example` stays
a plain file: it is the pristine reference the readme points at.

No `rc.d` script: Sakura is started by `getty(8)` from `/etc/ttys`. No `RUN_DEPENDS`
for power, VT switching or LEDs, all of which are syscalls (§4). `xorg`/`xorg-xauth`
are needed by X11 *sessions*, not by Sakura, and are deliberately not run dependencies.

### One thing the port cannot do yet, stated plainly

`USE_GITHUB` with `DISTVERSIONPREFIX=v` and `DISTVERSION=1.0.0` fetches the `v1.0.0`
tag. **No tag exists**, and D-011 #7 rules tags out of scope. The port is written ready
for the tag and cannot fetch until one is cut. `distinfo` is likewise absent by design —
it is always generated with `make makesum`, never hand-written, and doing so requires
the tag to exist first.

---

## D-012 — The development host IS FreeBSD; every recurring question is closed
**2026-08-29 09:21 — RESOLVED by verification and USER instruction**

USER: *"p6q1 - what the fuck are you talking about we are on freebsd - youre in a
linuxculator"*, and *"all these questions have me responding why the fuck are you talking
about, we need to resolve them before anything, im sick of them coming up every session"*.

### The root cause of the recurrence

Sessions ran `uname -s`, read `Linux`, and concluded that anything platform-specific
"needs a FreeBSD box". **The host is FreeBSD.** `uname -a` reports:

```
Linux cyronetics 5.15.0 FreeBSD 15.1-RELEASE releng/15.1-n283562-96841ea08dcf GENERIC x86_64
```

That is the FreeBSD **linuxulator** (`/compat/linux` exists): a Linux userland running on a
FreeBSD 15.1-RELEASE kernel, with the host's `/usr/local` and `/usr/share` visible. It was
already recorded once, at PROGRESS 2026-08-24 10:00, and later sessions did not carry it
forward.

**Standing fact for every future session: FreeBSD facts are verifiable here. Do not defer a
platform question to "a FreeBSD host".** `pkgconf`, `vtfontcvt`, `otf2bdf`, the ports tree
under `/usr/local`, and `/usr/share/vt/fonts` are all directly readable. The one genuine
limit is that `zig build` links against FreeBSD base headers unavailable from inside the
Linux userland — that, and only that, is what CI's FreeBSD VM is for.

### The two "unverifiable" facts, now verified

**1. `pkgconf` is required — CONFIRMED.** Closes TODOS **P6/Q1**.

| Check | Result |
| --- | --- |
| `pkgconf` binary | `/usr/local/bin/pkgconf` (also `/usr/local/bin/pkg-config`) |
| `xcb.pc` location | `/usr/local/libdata/pkgconfig/xcb.pc` — **not** `/usr/local/lib/pkgconfig` |
| `pkgconf --modversion xcb` | `1.17.0` |
| `pkgconf --cflags --libs xcb` | `-I/usr/local/include -L/usr/local/lib -lxcb` |
| `libxcb.so` | `/usr/local/lib/libxcb.so.1.1.0` |

`linkSystemLibrary("xcb")` resolves through pkg-config, the `.pc` file exists only in the
`libdata` path, and pkgconf reads it correctly. So `pkgconf` is a **build dependency**
whenever `-Denable_x11_support` is on. It is no longer an inference.

**2. The stock vt fonts already carry every wallpaper glyph — CONFIRMED.** Closes the
`spleen-12x24.fnt` question flagged in PLANS and BRIEFING.

The `.fnt` mapping tables were decoded directly (`VFNT0002` header, then
`glyph_count × howmany(w,8) × h` bitmap bytes, then `{src,dst,len}` map entries, all
big-endian) and checked against the 18 codepoints `Gif.zig` emits:

| Font | Cell | Halves/full | Quadrants | Shades |
| --- | --- | --- | --- | --- |
| `spleen-12x24.fnt` | 12x24 | 5/5 | 10/10 | 3/3 |
| `spleen-16x32.fnt` | 16x32 | 5/5 | 10/10 | 3/3 |
| `spleen-8x16.fnt` | 8x16 | 5/5 | 10/10 | 3/3 |
| `gallant.fnt` | 12x22 | 5/5 | 10/10 | 3/3 |
| `terminus-b32.fnt` | 16x32 | 5/5 | 10/10 | 3/3 |

**Consequence worth documenting to users:** the wallpaper works on a stock FreeBSD install
with no font build at all. `tools/mkvtfont.py` is for using *your own* font, not a
prerequisite. The readme currently implies otherwise. Folded into TODOS V14.

### Every previously-open question, closed

| ID | Was | Now |
| --- | --- | --- |
| D-005 | "needs USER ruling" | **Closed** — `AGENTS.md` already states the rule; there was never a question |
| D-009 Q1 | "OPEN: `res/setup.sh` provenance" | **Closed** — the carve-out *is* the disposition, taken at the time |
| D-010 Q1 | "OPEN: reciprocal cross-linking" | **Closed by USER** — the siblings link each other; other repos are not this repo's concern |
| D-011 Q1 | "OPEN: working-tree state of `tools/`" | **Closed by fact** — `git diff -- tools/` is empty |
| P6 Q1 | "needs a FreeBSD host" | **Closed** — verified above |
| spleen font | "needs a FreeBSD host" | **Closed** — verified above |

**There are now zero open questions in this repository.**

### The rule that prevents this recurring

Three of the six above were **already answered** when a later session re-tabled them. The
failure is a documentation convention: an answered question was left with the string
`OPEN` next to it, so the next session re-read it and re-asked.

1. **A question that has been answered is rewritten as its answer**, marked `CLOSED` with
   the date and the basis, and carries the words *"Do not re-table."* It is never left
   phrased as a question.
2. **A question whose answer is already written in `AGENTS.md` is not a question.** Apply
   the directive and move on.
3. **Nothing about another repository is ever an open item here.**
4. **Before writing "needs a FreeBSD host", run the check** — see the host fact above.
5. **Session briefings report outstanding *work*, not resolved history.** Closed decisions
   belong in this log, not in the briefing's blocker list.

---

## D-011 — v1 readiness: packaging, documentation scope, and the Python ruling
**2026-08-29 08:54 — RESOLVED by USER instruction**

USER directed a v1 readiness pass covering two things: that the user-facing documentation
is comprehensive enough for someone to install, configure and customise Sakura, and that
the packaging pulls in every dependency and installs the product as a whole.

### The goal, stated plainly by USER

**`pkg install sakura`.** Not a source-only install, not a Zig package for other Zig
projects. A FreeBSD port and package. Everything in PLANS.md's v1 section serves that.

### Rulings taken this session

| # | Question | USER ruling |
| --- | --- | --- |
| 1 | What does "pkgconfig" mean | A FreeBSD port so `pkg install sakura` works |
| 2 | Where does the port skeleton live | In this repository — there is no port yet, so it has to be created here |
| 3 | `vendor.tar.zst` tracked or ignored | **Tracked**, so the port builds without network |
| 4 | Readme split into `docs/` | **No.** One file. No new documentation folders |
| 5 | `res/config.ini` edit scope | It stays its own documentation — people edit it directly. Comment-only edits; the readme becomes the guide, not a duplicate |
| 6 | Man pages | Not for v1 |
| 7 | Tags and versions | **Out of scope entirely.** No tag, no edit to `sakura_version` or `build.zig.zon`'s `.version` |
| 8 | CI toolchain pinning | Leave alone |
| 9 | BRIEFING's unreachable commit SHAs | Leave alone |

### The overriding constraint

**Nothing is deleted.** USER: *"YOU DO NOT DELETE OR FUCK WITH ANYTHING"*, and
*"if there are py scripts that are necessary for the project obviously don't delete them"*.
This supersedes any earlier reading of Directive 3 as permitting removals, and it applies
to `contributing.md`, `tools/`, `res/lang/normalize_lang_files.py` and the CI workflow
alike. Every item in the v1 plan is an addition or a correction; none is a removal.

### Python provenance — the audit USER asked for

USER: *"I want to know what python is project related and what is shit you created"*, and
separately: *"I am getting sick of finding folders in my repos called tools or docs that you
make of your own volition"*. Three Python files exist. Determined from `git log`, not
assumed:

| File | Introduced | Verdict |
| --- | --- | --- |
| `res/lang/normalize_lang_files.py` | `06e2839`, 2024-10-12, **Moritz Reinel** | **Project.** Upstream Ly, predates the fork by ~2 years. Reorders all 25 locale files to match `Lang.zig`'s field order, leaving a blank line for missing translations. `src/config/Lang.zig:2` points at it. Upstream removed it once and reverted (`7a82b51`). |
| `tools/mkvtfont.py` | `f38fae8`, 2026-08-23 — the rebrand commit | **Project.** Added in the same commit as `Gif.zig`, `gif/decoder.zig` and `pixel_sakura.gif`. It exists to serve the wallpaper: it patches the zero-sized glyphs `otf2bdf` emits, restates every `DWIDTH` to the cell so `vtfontcvt` accepts the file, and synthesises the 15 quadrants and 3 shades at exact cell size so the image does not band. Documented as a user workflow at `readme.md:381-401`. |
| `tools/check_invariants.py` | `4a3cdbd`, 2026-08-24 | **Agent-created.** Added in the process-scaffolding commit alongside `AGENTS.md`, `.devdocs/`, `.coderabbit.yaml`, `.github/workflows/ci.yml` and the restored `contributing.md`. Its stated purpose is catching what *"a rebrand or a rename quietly breaks"* — it verifies agent-introduced drift, not product behaviour. `ci.yml` exists only to run it. |

Upstream Ly at the fork point (`db7f8ac`) contained exactly one Python file and **no
`tools/` directory**. The directory is this fork's.

**Coupling worth knowing:** `check_invariants.py`'s fourth check reads `mkvtfont.py`
directly, and `ci.yml` depends on `check_invariants.py`. `mkvtfont.py` depends on neither
and stands alone.

**No disposition is taken on any of the three.** They stay. Recorded so the question is
never re-asked.

### A process failure recorded against a prior session

TODOS item **E4** classified the absence of `contributing.md` as a defect —
*"No `contributing.md` — deleted in `f38fae8`"* — and restored the file. That deletion was
deliberate: D-000 records it as an intentional part of the rebrand, and USER confirmed this
session that they *"keep deleting it as trash"*. A USER decision was logged as a bug and
reversed without being asked about.

**Rule going forward:** a file that a USER commit deliberately removed is not a defect for
its absence. Before recording a missing file as a finding, check whether its removal was
intentional in the commit that removed it. Per the no-deletion constraint above,
`contributing.md` is nonetheless left in place.

### Q1 — CLOSED 2026-08-29 09:21 by fact. Do not re-table.

`tools/check_invariants.py` and `tools/mkvtfont.py` were momentarily deleted in the working
tree during session 004. **They are present and identical to HEAD** — verified:
`git diff -- tools/` is empty and both files are on disk. `ci.yml:18` and
`readme.md:108,384,391` resolve. There is nothing here for any session to act on or ask
about.

---

## D-010 — Sakura is documented as the login layer of the Sakura desktop
**2026-08-27 — RESOLVED by USER instruction**

USER established the framing that the readme had never carried: Sakura is not only a
standalone Ly fork but the first of **three components of one Wayland desktop environment
targeting FreeBSD**, and the naming of the other two is a lineage rooted in this
repository.

| Component | Repository | Layer | Licence |
| --- | --- | --- | --- |
| Sakura | `orpheus497/sakura` | Login — TUI display manager on `vt(4)`, OpenPAM | BSD 2-Clause |
| hikari-sakura | `orpheus497/hikari-sakura` | Compositor — stacking Wayland + tiling, wlroots 0.20 | BSD 2-Clause |
| Sofi | `orpheus497/sofi` | Shell — `zwlr_layer_shell_v1` surfaces, one binary | MIT/X11 |

**The naming lineage, as stated by USER.** Sakura was named first. hikari-sakura takes
*hikari* from the compositor it forks (`antaz/hikari`, originally `raichoo`, abandoned
upstream) and *sakura* from this display manager — the second half of the name is what
marks it as part of this desktop. Sofi is a hard fork of rofi and swaps rofi's leading
**r** for the **S** of Sakura. Each name therefore keeps what it came from and carries
Sakura's mark for what it became part of.

**Verification.** Every integration claim added to `readme.md` was checked against the
sibling working copies at `/home/orpheus497/Projects/{hikari-sakura,sofi}` rather than
asserted:

| Claim | Verified against |
| --- | --- |
| `hikari.desktop` lands in Sakura's default `waylandsessions` path | `hikari-sakura/share/wayland-sessions/hikari.desktop` (`Name=Hikari Sakura`, `Exec=start-hikari`) vs `res/config.ini:451` (`$PREFIX_DIRECTORY/share/wayland-sessions`) |
| `start-hikari` is the correct entry point, not `hikari` | `hikari-sakura/start-hikari.sh` — creates/validates `XDG_RUNTIME_DIR`, clears leaked `WAYLAND_DISPLAY`/`DISPLAY`, wraps in `dbus-run-session` |
| Sofi's daemons belong in hikari's autostart, not Sakura's `setup.sh` | `hikari-sakura/share/man/man1/hikari.1:195` (`~/.config/hikari/autostart`); `sofi/README.md` §Autostart |
| Sofi's on-demand surfaces need no autostart | `hikari-sakura/etc/hikari/hikari.conf:449-452` already binds `sofi -show drun/window/sheets/notification-history` |
| Licences of both siblings | `hikari-sakura/LICENSE` (BSD 2-Clause + raichoo upstream notice), `sofi/COPYING` (MIT/X11 + rofi + simpleswitcher) |
| FreeBSD Wayland prerequisites | `hikari-sakura/README.md` — `kern.evdev.rcpt_mask`, `XDG_RUNTIME_DIR` must not be on ZFS |

**Two claims deliberately made negative**, because both are plausible mistakes a reader
would otherwise make:

1. **`setup.sh` is the wrong place for Sofi's daemons.** It runs before the compositor
   exists, so a layer-shell client started there has nothing to bind to.
2. **`x_vt` does not apply to hikari-sakura.** That option exists because Xorg and the
   console fight over a shared virtual terminal; a Wayland compositor takes the terminal
   cleanly.

**Independence is stated explicitly.** The readme says in the opening that Sakura depends
on neither sibling and launches any session another login manager would. The desktop is an
option, not a requirement — this keeps the ecosystem framing from reading as a new
dependency.

**Files changed.** `readme.md` only, per USER's scope ruling: opening rewritten to lead
with the desktop, new §*The Sakura desktop* (component table, naming lineage, six-step
runtime hand-off), new §*Running hikari-sakura* under Sessions, and Credits/License
extended with sibling provenance. `contributing.md`, the `.github/` templates and `res/`
were offered and **declined** for this pass — see PLANS.md.

**Q1 — CLOSED 2026-08-29 by USER. Do not re-table.** USER states the sibling repositories
link each other, and that cross-repository content is not this repository's concern. The
observation that prompted it (hikari-sakura's readme naming "GDM, SDDM, greetd") describes
another repository's text and is therefore out of scope by definition. **No Sakura session
raises cross-repo linking again.**

---

## D-009 — Relicensed from WTFPL to BSD 2-Clause
**2026-08-25 — RESOLVED by USER instruction; one sub-question left open**

USER directed that the project licence become a BSD licence. Chosen variant: **BSD
2-Clause** (SPDX `BSD-2-Clause`), the "Simplified" or "FreeBSD" licence — the same one
FreeBSD itself uses, which fits a FreeBSD-only project and is the shortest permissive form.
Copyright line: `Copyright (c) 2026 orpheus497`.

**Why this is permissible.** Sakura inherits its groundwork from Ly, which is WTFPL. WTFPL
grants unrestricted permission ("You just DO WHAT THE FUCK YOU WANT TO"), which includes
redistribution under different terms. Relicensing the inherited work to BSD 2-Clause is
therefore within the grant, and no permission from upstream is required. Note the direction
of travel: BSD is *more* restrictive than WTFPL, adding an attribution requirement and a
warranty disclaimer that WTFPL has neither of. Nothing downstream loses a right it held.

**Files changed.**

| File | Change |
| --- | --- |
| `license.md` | WTFPL text replaced with BSD 2-Clause, plus a third-party components section |
| `readme.md` | License section rewritten; states BSD 2-Clause and names both carve-outs |
| `.devdocs/BLUEPRINT.md` §1 | Project licence line updated |
| `.devdocs/BRIEFING.md` | D-004 note corrected, D-009 recorded |

No source file carries a licence header, so no code changed. `build.zig.zon` has no
`license` field in the Zig 0.16 manifest schema, so there is nothing to update there.

**Two carve-outs, both stated in `license.md`.**
1. Bundled dependencies keep their own licences (MIT/BSD). Unchanged by this decision.
2. `res/setup.sh` keeps its existing notice and is explicitly excluded from the BSD grant.

**Q1 — CLOSED 2026-08-29. Accepted and documented; do not re-table.** The disposition was
already taken when this entry was written — USER elected to leave the header untouched and
`license.md` carves the file out. That is route 3 of the three listed below, and it is the
shipped position. Nothing further is required of any session. The background follows as the
record of *why* the carve-out exists, not as an outstanding question.

**Background — `res/setup.sh` provenance.** The file's header records three copyrights:
Oswald Buddenhagen (2001-2005, *"extracted from kde-workspace, `kdm/kfrontend/genkdmconf.c`"*),
Pier Luigi Fiorini (2015-2016), and The Fairy Glade (2024) — and upstream labels the result
WTFPL. kde-workspace/KDM was GPL-2.0-or-later. That WTFPL label is therefore an upstream
relicensing decision whose basis cannot be verified from inside this repo, and if it is
unsound the file would be GPL-derived, which Directive 2 prohibits outright.

**Action taken:** USER elected to leave the file's header untouched rather than compound an
unverifiable upstream call. `license.md` carves it out explicitly, so the BSD grant does not
assert terms over code that may not be ours to relicense. This is the conservative position
and is safe to ship.

**Knock-on fixed.** `res/setup.sh:11` reads *"See license.md for more details"* — a pointer
that the relicence would have left dangling, since `license.md` no longer contains WTFPL
terms. Rather than edit the file (which the ruling excluded), the carve-out in `license.md`
names the WTFPL and links to its canonical text, so the pointer resolves again. The full
WTFPL was briefly inlined instead and then removed: at ~18 added lines against 24 lines of
BSD text it would likely have pushed `license.md` below the similarity threshold GitHub's
`licensee` uses, costing the repo its `BSD-2-Clause` detection and badge. The short note
keeps detection intact and still answers the reader's question.

Three routes existed. **Route 3 was taken and Q1 is closed on it:**
1. Confirm the upstream relicensing was authorised by the original authors; or
2. Replace `res/setup.sh` with an original implementation; or
3. **← TAKEN.** Accept and document the file as separately licensed under its stated terms.
   This is the current and final state.

---

## D-008 — The in-tree version must always lead the newest git tag
**2026-08-25 — RECORDED, constrains the v1.0.0 release**

`build.zig:getVersionStr` derives the version string reported by `sakura --version` from
`git describe --match "*.*.*" --tags`, and branches on how many hyphens the result has:

| `git describe` | Meaning | Behaviour |
| --- | --- | --- |
| *fails* | no tag reachable | returns `sakura_version` verbatim |
| `1.0.0` | HEAD **is** the tag | must equal `sakura_version`, else `exit(1)` |
| `1.0.0-4-gabc1234` | 4 commits past the tag | tagged ancestor must be **strictly less than** `sakura_version`, else `exit(1)` |

The third row is the trap. With `sakura_version = 1.0.0` in `build.zig:22` and a `v1.0.0`
tag in place, the very next commit produces `1.0.0-1-g…`, whose ancestor `1.0.0` is not
less than `1.0.0` — so `zig build` calls `std.process.exit(1)` and the tree stops building
for everyone until the version is bumped. This is inherited upstream behaviour: it encodes
the convention that the tree version names the *next* release, not the last one.

**Release sequence for v1.0.0:**
1. Tag the release commit while `sakura_version` still reads `1.0.0` — at that commit
   `git describe` yields exactly `1.0.0` and the equality branch passes.
2. Immediately bump `sakura_version` in `build.zig:22` **and** `.version` in
   `build.zig.zon:3` to `1.0.1` (or `1.1.0`), and commit.
3. From then on `sakura --version` reports `1.0.1-dev.N+<hash>`, which is the format the
   bug-report template's placeholder already shows.

Both files must move together; `build.zig.zon` is not read by `getVersionStr`, so a
mismatch will not fail the build and would silently misreport the package version.

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
**2026-08-24 08:48 raised · 2026-08-29 09:21 — CLOSED. Do not re-table.**

**There was never a question here.** `AGENTS.md` states the rule outright:
*"DO NOT retroactively add commenting unless explicitly requested by the user."*
That is the answer. No ruling was needed and none is to be requested again.

**Settled behaviour:** existing comments are brought into line only when a task already
requires editing them. `Script function and purpose:` / `Function purpose:` /
`Action purpose:` headers are added to **new** code and to files being written, never
retrofitted onto untouched ones. The ~100 Zig and shell sources that predate the standard
stay as they are.

The original framing is kept below as the record of what was mis-tabled.

---

**Original framing (mis-tabled as an open question):**

`AGENTS.md` mandates `Script function and purpose:` / `Function purpose:` /
`Action purpose:` prefixes, and for shell scripts placement directly beneath the shebang.
It simultaneously states: *"DO NOT retroactively add commenting unless explicitly
requested by the user."*

The remediation backlog touches five shell/Python files that predate the standard
(`res/setup.sh`, `res/startup.sh`, `res/sakura-wrapper`, `tools/mkvtfont.py`,
`res/lang/normalize_lang_files.py`). None carry the mandated prefixes.

Reading applied, and now the closed position: the prohibition wins. Existing comments are
brought into line where a task already requires editing them (C1's docstring rewrite,
B1/B2's comment corrections); new `Script function and purpose:` headers are **not** added
to files a task does not otherwise touch.

---

## D-004 — Project licence (WTFPL) vs Directive 2
**2026-08-24 08:48 — RESOLVED, no action · 2026-08-25 — SUPERSEDED IN PART by D-009**

Directive 2 constrains **dependencies** to permissive non-copyleft (MIT/BSD). Sakura's own
licence is WTFPL (`license.md`), inherited from Ly. WTFPL is permissive and non-copyleft,
and in any case the directive governs dependencies, not the project's own terms. All ten
dependencies verified MIT or BSD on 2026-08-24 (BLUEPRINT §3). **Compliant.** No change
proposed; `readme.md:340` correctly states the fork retains upstream's licence.

**Superseded in part (2026-08-25).** The dependency finding stands unchanged — all ten are
still MIT or BSD. The premise that the project's own licence is WTFPL does not: it is now
BSD 2-Clause. See D-009.

---

## D-003 — `AGENTS.md` FOSS clause names dependencies this project does not have
**2026-08-24 08:48 — RAISED · 2026-08-25 — RESOLVED by USER ruling**

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

**USER ruling (2026-08-25, v1 readiness pass):** drop the exception. Directive 2 now reads
as an unqualified MIT/BSD-only rule with no LGPL carve-out. All ten dependencies already
comply (see D-004), so nothing in the tree changes as a consequence — this removes stale
text authored for a different project, and with it the dangling `README.md` reference (this
repo's readme is lowercase `readme.md`). Introducing pango or cairo into Sakura now
requires a fresh directive, not an inherited allowance.

---

## D-002 — `AGENTS.md` is untracked and lives in the product root
**2026-08-24 08:48 — RAISED · 2026-08-25 — RESOLVED by USER ruling**

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

**USER ruling (2026-08-25, v1 readiness pass):** keep both tracked. `AGENTS.md` stays at
the repo root and `.devdocs/` stays committed, both public. Directive 4's separation of
concerns is satisfied by `.devdocs/` holding the process documentation; `AGENTS.md` is the
governing directive file itself and is conventionally root-level, so it is exempt rather
than in violation. `.coderabbit.yaml` continues to exclude `.devdocs/**` from review.

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
