// Script function and purpose: the platform boundary. Everything that differs
// between FreeBSD and Linux lives behind this one file, and nothing outside
// src/interop/ may import a platform-specific C header.
//
// The dispatch selects a *file*, not a struct of function pointers or a
// type-returning function, so each platform's implementation is free to take
// exactly the parameters its own kernel needs. Two of them genuinely differ --
// see `getUserIdRange` below -- and forcing a shared signature would mean
// FreeBSD carrying arguments it never reads.
//
// `builtin.target.os.tag`, not `builtin.os.tag`: the latter is deprecated in
// Zig 0.17.0 and removed in 0.18.0.

const std = @import("std");
const builtin = @import("builtin");

const UidRange = @import("UidRange.zig");

// Action purpose: The other BSDs compile the FreeBSD implementation rather than
// being turned away. FreeBSD 15.0+ is what this is written and tested against,
// and nothing here claims NetBSD, OpenBSD or DragonFly works -- but refusing to
// build on them taught a porter nothing. Pointed at this file they get real
// errors naming the pieces that do not fit, which on DragonFly is little and on
// the wscons systems is the console layer, and that is a starting point rather
// than a closed door. Anything that is not a BSD or Linux still stops here,
// because there is no implementation it could sensibly be given.
const impl = switch (builtin.target.os.tag) {
    .freebsd, .netbsd, .openbsd, .dragonfly => @import("interop/freebsd.zig"),
    .linux => @import("interop/linux.zig"),
    else => @compileError("no interop layer for " ++ @tagName(builtin.target.os.tag) ++
        "; Sakura targets FreeBSD 15.0+ and Linux. Add src/interop/<os>.zig and a case here to port it."),
};

/// True when the FreeBSD implementation is the one compiled in -- which also
/// covers the untested BSDs above, since they share it and must therefore share
/// its behaviour. Call sites use this rather than re-deriving the target, so
/// adding a platform touches one file.
pub const is_freebsd = switch (builtin.target.os.tag) {
    .freebsd, .netbsd, .openbsd, .dragonfly => true,
    else => false,
};

// Translated C headers that application code legitimately reaches into. The
// platform-only ones -- sysctl, kbio, consio on FreeBSD; kd, vt, grp on Linux
// -- are deliberately absent: they stay private to the implementation files so
// a FreeBSD-only header cannot be referenced from src/.
pub const pam = impl.pam;
pub const utmp = impl.utmp;
pub const xcb = impl.xcb;

pub const TimeOfDay = impl.TimeOfDay;
pub const UsernameEntry = impl.UsernameEntry;

pub const isError = impl.isError;
pub const supportsUnicode = impl.supportsUnicode;
pub const timeAsString = impl.timeAsString;
pub const getTimeOfDay = impl.getTimeOfDay;

pub const getActiveTty = impl.getActiveTty;
pub const ttyDeviceName = impl.ttyDeviceName;
pub const ttyDeviceNameZ = impl.ttyDeviceNameZ;
pub const switchTty = impl.switchTty;

pub const getLockState = impl.getLockState;
pub const setNumlock = impl.setNumlock;

pub const setUserContext = impl.setUserContext;
pub const setUserShell = impl.setUserShell;
pub const setEnvironmentVariable = impl.setEnvironmentVariable;
pub const putEnvironmentVariable = impl.putEnvironmentVariable;

pub const getNextUsernameEntry = impl.getNextUsernameEntry;
pub const getUsernameEntry = impl.getUsernameEntry;
pub const closePasswordDatabase = impl.closePasswordDatabase;

pub const getBatteryPercentage = impl.getBatteryPercentage;
pub const shutdownSystem = impl.shutdownSystem;
pub const rebootSystem = impl.rebootSystem;

/// Function purpose: hide the one genuine signature divergence in the boundary.
///
/// FreeBSD has no /etc/login.defs, so its range is the pair baked in at build
/// time and the call needs nothing. Linux reads UID_MIN/UID_MAX out of a file,
/// so it needs an allocator, an `std.Io`, and the configurable path. Rather
/// than give FreeBSD three parameters it discards -- which is what the
/// pre-fork tree did -- the branch lives here and the call site passes what it
/// has.
pub fn getUserIdRange(
    allocator: std.mem.Allocator,
    io: std.Io,
    login_defs_path: ?[]const u8,
) UidRange {
    if (is_freebsd) return impl.getUserIdRange();
    return impl.getUserIdRange(allocator, io, login_defs_path orelse return .{});
}
