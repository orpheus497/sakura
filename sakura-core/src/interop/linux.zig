// Script function and purpose: the Linux half of the platform boundary. Every
// declaration here mirrors one in interop/freebsd.zig, and interop.zig picks
// between the two at comptime. Nothing outside this directory may import a
// platform-specific C header.

const std = @import("std");
const build_options = @import("build_options");
const UidRange = @import("../UidRange.zig");
const grp = @import("grp");
const kd = @import("kd");
const pwd = @import("pwd");
const stdlib = @import("stdlib");
const system_time = @import("system_time");
const time = @import("time");
const unistd = @import("unistd");
const vt = @import("vt");

pub const pam = @import("pam");
pub const utmp = @import("utmp");
// Exists for X11 support only, so it is only imported when X11 support was
// enabled at build time.
pub const xcb = if (build_options.enable_x11_support) @import("xcb") else struct {};

/// The Linux console driver reports the keyboard *flag* state through
/// KDGKBLED/KDSKBLED as a single byte. This is deliberately not KDGETLED,
/// which reports the physical LEDs: the two can disagree, and what a login
/// prompt needs to warn about is the flag state that will apply to the next
/// keystroke. See ioctl_console(2).
const LedState = u8;

/// Character major number of the virtual console devices. /dev/ttyN is major 4
/// minor N for 1 <= N <= 63; minor 0 is /dev/tty0, the "current VT" alias, and
/// 64 and up are serial lines. See the kernel's admin-guide/devices.
const vt_major = 4;
const vt_minor_max = 63;

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

/// glibc returns -1 on failure and sets errno, so a plain sign check is all
/// that is ever needed here.
pub fn isError(result: anytype) bool {
    comptime std.debug.assert(@typeInfo(@TypeOf(result)).int.signedness == .signed);
    return result < 0;
}

/// The Linux console is UTF-8 capable.
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

/// Function purpose: turn a device number into a virtual terminal index, or
/// null when the device is not a virtual terminal at all. Shared by both
/// strategies in `getActiveTty` so the two can never disagree about what
/// counts as a VT.
fn vtFromDev(major: u32, minor: u32) ?u8 {
    if (major != vt_major) return null;
    if (minor < 1 or minor > vt_minor_max) return null;
    return @intCast(minor);
}

/// Action purpose: decompose a dev_t the way glibc's major()/minor() macros do.
/// Writing `/ 256` and `% 256` happens to work for virtual terminals only
/// because both numbers are small; spelling out the real encoding is what keeps
/// this correct if it is ever handed a different device.
fn devMajor(dev: u64) u32 {
    return @intCast((dev >> 8) & 0xfff);
}

fn devMinor(dev: u64) u32 {
    return @intCast((dev & 0xff) | ((dev >> 12) & ~@as(u64, 0xff)));
}

/// Returns the number of the virtual terminal this process is attached to.
/// Linux numbers virtual terminals from 1 and names the device nodes to match:
/// VT 1 is /dev/tty1, with no offset. See `ttyDeviceName()`.
///
/// Linux has no VT_GETINDEX. The two interfaces that look like substitutes --
/// /sys/class/tty/tty0/active and VT_GETSTATE's v_active -- both report the
/// terminal currently in the *foreground*, which is a different question: a VT
/// switch racing startup would make a display manager believe it owns a
/// terminal it does not. Both strategies below instead answer "which device is
/// behind this file descriptor", the same question VT_GETINDEX answers on
/// FreeBSD.
pub fn getActiveTty() !u8 {
    // Strategy 1: TIOCGDEV reports the device number of the VT behind the file
    // descriptor, without depending on a controlling terminal.
    //
    // Action purpose: the request has to be bit-cast rather than passed
    // directly. Linux's _IOR sets its direction bits as _IOC_READ << 30, i.e.
    // 0x80000000, so TIOCGDEV is 0x80045432 -- above c_int's maximum, which is
    // what ioctl(3) takes. FreeBSD's _IOR uses IOC_OUT (0x40000000) instead and
    // stays positive, which is why none of the FreeBSD requests need this.
    var dev: c_uint = 0;
    const tiocgdev: c_int = @bitCast(@as(u32, vt.TIOCGDEV));
    if (std.c.ioctl(std.posix.STDIN_FILENO, tiocgdev, &dev) == 0) {
        if (vtFromDev(devMajor(dev), devMinor(dev))) |tty| return tty;
    }

    // Strategy 2: /proc/self/stat field 7 is tty_nr, the controlling terminal's
    // device number. Used when stdin has been redirected but the controlling
    // terminal is still the VT, which is how some init systems start us.
    return getActiveTtyFromProc();
}

fn getActiveTtyFromProc() !u8 {
    const fd = std.c.open("/proc/self/stat", .{ .ACCMODE = .RDONLY });
    if (fd < 0) return error.NoTtyFound;
    defer _ = std.c.close(fd);

    var buf: [1024]u8 = undefined;
    const read = std.c.read(fd, &buf, buf.len);
    if (read <= 0) return error.NoTtyFound;
    const stat = buf[0..@intCast(read)];

    // Action purpose: field 2 is the executable name in parentheses and may
    // itself contain spaces or parentheses, so the field walk starts after the
    // *last* ')' rather than splitting the whole line. tty_nr is then the
    // fifth field along.
    const close_paren = std.mem.lastIndexOfScalar(u8, stat, ')') orelse return error.NoTtyFound;
    if (close_paren + 2 > stat.len) return error.NoTtyFound;

    var fields = std.mem.tokenizeScalar(u8, stat[close_paren + 2 ..], ' ');
    // state, ppid, pgrp, session, tty_nr
    for (0..4) |_| _ = fields.next() orelse return error.NoTtyFound;
    const tty_nr_str = fields.next() orelse return error.NoTtyFound;

    // tty_nr is a signed 32-bit field and is 0 when the process has no
    // controlling terminal.
    const tty_nr = std.fmt.parseInt(i32, tty_nr_str, 10) catch return error.NoTtyFound;
    if (tty_nr <= 0) return error.NoTtyFound;

    const dev: u64 = @intCast(tty_nr);
    return vtFromDev(devMajor(dev), devMinor(dev)) orelse error.NoTtyFound;
}

/// Writes the device name of the virtual terminal `tty` (e.g. "tty2" for VT 2)
/// into `buf` and returns it. Linux names these devices in decimal with no
/// offset, unlike FreeBSD. See console(4).
pub fn ttyDeviceName(buf: []u8, tty: u8) ![]u8 {
    return std.fmt.bufPrint(buf, "tty{d}", .{tty});
}

/// Same as `ttyDeviceName()`, but NUL-terminated for passing to C.
pub fn ttyDeviceNameZ(buf: []u8, tty: u8) ![:0]u8 {
    return std.fmt.bufPrintSentinel(buf, "tty{d}", .{tty}, 0);
}

pub fn switchTty(tty: u8) !void {
    var status = std.c.ioctl(std.posix.STDIN_FILENO, vt.VT_ACTIVATE, @as(c_int, tty));
    if (status != 0) return error.FailedToActivateTty;

    status = std.c.ioctl(std.posix.STDIN_FILENO, vt.VT_WAITACTIVE, @as(c_int, tty));
    if (status != 0) return error.FailedToWaitForActiveTty;
}

pub fn getLockState() !struct {
    numlock: bool,
    capslock: bool,
} {
    var led: LedState = undefined;
    const status = std.c.ioctl(std.posix.STDIN_FILENO, kd.KDGKBLED, &led);
    if (status != 0) return error.FailedToGetLockState;

    // K_NUMLOCK and K_CAPSLOCK, not LED_NUM and LED_CAP: the LED_* values
    // belong to the KDGETLED pair and are not interchangeable with these. Note
    // also that FreeBSD's LED_CAP and LED_SCR are numerically swapped relative
    // to Linux's K_CAPSLOCK and K_SCROLLLOCK, which is why every constant here
    // comes from this platform's own header.
    return .{
        .numlock = (led & kd.K_NUMLOCK) != 0,
        .capslock = (led & kd.K_CAPSLOCK) != 0,
    };
}

pub fn setNumlock(val: bool) !void {
    var led: LedState = undefined;
    var status = std.c.ioctl(std.posix.STDIN_FILENO, kd.KDGKBLED, &led);
    if (status != 0) return error.FailedToGetNumlock;

    const numlock = (led & kd.K_NUMLOCK) != 0;
    if (numlock != val) {
        // The set side takes the mask by value as an unsigned long, where the
        // get side took a pointer to one byte.
        const mask: c_ulong = @intCast(led ^ kd.K_NUMLOCK);
        status = std.c.ioctl(std.posix.STDIN_FILENO, kd.KDSKBLED, mask);
        if (status != 0) return error.FailedToSetNumlock;
    }
}

/// Linux has no setusercontext(3). The triple below is the closest equivalent
/// and is *not* equal to it: FreeBSD's LOGIN_SETALL also applies the login
/// class, resource limits, umask, priority, MAC label, CPU mask and the
/// LANG/TZ/TERM environment. On Linux those come from PAM instead -- pam_limits,
/// pam_umask and pam_env in the session stack -- so they are configured in the
/// PAM policy rather than here.
pub fn setUserContext(allocator: std.mem.Allocator, entry: UsernameEntry) !void {
    const username_z = try allocator.dupeSentinel(u8, entry.username.?, 0);
    defer allocator.free(username_z);

    // Linux has initgroups() in grp, not unistd.
    const status = grp.initgroups(username_z.ptr, @intCast(entry.gid));
    if (status != 0) return error.GroupInitializationFailed;

    // Order matters: dropping the group must happen while still privileged.
    if (isError(std.posix.system.setgid(@intCast(entry.gid)))) return error.SetUserGidFailed;
    if (isError(std.posix.system.setuid(@intCast(entry.uid)))) return error.SetUserUidFailed;
}

/// Fills in `entry.shell` from the first entry of /etc/shells, for an account
/// whose passwd record names no shell. The name is copied into `buf`, which the
/// caller owns and which must outlive `entry`.
///
/// The copy is the point. `getusershell(3)` returns a pointer into a list the
/// library allocated, and `endusershell(3)` frees that list, so keeping the
/// returned pointer left `entry.shell` dangling into freed memory -- which was
/// then duplicated and handed to `execve` as the program to run.
pub fn setUserShell(entry: *UsernameEntry, buf: []u8) !void {
    unistd.setusershell();
    defer unistd.endusershell();

    // getusershell() returns NULL once the list is exhausted, which is also
    // what an empty or unreadable /etc/shells looks like on the first call.
    const shell = unistd.getusershell();
    if (shell == null) return error.NoUserShellAvailable;

    const name = std.mem.span(shell);
    // A name that exactly fills `buf` is fine: nothing here needs room for a
    // terminator, since `entry.shell` is a plain slice and the callers that
    // hand it to execve duplicate it with dupeSentinel.
    if (name.len > buf.len) return error.UserShellTooLong;

    @memcpy(buf[0..name.len], name[0..name.len]);
    entry.shell = buf[0..name.len];
}

pub fn setEnvironmentVariable(allocator: std.mem.Allocator, name: []const u8, value: []const u8, replace: bool) !void {
    const name_z = try allocator.dupeSentinel(u8, name, 0);
    defer allocator.free(name_z);

    const value_z = try allocator.dupeSentinel(u8, value, 0);
    defer allocator.free(value_z);

    const status = stdlib.setenv(name_z.ptr, value_z.ptr, @intFromBool(replace));
    if (status != 0) return error.SetEnvironmentVariableFailed;
}

/// `putenv` keeps the pointer it is given rather than copying, so the buffer
/// must be NUL-terminated and must outlive the environment entry.
pub fn putEnvironmentVariable(name_and_value: [:0]u8) !void {
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

/// Reads the regular-account UID range from login.defs(5). `path` is
/// configurable because the file's location is a shadow-utils compile-time
/// default rather than a standard, and the build-time bounds are the fallback
/// for a file that is missing, unreadable, or silent on either bound.
///
/// Note the Linux default UID_MAX is 60000, where FreeBSD's pw(8) uses 32000,
/// so the build-time default must not be assumed to suit both.
pub fn getUserIdRange(allocator: std.mem.Allocator, io: std.Io, path: []const u8) UidRange {
    var range: UidRange = .{};

    // Action purpose: openFile, not openFileAbsolute. The latter opens with
    // `assert(path.isAbsolute(...))` (std/Io/Dir.zig:585), and an assert is
    // `if (!ok) unreachable` -- not an error, so the `catch return range`
    // below cannot intercept it. `path` comes straight from config.ini with
    // no validation, so a relative `login_defs_path` would panic Sakura
    // before it drew a login prompt in any build with runtime safety on, and
    // be undefined behaviour without. openFile takes the same absolute paths
    // (openFileAbsolute itself just delegates to it) and returns an error for
    // a relative one that does not resolve, which is what the catch expects.
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch return range;
    defer file.close(io);

    // Action purpose: bound the read. login.defs(5) is a few dozen lines of
    // key-value pairs; 1 MiB is already orders of magnitude more than any real
    // one. Unbounded, a path pointed at something huge -- by a typo as much as
    // by malice -- would be read wholly into memory during startup. Exceeding
    // the limit lands in the same fallback as an unreadable file.
    var file_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &file_buffer);
    const contents = file_reader.interface.allocRemaining(allocator, .limited(1 << 20)) catch return range;
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (parseLoginDefsValue(std.posix.uid_t, "UID_MIN", trimmed)) |value| {
            range.uid_min = value;
        } else if (parseLoginDefsValue(std.posix.uid_t, "UID_MAX", trimmed)) |value| {
            range.uid_max = value;
        }
    }

    return range;
}

fn parseLoginDefsValue(comptime T: type, comptime name: []const u8, line: []const u8) ?T {
    if (!std.mem.startsWith(u8, line, name)) return null;
    const rest = std.mem.trim(u8, line[name.len..], " \t");
    // Guard against UID_MIN matching a longer key that merely starts the same.
    if (rest.len == line.len - name.len) return null;
    return std.fmt.parseInt(T, rest, 10) catch null;
}

/// Reads the remaining battery capacity as a percentage. `source` is a
/// power-supply name under /sys/class/power_supply, e.g. "BAT0".
///
/// `capacity` is preferred but the kernel does not synthesise it for drivers
/// that do not report it, so energy_now/energy_full is the fallback. See the
/// kernel's Documentation/ABI/testing/sysfs-class-power.
pub fn getBatteryPercentage(source: []const u8) !u8 {
    var path_buffer: [128]u8 = undefined;

    const capacity_path = std.fmt.bufPrint(
        &path_buffer,
        "/sys/class/power_supply/{s}/capacity",
        .{source},
    ) catch return error.BatterySourceTooLong;

    if (readSysfsUnsigned(capacity_path)) |capacity| {
        if (capacity > 100) return error.InvalidBatteryCapacity;
        return @intCast(capacity);
    }

    const now = readSysfsEnergy(source, "energy_now") orelse return error.BatteryReadFailed;
    const full = readSysfsEnergy(source, "energy_full") orelse return error.BatteryReadFailed;
    if (full == 0) return error.InvalidBatteryCapacity;

    const percentage = (now * 100) / full;
    if (percentage > 100) return error.InvalidBatteryCapacity;

    return @intCast(percentage);
}

fn readSysfsEnergy(source: []const u8, comptime leaf: []const u8) ?u64 {
    var path_buffer: [128]u8 = undefined;
    const path = std.fmt.bufPrint(
        &path_buffer,
        "/sys/class/power_supply/{s}/" ++ leaf,
        .{source},
    ) catch return null;
    return readSysfsUnsigned(path);
}

fn readSysfsUnsigned(path: []const u8) ?u64 {
    var path_z_buffer: [160]u8 = undefined;
    const path_z = std.fmt.bufPrintSentinel(&path_z_buffer, "{s}", .{path}, 0) catch return null;

    const fd = std.c.open(path_z.ptr, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = std.c.close(fd);

    var buf: [32]u8 = undefined;
    const read = std.c.read(fd, &buf, buf.len);
    if (read <= 0) return null;

    const text = std.mem.trim(u8, buf[0..@intCast(read)], " \t\r\n");
    return std.fmt.parseInt(u64, text, 10) catch null;
}

/// Linux's reboot(2) does not sync first -- the man page notes for each of
/// these operations that "if not preceded by a sync(2), data will be lost".
/// FreeBSD's reboot(2) syncs unless RB_NOSYNC is given, so this is a real
/// asymmetry and the sync below must not be factored out as common code.
///
/// std.posix.reboot is used rather than the libc wrapper or a hand-rolled
/// syscall. The libc constant names differ between the two kernels -- FreeBSD
/// spells it RB_POWEROFF and Linux RB_POWER_OFF -- while RB_AUTOBOOT exists on
/// both with *different* values, which would compile cleanly and then do the
/// wrong thing. The wrapper takes a tagged command instead of a bare integer,
/// so neither mistake is expressible, and it decodes errno properly: the raw
/// syscall returns a `usize` whose error range cannot be sign-checked the way
/// `isError` checks a libc return.
///
/// Neither command returns on success, so a return at all means failure.
pub fn shutdownSystem() !void {
    std.posix.system.sync();
    std.posix.reboot(.POWER_OFF) catch return error.CouldntShutdown;
    return error.CouldntShutdown;
}

pub fn rebootSystem() !void {
    std.posix.system.sync();
    std.posix.reboot(.RESTART) catch return error.CouldntReboot;
    return error.CouldntReboot;
}
