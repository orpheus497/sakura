const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_x11_support = b.option(bool, "enable_x11_support", "Enable X11 support") orelse true;
    const mod = b.addModule("sakura-core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const uid_min = b.option(std.posix.uid_t, "uid_min", "Set the minimum UID of listed users (default is 1000). This value gets embedded into the binary") orelse 1000;
    const uid_max = b.option(std.posix.uid_t, "uid_max", "Set the maximum UID of listed users (default is 32000). This value gets embedded into the binary") orelse 32000;
    const build_options = b.addOptions();
    build_options.addOption(std.posix.uid_t, "uid_min", uid_min);
    build_options.addOption(std.posix.uid_t, "uid_max", uid_max);
    build_options.addOption(bool, "enable_x11_support", enable_x11_support);
    mod.addOptions("build_options", build_options);

    const zigini = b.dependency("zigini", .{ .target = target, .optimize = optimize });
    mod.addImport("zigini", zigini.module("zigini"));

    const translate_c = b.dependency("translate_c", .{
        .target = target,
    });

    addCImport(b, mod, translate_c, target, optimize, "pam", "#include <security/pam_appl.h>");
    addCImport(b, mod, translate_c, target, optimize, "utmp", "#include <utmpx.h>");
    if (enable_x11_support) {
        addCImport(b, mod, translate_c, target, optimize, "xcb", "#include <xcb/xcb.h>");
    }
    addCImport(b, mod, translate_c, target, optimize, "pwd",
        \\#include <sys/types.h>
        \\#include <pwd.h>
        \\#include <login_cap.h>
    );
    addCImport(b, mod, translate_c, target, optimize, "stdlib", "#include <stdlib.h>");
    addCImport(b, mod, translate_c, target, optimize, "unistd", "#include <unistd.h>");
    addCImport(b, mod, translate_c, target, optimize, "system_time", "#include <sys/time.h>");
    addCImport(b, mod, translate_c, target, optimize, "time", "#include <time.h>");

    // FreeBSD console & power management interfaces
    addCImport(b, mod, translate_c, target, optimize, "kbio", "#include <sys/kbio.h>");
    addCImport(b, mod, translate_c, target, optimize, "consio", "#include <sys/consio.h>");
    addCImport(b, mod, translate_c, target, optimize, "sysctl",
        \\#include <sys/types.h>
        \\#include <sys/sysctl.h>
    );
    addCImport(b, mod, translate_c, target, optimize, "reboot",
        \\#include <sys/types.h>
        \\#include <sys/reboot.h>
    );

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

fn addCImport(
    b: *std.Build,
    mod: *std.Build.Module,
    translate_c: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    comptime bytes: []const u8,
) void {
    const translator: Translator = .init(translate_c, .{
        .c_source_file = b.addWriteFiles().add(name ++ ".h", bytes),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport(name, translator.mod);
}
