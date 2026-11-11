const std = @import("std");
const interop = @import("interop.zig");

const LogFile = @This();

maybe_path: ?[]const u8,
could_open_log_file: bool = undefined,
maybe_file: ?std.Io.File = null,
buffer: []u8,
maybe_file_writer: ?std.Io.File.Writer = null,

pub fn init(io: std.Io, path: ?[]const u8, buffer: []u8) !LogFile {
    var log_file = LogFile{
        .maybe_path = path,
        .buffer = buffer,
    };

    if (path) |p| {
        log_file.could_open_log_file = try openLogFile(io, p, &log_file);
    } else {
        std.posix.system.openlog("sakura", 0, 0);
        log_file.could_open_log_file = true;
    }

    return log_file;
}

pub fn reinit(self: *LogFile, io: std.Io) !void {
    // Reopening without closing would leak the previous descriptor; deinit
    // clears the handle, so this only fires when one is genuinely still open.
    if (self.maybe_file) |file| {
        file.close(io);
        self.maybe_file = null;
        self.maybe_file_writer = null;
    }

    if (self.maybe_path) |path| {
        self.could_open_log_file = try openLogFile(io, path, self);
    } else {
        std.posix.system.openlog("sakura", 0, 0);
        self.could_open_log_file = true;
    }
}

pub fn deinit(self: *LogFile, io: std.Io) void {
    if (self.maybe_file) |file| {
        file.close(io);
        // Clear it so a later reinit cannot close the same descriptor twice.
        self.maybe_file = null;
        self.maybe_file_writer = null;
    } else {
        std.posix.system.closelog();
    }
}

// Function purpose: write one diagnostic line, and never fail doing it.
//
// Neither info nor err can return an error, and that is a deliberate contract
// rather than a convenience. A diagnostic describes what happened; it is never
// itself the thing that happened. So failing to record one must not change what
// the caller does.
//
// This module already held that rule for opening the log -- fallBackToSyslog
// exists precisely so a log that cannot be opened does not end the login screen
// -- but it did not hold it for writing to one. Writing could fail two ways, and
// both reached callers as errors they only ever propagated:
//
//   * The file branch returns error.WriteFailed, which is what a full
//     filesystem gives. That is the same condition that stops a session log
//     from being created, so the code in auth.zig that degrades gracefully when
//     it cannot make a log would abort the login on the write that said so.
//
//   * The syslog branch formatted the message into a 1024-byte buffer, then
//     formatted it a second time -- prefix and all -- into whatever was left of
//     that same buffer. Holding two copies in one buffer halved the usable
//     limit, so a session_log path of 166 bytes, which is legal when PATH_MAX
//     is 4096, made std.fmt.bufPrint return error.NoSpaceLeft. A login could be
//     denied because the path it was being told about was too long to complain
//     about.
//
// Every caller in auth.zig sits on the login path, and not one did anything
// with the error but pass it up, so the error union bought nothing and cost
// that. The syslog branch now formats once, prefix included, into a
// std.Io.Writer.fixed: an over-long message keeps what fits and loses only its
// tail, which is strictly better than losing the whole line and the login too.
fn write(
    self: *LogFile,
    io: std.Io,
    comptime level: []const u8,
    priority: c_int,
    category: []const u8,
    comptime message: []const u8,
    args: anytype,
) void {
    if (self.maybe_file_writer) |*writer| {
        var buffer: [128:0]u8 = undefined;
        const time = interop.timeAsString(io, &buffer, "%Y-%m-%d %H:%M:%S");

        // Action purpose: attempt every step even after one fails, rather than
        // returning at the first. Returning early would leave a line that
        // partly landed without its newline, and the next diagnostic would be
        // appended to it -- one log line holding two messages. In practice a
        // failure here is a full filesystem, where all four fail and nothing is
        // written at all; the ordering only matters in the case where it does
        // not, and there it is better to close the line.
        writer.interface.print("{s} [" ++ level ++ "/{s}] ", .{ time, category }) catch {};
        writer.interface.print(message, args) catch {};
        writer.interface.writeByte('\n') catch {};
        writer.interface.flush() catch {};
    } else {
        var buffer: [syslog_line_capacity + 1]u8 = undefined;
        const line = formatSyslogLine(&buffer, level, category, message, args);

        // Action purpose: hand the diagnostic to syslog(3) as an argument, not
        // as its format string. The constant "%s" is the whole point and must
        // not be removed.
        //
        // syslog(3) is variadic and its second parameter is a printf format:
        // FreeBSD's libc does `va_start(ap, fmt); vsyslog(pri, fmt, ap)` and
        // ends at `(void)vfprintf(fp, fmt, ap)`, and glibc's __syslog forwards
        // fmt to __vsyslog_internal, which passes it to __vsnprintf_internal.
        // Passing the message there means every per cent sign in it is read as
        // a conversion with no argument behind it.
        //
        // This is not hypothetical for this program. A session's Exec line is
        // logged verbatim by executeCmd, and desktop entries carry field codes
        // -- on this machine 9 of 30 installed Exec lines contain one. Two of
        // the codes in them, %f and %F, are also printf conversions for
        // double, so they consume an argument that was never pushed: the
        // command line in the log comes out mangled and the read is
        // uninitialised. %m is worse in a quieter way, because syslog(3)
        // replaces it with strerror() before vfprintf is reached, so a path
        // containing it is logged as something it is not. %n would be a write.
        //
        // The configured session_log path, PAM variable values and Lua error
        // text reach these diagnostics too, and none of them are this
        // program's to choose.
        std.posix.system.syslog(priority, "%s", line.ptr);
    }
}

// The most a single syslog(3) line may occupy, terminator excluded. It was
// already this, implicitly, as the size of the format buffer.
const syslog_line_capacity = 1024;

// Function purpose: lay out one syslog line, truncating rather than failing.
//
// Separated from write() for two reasons. It is the only part of the syslog
// branch whose result can be inspected -- syslog(3) itself returns nothing and
// goes to a system service -- so this is what the tests at the bottom of the
// file can actually assert on. And it keeps the single-pass property visible:
// the prefix and the message go into one writer, over one buffer, so the
// capacity means what it says.
//
// The previous code formatted the message, then formatted it again with the
// prefix into what remained of the same buffer, which stored two copies and so
// halved the real limit to about 500 bytes. Worse, it did that with
// std.fmt.bufPrint, which returns error.NoSpaceLeft rather than a short
// result, so an over-long line was not shortened but lost -- and, because
// write() propagated, took the caller down with it.
fn formatSyslogLine(
    buffer: *[syslog_line_capacity + 1]u8,
    comptime level: []const u8,
    category: []const u8,
    comptime message: []const u8,
    args: anytype,
) [:0]const u8 {
    var line = std.Io.Writer.fixed(buffer[0..syslog_line_capacity]);

    // Action purpose: a failed print leaves behind whatever fit and has
    // advanced `end` by exactly that much, so both results are discarded
    // rather than checked. What arrived is what gets logged.
    line.print("[" ++ level ++ "/{s}] ", .{category}) catch {};
    line.print(message, args) catch {};

    // The buffer is one byte longer than the capacity handed to the writer, so
    // this terminator can never overwrite a byte of the message.
    const len = line.end;
    buffer[len] = 0;
    return buffer[0..len :0];
}

pub fn info(self: *LogFile, io: std.Io, category: []const u8, comptime message: []const u8, args: anytype) void {
    self.write(io, "info", std.posix.LOG.INFO, category, message, args);
}

pub fn err(self: *LogFile, io: std.Io, category: []const u8, comptime message: []const u8, args: anytype) void {
    self.write(io, "err", std.posix.LOG.ERR, category, message, args);
}

// Function purpose: give up on the configured log file and route logging to
// syslog(3) instead, closing whatever descriptor was already open. Returns
// false so it can be tail-called from every failure site in openLogFile, which
// is what keeps a logging problem from being fatal: discarding the log is at
// its worst in exactly the situation that causes it, since the troubleshooting
// instructions send people to this file first, and a permissions problem or a
// full disk would otherwise hand them an empty one with the reason gone.
// Leaving both handles null is what makes info() and err() take their syslog
// branch, and what makes deinit() close the syslog connection rather than a
// file.
fn fallBackToSyslog(io: std.Io, log_file: *LogFile) bool {
    if (log_file.maybe_file) |file| file.close(io);
    log_file.maybe_file = null;
    log_file.maybe_file_writer = null;

    std.posix.system.openlog("sakura", 0, 0);
    return false;
}

fn openLogFile(io: std.Io, path: []const u8, log_file: *LogFile) !bool {
    log_file.maybe_file = std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only }) catch std.Io.Dir.cwd().createFile(io, path, .{ .permissions = .fromMode(0o666) }) catch {
        return fallBackToSyslog(io, log_file);
    };

    var log_file_writer = log_file.maybe_file.?.writer(io, log_file.buffer);

    // Seek to the end of the log file
    //
    // Action purpose: a failure here takes the same syslog fallback as a
    // failure to open. Propagating instead would have unwound out of init() or
    // reinit() and so out of main -- ending the login screen because a log file
    // could not be measured or positioned. It also stranded the descriptor:
    // maybe_file was left holding an open file that nothing went on to close.
    const stat = log_file.maybe_file.?.stat(io) catch return fallBackToSyslog(io, log_file);
    log_file_writer.seekTo(stat.size) catch return fallBackToSyslog(io, log_file);

    log_file.maybe_file_writer = log_file_writer;
    return true;
}

// The message that made the old two-pass formatter fail. Its length is what
// matters, not its wording: 338 bytes of literal text plus a path.
const long_diagnostic =
    "cannot create a private session log: replacing '{s}' needs write permission on the directory holding it, which this user does not have, and an existing file there cannot be shown never to have been readable. Continuing without a session log. Make that directory writable to get one back, or set session_log = null to ask for this deliberately";

test "a diagnostic shorter than the capacity is laid out whole" {
    var buffer: [syslog_line_capacity + 1]u8 = undefined;
    const line = formatSyslogLine(&buffer, "err", "auth/sys", "cannot inspect '{s}'", .{"/home/u/.cache/sakura/session.log"});

    try std.testing.expectEqualStrings(
        "[err/auth/sys] cannot inspect '/home/u/.cache/sakura/session.log'",
        line,
    );
    try std.testing.expectEqual(@as(u8, 0), buffer[line.len]);
}

test "a path that overflowed the old formatter now produces a line" {
    // 166 bytes was the shortest session_log path that made the previous code
    // return error.NoSpaceLeft, because it held the message twice in one
    // 1024-byte buffer. PATH_MAX is 4096, so such a path is perfectly legal,
    // and the error used to leave openSessionLog and deny the login.
    var path: [166]u8 = undefined;
    @memset(&path, 'a');

    var buffer: [syslog_line_capacity + 1]u8 = undefined;
    const line = formatSyslogLine(&buffer, "err", "auth/sys", long_diagnostic, .{&path});

    try std.testing.expect(line.len > 0);
    try std.testing.expect(line.len <= syslog_line_capacity);
    try std.testing.expect(std.mem.startsWith(u8, line, "[err/auth/sys] cannot create a private session log"));
    try std.testing.expectEqual(@as(u8, 0), buffer[line.len]);
}

test "an over-long diagnostic is truncated, never dropped" {
    // A path at PATH_MAX cannot fit, so the line is cut at the capacity. The
    // point is that a line still arrives: the beginning says what happened,
    // which is the part worth having.
    var path: [4096]u8 = undefined;
    @memset(&path, 'a');

    var buffer: [syslog_line_capacity + 1]u8 = undefined;
    const line = formatSyslogLine(&buffer, "err", "auth/sys", long_diagnostic, .{&path});

    try std.testing.expectEqual(@as(usize, syslog_line_capacity), line.len);
    try std.testing.expect(std.mem.startsWith(u8, line, "[err/auth/sys] cannot create a private session log"));
    try std.testing.expectEqual(@as(u8, 0), buffer[line.len]);
}

test "the whole capacity is usable, not half of it" {
    // The old formatter's effective ceiling was about half the buffer. This
    // fills the line past that halfway mark to show the single pass recovers
    // it: 338 bytes of literal plus a 600-byte path is 938, well beyond ~500.
    var path: [600]u8 = undefined;
    @memset(&path, 'b');

    var buffer: [syslog_line_capacity + 1]u8 = undefined;
    const line = formatSyslogLine(&buffer, "err", "auth/sys", long_diagnostic, .{&path});

    try std.testing.expect(line.len > syslog_line_capacity / 2);
    try std.testing.expect(line.len < syslog_line_capacity);
    // Nothing was truncated at this length, so the tail is intact.
    try std.testing.expect(std.mem.endsWith(u8, line, "to ask for this deliberately"));
}

test "info and err cannot fail, by contract" {
    // The whole point of the change: no caller can be aborted by a diagnostic.
    // Asserting it on the type means the property cannot quietly regress into
    // an error union again without this failing.
    try std.testing.expectEqual(void, @typeInfo(@TypeOf(info)).@"fn".return_type.?);
    try std.testing.expectEqual(void, @typeInfo(@TypeOf(err)).@"fn".return_type.?);
}
