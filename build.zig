const std = @import("std");
const builtin = @import("builtin");

const InstallType = enum {
    installexe,
    installnoconf,
    uninstallexe,
    uninstallnoconf,
};

const min_zig_string = "0.16.0";
const current_zig = builtin.zig_version;

// Implementing zig version detection through compile time
comptime {
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
}

const sakura_version = std.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 };

fn InstallStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    comptime install_type: InstallType,
    dest_directory: []const u8,
    config_directory: []const u8,
    prefix_directory: []const u8,
    executable_name: []const u8,
    default_tty_str: []const u8,
) *std.Build.Step.Run {
    const step = b.addRunArtifact(b.addExecutable(.{
        .name = "install",
        .root_module = b.createModule(.{
            .root_source_file = b.path("install.zig"),
            .target = target,
        }),
    }));
    step.step.dependOn(b.getInstallStep());

    step.addArgs(&.{
        std.enums.tagName(InstallType, install_type).?,
        dest_directory,
        config_directory,
        prefix_directory,
        executable_name,
        default_tty_str,
    });

    return step;
}

pub fn build(b: *std.Build) !void {
    const dest_directory = b.option([]const u8, "dest_directory", "Specify a destination directory for installation") orelse "";
    const config_directory = b.option([]const u8, "config_directory", "Specify a default config directory (default is /usr/local/etc). This path gets embedded into the binary") orelse "/usr/local/etc";
    const prefix_directory = b.option([]const u8, "prefix_directory", "Specify a default prefix directory (default is /usr/local)") orelse "/usr/local";
    const executable_name = b.option([]const u8, "name", "Specify installed executable file name (default is sakura)") orelse "sakura";

    const build_options = b.addOptions();
    const version_str = try getVersionStr(b, "sakura", sakura_version);
    const enable_x11_support = b.option(bool, "enable_x11_support", "Enable X11 support (default is on)") orelse true;
    const default_tty = b.option(u8, "default_tty", "Set the virtual terminal Sakura runs on (default is 2, i.e. /dev/ttyv1)") orelse 2;
    const fallback_tty = b.option(u8, "fallback_tty", "Set the fallback virtual terminal (default is 2). This value gets embedded into the binary") orelse 2;
    const uid_min = b.option(std.posix.uid_t, "uid_min", "Set the minimum UID of listed users (default is 1000). This value gets embedded into the binary") orelse 1000;
    const uid_max = b.option(std.posix.uid_t, "uid_max", "Set the maximum UID of listed users (default is 32000). This value gets embedded into the binary") orelse 32000;

    const default_tty_str = try std.fmt.allocPrint(b.allocator, "{d}", .{default_tty});

    build_options.addOption([]const u8, "config_directory", config_directory);
    build_options.addOption([]const u8, "prefix_directory", prefix_directory);
    build_options.addOption([]const u8, "version", version_str);
    build_options.addOption(u8, "tty", default_tty);
    build_options.addOption(u8, "fallback_tty", fallback_tty);
    build_options.addOption(std.posix.uid_t, "uid_min", uid_min);
    build_options.addOption(std.posix.uid_t, "uid_max", uid_max);
    build_options.addOption(bool, "enable_x11_support", enable_x11_support);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Sakura is a FreeBSD-only display manager. Bail out early with a readable
    // message instead of letting the build fail somewhere deep inside a C
    // header translation.
    if (target.result.os.tag != .freebsd) {
        std.debug.print(
            "error: Sakura only supports FreeBSD, but the requested target is '{t}'.\n",
            .{target.result.os.tag},
        );
        return error.UnsupportedTarget;
    }

    const exe = b.addExecutable(.{
        .name = "sakura",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const zlua = b.dependency("zlua", .{
        .target = target,
        .optimize = optimize,
        .lang = .luajit,
    });
    exe.root_module.addImport("zlua", zlua.module("zlua"));

    const sakura_ui = b.dependency("sakura_ui", .{
        .target = target,
        .optimize = optimize,
        .enable_x11_support = enable_x11_support,
        .uid_min = uid_min,
        .uid_max = uid_max,
    });
    exe.root_module.addImport("sakura-ui", sakura_ui.module("sakura-ui"));

    exe.root_module.addOptions("build_options", build_options);

    const clap = b.dependency("clap", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("clap", clap.module("clap"));

    exe.root_module.linkSystemLibrary("pam", .{});
    if (enable_x11_support) exe.root_module.linkSystemLibrary("xcb", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const installexe_step = b.step("installexe", "Install Sakura, its configuration and its getty wrapper");
    installexe_step.dependOn(&InstallStep(
        b,
        target,
        .installexe,
        dest_directory,
        config_directory,
        prefix_directory,
        executable_name,
        default_tty_str,
    ).step);

    const installnoconf_step = b.step("installnoconf", "Install Sakura and its getty wrapper, but not the configuration file");
    installnoconf_step.dependOn(&InstallStep(
        b,
        target,
        .installnoconf,
        dest_directory,
        config_directory,
        prefix_directory,
        executable_name,
        default_tty_str,
    ).step);

    const uninstallexe_step = b.step("uninstallexe", "Uninstall Sakura, its configuration and its getty wrapper");
    uninstallexe_step.dependOn(&InstallStep(
        b,
        target,
        .uninstallexe,
        dest_directory,
        config_directory,
        prefix_directory,
        executable_name,
        default_tty_str,
    ).step);

    const uninstallnoconf_step = b.step("uninstallnoconf", "Uninstall Sakura and its getty wrapper, but keep the configuration directory");
    uninstallnoconf_step.dependOn(&InstallStep(
        b,
        target,
        .uninstallnoconf,
        dest_directory,
        config_directory,
        prefix_directory,
        executable_name,
        default_tty_str,
    ).step);
}

fn getVersionStr(b: *std.Build, name: []const u8, version: std.SemanticVersion) ![]const u8 {
    const version_str = b.fmt("{d}.{d}.{d}", .{ version.major, version.minor, version.patch });

    var status: u8 = undefined;
    const git_describe_raw = b.runAllowFail(&[_][]const u8{
        "git",
        "-C",
        b.build_root.path orelse ".",
        "describe",
        "--match",
        "*.*.*",
        "--tags",
    }, &status, .ignore) catch {
        return version_str;
    };
    var git_describe = std.mem.trim(u8, git_describe_raw, " \n\r");
    git_describe = std.mem.trimStart(u8, git_describe, "v");

    switch (std.mem.count(u8, git_describe, "-")) {
        0 => {
            if (!std.mem.eql(u8, version_str, git_describe)) {
                std.debug.print("{s} version '{s}' does not match git tag: '{s}'\n", .{ name, version_str, git_describe });
                std.process.exit(1);
            }
            return version_str;
        },
        2 => {
            // Untagged development build (e.g. 0.10.0-dev.2025+ecf0050a9).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            const tagged_ancestor = std.mem.trimStart(u8, it.first(), "v");
            const commit_height = it.next().?;
            const commit_id = it.next().?;

            const ancestor_ver = try std.SemanticVersion.parse(tagged_ancestor);
            if (version.order(ancestor_ver) != .gt) {
                std.debug.print("{s} version '{f}' must be greater than tagged ancestor '{f}'\n", .{ name, version, ancestor_ver });
                std.process.exit(1);
            }

            // Check that the commit hash is prefixed with a 'g' (a Git convention).
            if (commit_id.len < 1 or commit_id[0] != 'g') {
                std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                return version_str;
            }

            // The version is reformatted in accordance with the https://semver.org specification.
            return b.fmt("{s}-dev.{s}+{s}", .{ version_str, commit_height, commit_id[1..] });
        },
        else => {
            std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
            return version_str;
        },
    }
}
