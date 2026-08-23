const std = @import("std");
const build_options = @import("build_options");

// The range of UIDs Sakura considers to be "regular" user accounts. FreeBSD
// has no /etc/login.defs, so the bounds come from the values baked into the
// binary at build time (see the -Duid_min and -Duid_max build options), which
// default to the ones pw(8) uses (see /usr/src/usr.sbin/pw/pw_conf.c).
uid_min: std.posix.uid_t = build_options.uid_min,
uid_max: std.posix.uid_t = build_options.uid_max,
