const std = @import("std");

const PatchMap = std.StringHashMap([]const u8);
const InstallType = enum {
    installexe,
    installnoconf,
    uninstallexe,
    uninstallnoconf,
};

/// Which operating system the build targets. This is deliberately a separate
/// axis from `InitSystem`: the pre-fork tree folded the two together and made
/// `freebsd` a sibling of `systemd`, which is a category error -- it leaves
/// nowhere to say "FreeBSD" and "OpenRC" at once.
const TargetOs = enum {
    freebsd,
    linux,
};

/// How the host starts Sakura. FreeBSD uses getty(8) driven by /etc/ttys and
/// has no service file, so it has no entry here.
const InitSystem = enum {
    none,
    systemd,
    openrc,
    runit,
    s6,
    dinit,
    sysvinit,
};

var dest_directory: []const u8 = undefined;
var config_directory: []const u8 = undefined;
var prefix_directory: []const u8 = undefined;
var executable_name: []const u8 = undefined;
var wrapper_name: []const u8 = undefined;
var target_os: TargetOs = undefined;
var init_system: InitSystem = undefined;

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
    target_os = std.meta.stringToEnum(TargetOs, args.next().?).?;
    init_system = std.meta.stringToEnum(InitSystem, args.next().?).?;

    wrapper_name = try std.fmt.allocPrint(allocator, "{s}_wrapper", .{executable_name});
    defer allocator.free(wrapper_name);

    switch (install_type) {
        .installexe, .installnoconf => {
            // The two kernels name virtual terminal devices differently, and
            // both halves differ: FreeBSD numbers terminals from 1 but names
            // the nodes from 0 in base 32 (VT 2 is /dev/ttyv1, VT 11 is
            // /dev/ttyva), while Linux names them in decimal with no offset
            // (VT 2 is /dev/tty2). Base 32 and hex agree over every reachable
            // index because VT_MAXWINDOWS is at most 16.
            const default_tty = std.fmt.parseInt(u8, default_tty_str, 10) catch 2;
            const tty_device = switch (target_os) {
                .freebsd => try std.fmt.allocPrint(allocator, "ttyv{x}", .{default_tty -| 1}),
                .linux => try std.fmt.allocPrint(allocator, "tty{d}", .{default_tty}),
            };
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

            switch (target_os) {
                // FreeBSD is started by getty(8) out of /etc/ttys, so what gets
                // installed is the wrapper getty executes plus the two snippets
                // the administrator has to paste in.
                .freebsd => {
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
                .linux => {
                    try installInitSystem(allocator, io, patch_map);
                    printLinuxInstructions(tty_device);
                },
            }
        },
        .uninstallexe, .uninstallnoconf => {
            if (install_type == .uninstallexe) {
                try deleteTree(allocator, io, config_directory, "/sakura", "sakura config directory not found");
            }

            try deleteFile(allocator, io, prefix_directory, "/bin/", executable_name, "sakura executable not found");
            try deleteFile(allocator, io, config_directory, "/pam.d/", "sakura", "sakura pam file not found");
            try deleteFile(allocator, io, config_directory, "/pam.d/", "sakura-autologin", "sakura autologin pam file not found");

            switch (target_os) {
                .freebsd => try deleteFile(allocator, io, prefix_directory, "/bin/", wrapper_name, "getty wrapper not found"),
                .linux => try uninstallInitSystem(allocator, io),
            }
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

        // Ready-made /etc/gettytab and /etc/ttys snippets for the
        // administrator. Both describe files that exist only on FreeBSD, so
        // there is nothing to install them for on Linux, where the init system
        // handles startup instead.
        if (target_os == .freebsd) {
            const patched_gettytab = try patchFile(allocator, io, "res/sakura.gettytab", patch_map);
            defer allocator.free(patched_gettytab);

            try installText(io, patched_gettytab, config_dir, sakura_config_directory, "gettytab.example", .{});

            const patched_ttys = try patchFile(allocator, io, "res/sakura.ttys", patch_map);
            defer allocator.free(patched_ttys);

            try installText(io, patched_ttys, config_dir, sakura_config_directory, "ttys.example", .{});
        }

        try installFile(io, "res/example.dur", config_dir, sakura_config_directory, "example.dur", .{ .permissions = .fromMode(0o755) });

        try installFile(io, "res/example.lua", config_dir, sakura_config_directory, "example.lua", .{ .permissions = .fromMode(0o755) });

        // The default login wallpaper. Installed unconditionally (not only with
        // the config) so that installnoconf still repairs a deleted wallpaper.
        try installFile(io, "res/pixel_sakura.gif", config_dir, sakura_config_directory, "pixel_sakura.gif", .{ .permissions = .fromMode(0o644) });
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

        // The two policies cannot be merged: the Linux one relies on the
        // leading "-" prefix for modules that may not be installed, and on
        // FreeBSD 14.3 and earlier that prefix is a fatal parse error which
        // discards the whole policy. The *installed* names stay fixed, so
        // Config.zig's service_name/auto_login_service defaults and the
        // documentation remain correct on both platforms.
        const policy, const autologin_policy = switch (target_os) {
            .freebsd => .{ "res/pam.d/sakura-freebsd", "res/pam.d/sakura-freebsd-autologin" },
            .linux => .{ "res/pam.d/sakura-linux", "res/pam.d/sakura-linux-autologin" },
        };

        try installFile(io, policy, pam_dir, pam_path, "sakura", .{ .permissions = .fromMode(0o644) });
        try installFile(io, autologin_policy, pam_dir, pam_path, "sakura-autologin", .{ .permissions = .fromMode(0o644) });
    }
}

// Function purpose: install the service file for the host's init system. Each
// one is a separate file under res/ rather than a generated template, so what
// lands on disk is reviewable as-is.
fn installInitSystem(allocator: std.mem.Allocator, io: std.Io, patch_map: PatchMap) !void {
    switch (init_system) {
        .none => std.debug.print(
            "warn: no init system selected, so no service file was installed. Pass -Dinit_system to install one.\n",
            .{},
        ),

        .systemd => {
            // Units belong under the prefix, not in /etc: /etc/systemd/system
            // is the administrator's directory and a package must not write
            // there.
            try installServiceFile(allocator, io, patch_map, prefix_directory, "/lib/systemd/system", "res/sakura.service", "sakura@.service", 0o644);
        },

        .openrc => try installServiceFile(allocator, io, patch_map, config_directory, "/init.d", "res/sakura-openrc", executable_name, 0o755),
        .sysvinit => try installServiceFile(allocator, io, patch_map, config_directory, "/init.d", "res/sakura-sysvinit", executable_name, 0o755),
        .dinit => try installServiceFile(allocator, io, patch_map, config_directory, "/dinit.d", "res/sakura-dinit", executable_name, 0o644),

        .runit => {
            const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/sv/sakura" });
            defer allocator.free(service_path);

            std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
            var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
            defer service_dir.close(io);

            const patched_conf = try patchFile(allocator, io, "res/sakura-runit-service/conf", patch_map);
            defer allocator.free(patched_conf);
            try installText(io, patched_conf, service_dir, service_path, "conf", .{});

            const patched_run = try patchFile(allocator, io, "res/sakura-runit-service/run", patch_map);
            defer allocator.free(patched_run);
            try installText(io, patched_run, service_dir, service_path, "run", .{ .permissions = .fromMode(0o755) });

            try installFile(io, "res/sakura-runit-service/finish", service_dir, service_path, "finish", .{ .permissions = .fromMode(0o755) });

            // runit keeps its supervise state on a tmpfs, so the service
            // directory points at it rather than holding it.
            const supervise_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ service_path, "supervise" });
            defer allocator.free(supervise_path);

            std.Io.Dir.cwd().symLink(io, "/run/runit/supervise.sakura", supervise_path, .{}) catch |err| {
                if (err != error.PathAlreadyExists) return err;
                std.debug.print("warn: {s} already exists.\n", .{supervise_path});
                return;
            };
            std.debug.print("info: installed symlink {s}\n", .{supervise_path});
        },

        .s6 => {
            const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/s6/sv/sakura-srv" });
            defer allocator.free(service_path);

            std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
            var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
            defer service_dir.close(io);

            const patched_run = try patchFile(allocator, io, "res/sakura-s6/run", patch_map);
            defer allocator.free(patched_run);
            try installText(io, patched_run, service_dir, service_path, "run", .{ .permissions = .fromMode(0o755) });

            try installFile(io, "res/sakura-s6/type", service_dir, service_path, "type", .{});

            // s6-rc needs the service listed in a bundle's contents.d before it
            // will be brought up.
            const admin_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, config_directory, "/s6/adminsv/default/contents.d" });
            defer allocator.free(admin_path);

            std.Io.Dir.cwd().createDirPath(io, admin_path) catch {};
            var admin_dir = std.Io.Dir.cwd().openDir(io, admin_path, .{}) catch unreachable;
            defer admin_dir.close(io);

            var file = try admin_dir.createFile(io, "sakura-srv", .{});
            file.close(io);
            std.debug.print("info: installed {s}/sakura-srv\n", .{admin_path});
        },
    }
}

fn installServiceFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    patch_map: PatchMap,
    prefix: []const u8,
    directory: []const u8,
    source: []const u8,
    destination: []const u8,
    mode: std.Io.File.Mode,
) !void {
    const service_path = try std.Io.Dir.path.join(allocator, &[_][]const u8{ dest_directory, prefix, directory });
    defer allocator.free(service_path);

    std.Io.Dir.cwd().createDirPath(io, service_path) catch {};
    var service_dir = std.Io.Dir.cwd().openDir(io, service_path, .{}) catch unreachable;
    defer service_dir.close(io);

    const patched = try patchFile(allocator, io, source, patch_map);
    defer allocator.free(patched);

    try installText(io, patched, service_dir, service_path, destination, .{ .permissions = .fromMode(mode) });
}

// Function purpose: remove whatever installInitSystem put down. Kept in step
// with it by hand, since an uninstall that misses a file leaves the host
// starting a binary that is no longer there.
fn uninstallInitSystem(allocator: std.mem.Allocator, io: std.Io) !void {
    switch (init_system) {
        .none => {},
        .systemd => try deleteFile(allocator, io, prefix_directory, "/lib/systemd/system/", "sakura@.service", "systemd unit not found"),
        .openrc, .sysvinit => try deleteFile(allocator, io, config_directory, "/init.d/", executable_name, "init script not found"),
        .dinit => try deleteFile(allocator, io, config_directory, "/dinit.d/", executable_name, "dinit service not found"),
        .runit => try deleteTree(allocator, io, config_directory, "/sv/sakura", "runit service not found"),
        .s6 => {
            try deleteTree(allocator, io, config_directory, "/s6/sv/sakura-srv", "s6 service not found");
            try deleteFile(allocator, io, config_directory, "/s6/adminsv/default/contents.d/", "sakura-srv", "s6 bundle entry not found");
        },
    }
}

// Function purpose: tell the administrator the one step the installer cannot
// take, which differs per init system.
fn printLinuxInstructions(tty_device: []const u8) void {
    const enable_hint = switch (init_system) {
        .none => "      Select an init system with -Dinit_system to have a service file installed.",
        .systemd => "      systemctl enable --now sakura@" ++ "<tty>" ++ ".service",
        .openrc => "      rc-update add sakura default",
        .runit => "      ln -s /etc/sv/sakura /var/service/",
        .s6 => "      s6-rc-bundle-update add default sakura-srv",
        .dinit => "      dinitctl enable sakura",
        .sysvinit => "      update-rc.d sakura defaults",
    };

    std.debug.print(
        \\
        \\info: Sakura is installed. One step is left: enable it, and make sure
        \\      nothing else is already holding /dev/{s}.
        \\
        \\{s}
        \\
        \\      A getty on that terminal will fight Sakura for it. The systemd
        \\      unit declares the conflict itself; on the others, disable the
        \\      getty for that terminal by hand.
        \\
        \\
    , .{ tty_device, enable_hint });
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
