const std = @import("std");
const build_options = @import("build_options");
const UidRange = @import("UidRange.zig");
const consio = @import("consio");
const kbio = @import("kbio");
const pwd = @import("pwd");
const reboot = @import("reboot");
const stdlib = @import("stdlib");
const system_time = @import("system_time");
const time = @import("time");
const unistd = @import("unistd");

pub const pam = @import("pam");
pub const utmp = @import("utmp");
pub const sysctl = @import("sysctl");
// Exists for X11 support only, so it is only imported when X11 support was
// enabled at build time.
pub const xcb = if (build_options.enable_x11_support) @import("xcb") else struct {};

/// The FreeBSD console driver reports and sets the keyboard LEDs as an `int`
/// bit mask.
const LedState = c_int;

pub const TimeOfDay = struct {
    seconds: i64,
    microseconds: i64,
};

pub const UsernameEntry = struct {
    username: ?[]const u8,
    uid: std.posix.uid_t,
    gid: std.posix.gid_t,
    home: ?[]const u8,
    shell: ?[]const u8,
    passwd_struct: [*]pwd.passwd,
};

/// FreeBSD libc returns -1 on failure and sets errno, so a plain sign check is
/// all that is ever needed here.
pub fn isError(result: anytype) bool {
    comptime std.debug.assert(@typeInfo(@TypeOf(result)).int.signedness == .signed);
    return result < 0;
}

/// FreeBSD's vt(4) console is UTF-8 capable.
pub fn supportsUnicode() bool {
    return true;
}

pub fn timeAsString(io: std.Io, buf: [:0]u8, format: [:0]const u8) []u8 {
    const timer: isize = @intCast(std.Io.Timestamp.now(io, .real).toSeconds());
    const tm_info = time.localtime(&timer);
    const len = time.strftime(buf, buf.len, format, tm_info);

    return buf[0..len];
}

pub fn getTimeOfDay() !TimeOfDay {
    var tv: system_time.timeval = undefined;
    const status = system_time.gettimeofday(&tv, null);

    if (status != 0) return error.FailedToGetTimeOfDay;

    return .{
        .seconds = @intCast(tv.tv_sec),
        .microseconds = @intCast(tv.tv_usec),
    };
}

/// Returns the number of the virtual terminal this process is attached to.
/// FreeBSD numbers virtual terminals starting at 1, while the device nodes
/// backing them start at 0: VT 1 is /dev/ttyv0, VT 2 is /dev/ttyv1, and so on.
/// See `ttyDeviceName()` for the mapping.
pub fn getActiveTty() !u8 {
    // VT_GETINDEX reports the index of the terminal behind the file
    // descriptor, which is what we want: the one getty handed us, not
    // whichever one happens to be in the foreground at this instant. Console
    // drivers that don't implement it only offer VT_GETACTIVE.
    const request = comptime if (@hasDecl(consio, "VT_GETINDEX")) consio.VT_GETINDEX else consio.VT_GETACTIVE;

    var vt: c_int = 0;

    const status = std.c.ioctl(std.posix.STDIN_FILENO, request, &vt);
    if (status != 0) return error.FailedToGetActiveTty;
    if (vt < 1 or vt > std.math.maxInt(u8)) return error.NoTtyFound;

    return @intCast(vt);
}

/// Writes the device name of the virtual terminal `tty` (e.g. "ttyv1" for VT
/// 2) into `buf` and returns it. FreeBSD names these devices with a single
/// hexadecimal digit, so VT 11 is /dev/ttyva.
pub fn ttyDeviceName(buf: []u8, tty: u8) ![]u8 {
    return std.fmt.bufPrint(buf, "ttyv{x}", .{tty -| 1});
}

/// Same as `ttyDeviceName()`, but NUL-terminated for passing to C.
pub fn ttyDeviceNameZ(buf: []u8, tty: u8) ![:0]u8 {
    return std.fmt.bufPrintZ(buf, "ttyv{x}", .{tty -| 1});
}

pub fn switchTty(tty: u8) !void {
    var status = std.c.ioctl(std.posix.STDIN_FILENO, consio.VT_ACTIVATE, tty);
    if (status != 0) return error.FailedToActivateTty;

    status = std.c.ioctl(std.posix.STDIN_FILENO, consio.VT_WAITACTIVE, tty);
    if (status != 0) return error.FailedToWaitForActiveTty;
}

pub fn getLockState() !struct {
    numlock: bool,
    capslock: bool,
} {
    var led: LedState = undefined;
    const status = std.c.ioctl(std.posix.STDIN_FILENO, kbio.KDGETLED, &led);
    if (status != 0) return error.FailedToGetLockState;

    return .{
        .numlock = (led & kbio.LED_NUM) != 0,
        .capslock = (led & kbio.LED_CAP) != 0,
    };
}

pub fn setNumlock(val: bool) !void {
    var led: LedState = undefined;
    var status = std.c.ioctl(std.posix.STDIN_FILENO, kbio.KDGETLED, &led);
    if (status != 0) return error.FailedToGetNumlock;

    const numlock = (led & kbio.LED_NUM) != 0;
    if (numlock != val) {
        status = std.c.ioctl(std.posix.STDIN_FILENO, kbio.KDSETLED, led ^ kbio.LED_NUM);
        if (status != 0) return error.FailedToSetNumlock;
    }
}

pub fn setUserContext(allocator: std.mem.Allocator, entry: UsernameEntry) !void {
    const username_z = try allocator.dupeZ(u8, entry.username.?);
    defer allocator.free(username_z);

    // FreeBSD has initgroups() in unistd
    const status = unistd.initgroups(username_z.ptr, @intCast(entry.gid));
    if (status != 0) return error.GroupInitializationFailed;

    // FreeBSD sets the GID and UID with setusercontext()
    const result = pwd.setusercontext(null, entry.passwd_struct, @intCast(entry.uid), pwd.LOGIN_SETALL);
    if (result != 0) return error.SetUserUidFailed;
}

pub fn setUserShell(entry: *UsernameEntry) void {
    unistd.setusershell();

    const shell = unistd.getusershell();
    entry.shell = std.mem.span(shell);

    unistd.endusershell();
}

pub fn setEnvironmentVariable(allocator: std.mem.Allocator, name: []const u8, value: []const u8, replace: bool) !void {
    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);

    const value_z = try allocator.dupeZ(u8, value);
    defer allocator.free(value_z);

    const status = stdlib.setenv(name_z.ptr, value_z.ptr, @intFromBool(replace));
    if (status != 0) return error.SetEnvironmentVariableFailed;
}

pub fn putEnvironmentVariable(name_and_value: []u8) !void {
    const status = stdlib.putenv(name_and_value.ptr);
    if (status != 0) return error.PutEnvironmentVariableFailed;
}

pub fn getNextUsernameEntry() ?UsernameEntry {
    const entry = pwd.getpwent();
    if (entry == null) return null;

    return .{
        .username = if (entry.*.pw_name) |name| std.mem.span(name) else null,
        .uid = @intCast(entry.*.pw_uid),
        .gid = @intCast(entry.*.pw_gid),
        .home = if (entry.*.pw_dir) |dir| std.mem.span(dir) else null,
        .shell = if (entry.*.pw_shell) |shell| std.mem.span(shell) else null,
        .passwd_struct = entry,
    };
}

pub fn getUsernameEntry(username: [:0]const u8) ?UsernameEntry {
    const entry = pwd.getpwnam(username);
    if (entry == null) return null;

    return .{
        .username = if (entry.*.pw_name) |name| std.mem.span(name) else null,
        .uid = @intCast(entry.*.pw_uid),
        .gid = @intCast(entry.*.pw_gid),
        .home = if (entry.*.pw_dir) |dir| std.mem.span(dir) else null,
        .shell = if (entry.*.pw_shell) |shell| std.mem.span(shell) else null,
        .passwd_struct = entry,
    };
}

pub fn closePasswordDatabase() void {
    pwd.endpwent();
}

/// FreeBSD has no /etc/login.defs to read a UID range from, so the bounds are
/// baked into the binary at build time. See `UidRange`.
pub fn getUserIdRange() UidRange {
    return .{};
}

pub fn shutdownSystem() !void {
    if (isError(unistd.reboot(reboot.RB_POWEROFF))) {
        return error.CouldntShutdown;
    }
}

pub fn rebootSystem() !void {
    if (isError(unistd.reboot(reboot.RB_AUTOBOOT))) {
        return error.CouldntReboot;
    }
}
