PORTNAME=	sakura
DISTVERSIONPREFIX=	v
DISTVERSION=	1.0.0
CATEGORIES=	x11

MAINTAINER=	orpheus497@gmail.com
COMMENT=	TUI display manager for FreeBSD
WWW=		https://github.com/orpheus497/sakura

LICENSE=	BSD2CLAUSE
LICENSE_FILE=	${WRKSRC}/license.md

USES=		zig
USE_GITHUB=	yes
GH_ACCOUNT=	orpheus497

# Every Zig dependency, fetched by the ports framework as an ordinary distfile.
# Each entry is name:url-without-scheme:package-hash-directory. The hash
# directories are the ones Zig resolves in --system mode and must match the
# .hash fields in build.zig.zon, sakura-ui/build.zig.zon and
# sakura-core/build.zig.zon exactly.
#
# Regenerate with `make make-zig-tuple` (needs ports-mgmt/zig2tuple) after any
# dependency change; it may need running more than once to pull in transitive
# dependencies.
#
# Two entries are not named in any manifest a reader would think to check:
# luajit arrives lazily beneath zlua because the build requests .lang = .luajit,
# and translate_c 0.0.0 is zlua's own copy, distinct from the 1.0.0 that
# sakura-ui and sakura-core use.
ZIG_TUPLE=	clap:github.com/Hejsil/zig-clap/archive/fc1e5cc3f6d9d3001112385ee6256d694e959d2f.tar.gz:clap-0.11.0-oBajB7foAQC3Iyn4IVCkUdYaOVVng5IZkSncySTjNig1 \
		zlua:github.com/natecraddock/ziglua/archive/8f271c82baa5fc43aa02a72f6da020c2025d9436.tar.gz:zlua-0.1.0-hGRpC2aABQD4D9PBVH3wAW8k32-I4969MRQ0CpOwoley \
		luajit:github.com/LuaJIT/LuaJIT/archive/18b087cd2cd4ddc4a79782bf155383a689d5093d.tar.gz:N-V-__8AAODpQgCVrpfzE2ze9FA_rOuByh3WKyIyk5iS_o9a \
		termbox2:github.com/AnErrupTion/termbox2/archive/c7f241e8888ce243e1748b05c26a42fcfaaad936.tar.gz:N-V-__8AAAUXBQD6Fwpi9m0MBqWXFFaqW5l1lVrJC2Ynj7a- \
		zigini:github.com/AshAmetrine/zigini/archive/a665d081dda42664a96da2840ea09c5ccf9d0692.tar.gz:zigini-0.5.0-BSkB7e9WAACfyCBABNZiWL3gFMw18GKn3qBcPs8L1Ec1 \
		ini:github.com/AshAmetrine/ziglibs-ini/archive/3b733e10adc6c4c48050709b97a22258bc2e6156.tar.gz:ini-0.1.0-YCQ9YiwsAACghqF8LZyjAF2H_NnL6n29QLuCe0fsmPTo \
		translate_c:codeberg.org/ziglang/translate-c/archive/6fe0ffc4549f15c5f2d9432c2b4460ba90ff85ac.tar.gz:translate_c-1.0.0-Q_BUWo_5BgD4flHdUhA31zOz0XvZk9k7lQv1ouzyNXj2 \
		translate_c_zlua:codeberg.org/ziglang/translate-c/archive/46b5609b5ac4c0a896217d1d984f3ae50e4810b5.tar.gz:translate_c-0.0.0-Q_BUWpf0BgAwrh5AM-acJcslN_YPEhcoCVKbbNjwuUTJ \
		aro:github.com/Vexu/arocc/archive/5f5a050569a95ecc40a426f0c3666ae7ef987ede.tar.gz:aro-0.0.0-JSD1Qi7QNgDnfcrdEJf82v3o6MhZySjYVrtdfEf3E4Se

OPTIONS_DEFINE=		X11
OPTIONS_DEFAULT=	X11
X11_DESC=		Support X11 sessions (Wayland and console sessions work without it)

# Zig resolves linkSystemLibrary("xcb") through pkg-config, and xcb.pc lives in
# ${LOCALBASE}/libdata/pkgconfig, so pkgconf is a build dependency whenever this
# option is on.
X11_USES=		pkgconfig
X11_LIB_DEPENDS=	libxcb.so:x11/libxcb
X11_VARS=		SAKURA_X11=true
X11_VARS_OFF=		SAKURA_X11=false

# Sakura is started by getty(8) from /etc/ttys, not by the service framework, so
# there is no rc.d script. Power management, virtual-terminal switching and
# keyboard LEDs all go through FreeBSD syscalls, so there are no helper-binary
# run dependencies either. xorg and xorg-xauth are needed only by X11 sessions
# themselves, not by Sakura, and so are deliberately not RUN_DEPENDS.

# The bundled Zig installer is what places the configuration, the language
# files, both PAM policies and the getty wrapper, so the default `zig build`
# step that USES=zig would run is not enough on its own.
#
# Two details matter and are easy to get wrong:
#   1. --prefix is deliberately NOT passed. install.zig reads the built binary
#      from the literal relative path zig-out/bin/sakura, so Zig's own install
#      step must land in ${WRKSRC}/zig-out. Passing --prefix ${PREFIX} would
#      both break that read and write outside the stage directory.
#   2. -Ddest_directory is Sakura's DESTDIR equivalent; install.zig prefixes
#      every write with it.
do-install:
	@(cd ${WRKSRC} && ${SETENV} ${MAKE_ENV} ${ZIG_CMD} build installexe \
		--system ${ZIG_DEPSDIR} \
		-Doptimize=ReleaseSafe \
		-Dcpu=${ZIG_CPUTYPE} \
		-Ddest_directory=${STAGEDIR} \
		-Dprefix_directory=${PREFIX} \
		-Dconfig_directory=${PREFIX}/etc \
		-Denable_x11_support=${SAKURA_X11})

# The installer writes live configuration files. A package must not overwrite a
# file the administrator has edited, so the user-editable ones ship as .sample
# and pkg materialises them on first install only.
post-install:
	@${MV} ${STAGEDIR}${PREFIX}/etc/sakura/config.ini \
		${STAGEDIR}${PREFIX}/etc/sakura/config.ini.sample
	@${MV} ${STAGEDIR}${PREFIX}/etc/sakura/startup.sh \
		${STAGEDIR}${PREFIX}/etc/sakura/startup.sh.sample
	@${MV} ${STAGEDIR}${PREFIX}/etc/sakura/setup.sh \
		${STAGEDIR}${PREFIX}/etc/sakura/setup.sh.sample
	@${MV} ${STAGEDIR}${PREFIX}/etc/pam.d/sakura \
		${STAGEDIR}${PREFIX}/etc/pam.d/sakura.sample
	@${MV} ${STAGEDIR}${PREFIX}/etc/pam.d/sakura-autologin \
		${STAGEDIR}${PREFIX}/etc/pam.d/sakura-autologin.sample
	@${STRIP_CMD} ${STAGEDIR}${PREFIX}/bin/sakura

.include <bsd.port.mk>
