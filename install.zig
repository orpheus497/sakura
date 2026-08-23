const std = @import("std");

const PatchMap = std.StringHashMap([]const u8);
const InstallType = enum {
    installexe,
    installnoconf,
    uninstallexe,
    uninstallnoconf,
};

var dest_directory: []const u8 = undefined;
var config_directory: []const u8 = undefined;
var prefix_directory: []const u8 = undefined;
var executable_name: []const u8 = undefined;
var wrapper_name: []const u8 = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var args = init.minimal.args.iterate();
    if (!args.skip()) return error.NoProgramName;

    const install_type = std.meta.stringToEnum(InstallType, args.next().?).?;
    dest_directory = args.next().?;
    config_directory = args.next().?;
    prefix_directory = args.next().?;
    executable_name = args.next().?;
    const default_tty_str = args.next().?;

    wrapper_name = try std.fmt.allocPrint(allocator, "{s}_wrapper", .{executable_name});
    defer allocator.free(wrapper_name);

    switch (install_type) {
        .installexe, .installnoconf => {
            // FreeBSD numbers virtual terminals from 1, but names the device
            // nodes backing them from 0, using a single hexadecimal digit:
            // VT 2 is /dev/ttyv1, VT 11 is /dev/ttyva.
            const default_tty = std.fmt.parseInt(u8, default_tty_str, 10) catch 2;
            const tty_device = try std.fmt.allocPrint(allocator, "ttyv{x}", .{default_tty -| 1});
            defer allocator.free(tty_device);

            var patch_map = PatchMap.init(allocator);
            defer patch_map.deinit();

            try patch_map.put("$DEFAULT_TTY", default_tty_str);
            try patch_map.put("$TTY_DEVICE", tty_device);
            try patch_map.put("$CONFIG_DIRECTORY", config_directory);
            try patch_map.put("$PREFIX_DIRECTORY", prefix_directory);
            try patch_map.put("$EXECUTABLE_NAME", executable_name);
            try patch_map.put("$WRAPPER_NAME", wrapper_name);

            try installSakura(allocator, io, patch_map, install_type == .installexe);
            try installGettyWrapper(allocator, io, patch_map);

            std.debug.print(
                \\
                \\info: Sakura is installed. Two steps are left, both of which
                \\      have a ready-made snippet in {s}/sakura:
                \\
                \\      1. Append the contents of gettytab.example to /etc/gettytab
                \\      2. Replace the {s} line in /etc/ttys with the one in ttys.example
                \\
                \\      Then run `kill -HUP 1` or reboot.
                \\
                \\
            , .{ config_directory, tty_device });
        },
        .uninstallexe, .uninstallnoconf => {
            if (install_type == .uninstallexe) {
                try deleteTree(allocator, io, config_directory, "/sakura", "sakura config directory not found");
            }

            try deleteFile(allocator, io, prefix_directory, "/bin/", executable_name, "sakura executable not found");
            try deleteFile(allocator, io, prefix_directory, "/bin/", wrapper_name, "getty wrapper not found");
            try deleteFile(allocator, io, config_directory, "/pam.d/", "sakura", "sakura pam file not found");
            try deleteFile(allocator, io, config_directory, "/pam.d/", "sakura-autologin", "sakura autologin pam file not found");
        },
    }
}

fn installSakura(allocator: std.mem.Allocator, io: std.Io, patch_map: PatchMap, install_config: bool) !void {
    const sakura_config_directory = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/sakura" });
    defer allocator.free(sakura_config_directory);

    std.Io.Dir.cwd().createDirPath(io, sakura_config_directory) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{sakura_config_directory});
    };

    const sakura_custom_sessions_directory = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/sakura/custom-sessions" });
    defer allocator.free(sakura_custom_sessions_directory);

    std.Io.Dir.cwd().createDirPath(io, sakura_custom_sessions_directory) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{sakura_custom_sessions_directory});
    };

    const sakura_lang_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/sakura/lang" });
    defer allocator.free(sakura_lang_path);

    std.Io.Dir.cwd().createDirPath(io, sakura_lang_path) catch {
        std.debug.print("warn: {s} already exists as a directory.\n", .{sakura_lang_path});
    };

    {
        const exe_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix_directory, "/bin" });
        defer allocator.free(exe_path);

        std.Io.Dir.cwd().createDirPath(io, exe_path) catch {
            if (!std.mem.eql(u8, dest_directory, "")) {
                std.debug.print("warn: {s} already exists as a directory.\n", .{exe_path});
            }
        };

        var executable_dir = std.Io.Dir.cwd().openDir(io, exe_path, .{}) catch unreachable;
        defer executable_dir.close(io);

        try installFile(io, "zig-out/bin/sakura", executable_dir, exe_path, executable_name, .{});
    }

    {
        var config_dir = std.Io.Dir.cwd().openDir(io, sakura_config_directory, .{}) catch unreachable;
        defer config_dir.close(io);

        if (install_config) {
            const patched_config = try patchFile(allocator, io, "res/config.ini", patch_map);
            defer allocator.free(patched_config);

            try installText(io, patched_config, config_dir, sakura_config_directory, "config.ini", .{});

            try installFile(io, "res/startup.sh", config_dir, sakura_config_directory, "startup.sh", .{ .permissions = .fromMode(0o755) });
        }

        const patched_example_config = try patchFile(allocator, io, "res/config.ini", patch_map);
        defer allocator.free(patched_example_config);

        try installText(io, patched_example_config, config_dir, sakura_config_directory, "config.ini.example", .{});

        const patched_setup = try patchFile(allocator, io, "res/setup.sh", patch_map);
        defer allocator.free(patched_setup);

        try installText(io, patched_setup, config_dir, sakura_config_directory, "setup.sh", .{ .permissions = .fromMode(0o755) });

        // Ready-made /etc/gettytab and /etc/ttys snippets for the administrator
        const patched_gettytab = try patchFile(allocator, io, "res/sakura.gettytab", patch_map);
        defer allocator.free(patched_gettytab);

        try installText(io, patched_gettytab, config_dir, sakura_config_directory, "gettytab.example", .{});

        const patched_ttys = try patchFile(allocator, io, "res/sakura.ttys", patch_map);
        defer allocator.free(patched_ttys);

        try installText(io, patched_ttys, config_dir, sakura_config_directory, "ttys.example", .{});

        try installFile(io, "res/example.dur", config_dir, sakura_config_directory, "example.dur", .{ .permissions = .fromMode(0o755) });

        try installFile(io, "res/example.lua", config_dir, sakura_config_directory, "example.lua", .{ .permissions = .fromMode(0o755) });
    }

    {
        var custom_sessions_dir = std.Io.Dir.cwd().openDir(io, sakura_custom_sessions_directory, .{}) catch unreachable;
        defer custom_sessions_dir.close(io);

        const patched_readme = try patchFile(allocator, io, "res/custom-sessions/README", patch_map);
        defer allocator.free(patched_readme);

        try installText(io, patched_readme, custom_sessions_dir, sakura_custom_sessions_directory, "README", .{});
    }

    {
        var lang_dir = std.Io.Dir.cwd().openDir(io, sakura_lang_path, .{}) catch unreachable;
        defer lang_dir.close(io);

        const languages = [_][]const u8{
            "ar.ini",
            "bg.ini",
            "cat.ini",
            "cs.ini",
            "de.ini",
            "en.ini",
            "eo.ini",
            "es.ini",
            "fr.ini",
            "it.ini",
            "ja_JP.ini",
            "ku.ini",
            "lv.ini",
            "pl.ini",
            "pt.ini",
            "pt_BR.ini",
            "ro.ini",
            "ru.ini",
            "sr.ini",
            "sr_Cyrl.ini",
            "sv.ini",
            "tr.ini",
            "uk.ini",
            "zh_CN.ini",
            "zh_TW.ini",
        };

        inline for (languages) |language| {
            try installFile(io, "res/lang/" ++ language, lang_dir, sakura_lang_path, language, .{});
        }
    }

    {
        const pam_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/pam.d" });
        defer allocator.free(pam_path);

        std.Io.Dir.cwd().createDirPath(io, pam_path) catch {
            if (!std.mem.eql(u8, dest_directory, "")) {
                std.debug.print("warn: {s} already exists as a directory.\n", .{pam_path});
            }
        };

        var pam_dir = std.Io.Dir.cwd().openDir(io, pam_path, .{}) catch unreachable;
        defer pam_dir.close(io);

        try installFile(io, "res/pam.d/sakura", pam_dir, pam_path, "sakura", .{ .permissions = .fromMode(0o644) });
        try installFile(io, "res/pam.d/sakura-autologin", pam_dir, pam_path, "sakura-autologin", .{ .permissions = .fromMode(0o644) });
    }
}

// On FreeBSD, getty(8) appends "login -fp root" to the program named by the
// "lo" capability, which Sakura does not understand. A small wrapper script
// swallows those arguments.
fn installGettyWrapper(allocator: std.mem.Allocator, io: std.Io, patch_map: PatchMap) !void {
    const exe_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix_directory, "/bin" });
    defer allocator.free(exe_path);

    var executable_dir = std.Io.Dir.cwd().openDir(io, exe_path, .{}) catch unreachable;
    defer executable_dir.close(io);

    const patched_wrapper = try patchFile(allocator, io, "res/sakura-wrapper", patch_map);
    defer allocator.free(patched_wrapper);

    try installText(io, patched_wrapper, executable_dir, exe_path, wrapper_name, .{ .permissions = .fromMode(0o755) });
}

fn installFile(
    io: std.Io,
    source_file: []const u8,
    destination_directory: std.Io.Dir,
    destination_directory_path: []const u8,
    destination_file: []const u8,
    options: std.Io.Dir.CopyFileOptions,
) !void {
    try std.Io.Dir.cwd().copyFile(source_file, destination_directory, destination_file, io, options);
    std.debug.print("info: installed {s}/{s}\n", .{ destination_directory_path, destination_file });
}

fn patchFile(allocator: std.mem.Allocator, io: std.Io, source_file: []const u8, patch_map: PatchMap) ![]const u8 {
    var file = try std.Io.Dir.cwd().openFile(io, source_file, .{});
    defer file.close(io);

    const stat = try file.stat(io);

    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    var text = try reader.interface.readAlloc(allocator, @intCast(stat.size));

    var iterator = patch_map.iterator();
    while (iterator.next()) |kv| {
        const new_text = try std.mem.replaceOwned(u8, allocator, text, kv.key_ptr.*, kv.value_ptr.*);
        allocator.free(text);
        text = new_text;
    }

    return text;
}

fn installText(
    io: std.Io,
    text: []const u8,
    destination_directory: std.Io.Dir,
    destination_directory_path: []const u8,
    destination_file: []const u8,
    options: std.Io.File.CreateFlags,
) !void {
    var file = try destination_directory.createFile(io, destination_file, options);
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(text);
    try writer.interface.flush();

    std.debug.print("info: installed {s}/{s}\n", .{ destination_directory_path, destination_file });
}

fn deleteFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    prefix: []const u8,
    directory: []const u8,
    file: []const u8,
    warning: []const u8,
) !void {
    const path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix, directory, file });
    defer allocator.free(path);

    std.Io.Dir.cwd().deleteFile(io, path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("warn: {s}\n", .{warning});
            return;
        }

        return err;
    };

    std.debug.print("info: deleted {s}\n", .{path});
}

fn deleteTree(
    allocator: std.mem.Allocator,
    io: std.Io,
    prefix: []const u8,
    directory: []const u8,
    warning: []const u8,
) !void {
    const path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix, directory });
    defer allocator.free(path);

    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("warn: {s}\n", .{warning});
            return;
        }

        return err;
    };
    dir.close(io);

    try std.Io.Dir.cwd().deleteTree(io, path);

    std.debug.print("info: deleted {s}\n", .{path});
}
