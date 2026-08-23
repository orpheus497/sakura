const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_x11_support = b.option(bool, "enable_x11_support", "Enable X11 support") orelse true;
    const mod = b.addModule("sakura-ui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const uid_min = b.option(std.posix.uid_t, "uid_min", "Set the minimum UID of listed users (default is 1000). This value gets embedded into the binary");
    const uid_max = b.option(std.posix.uid_t, "uid_max", "Set the maximum UID of listed users (default is 32000). This value gets embedded into the binary");

    const sakura_core = b.dependency("sakura_core", .{
        .target = target,
        .optimize = optimize,
        .enable_x11_support = enable_x11_support,
        .uid_min = uid_min,
        .uid_max = uid_max,
    });
    mod.addImport("sakura-core", sakura_core.module("sakura-core"));

    const termbox_dep = b.dependency("termbox2", .{
        .target = target,
        .optimize = optimize,
    });

    const translate_c_dep = b.dependency("translate_c", .{
        .target = target,
    });

    const termbox2: Translator = .init(translate_c_dep, .{
        .c_source_file = termbox_dep.path("termbox2.h"),
        .target = target,
        .optimize = optimize,
    });
    termbox2.defineCMacro("TB_IMPL", null);
    // TODO 0.16.0: Workaround until Aro gets better...
    // https://codeberg.org/ziglang/translate-c/issues/319
    termbox2.defineCMacro("_XOPEN_SOURCE", "700");
    termbox2.defineCMacro("TB_OPT_ATTR_W", "32"); // Enable 24-bit color support + styling (32-bit)
    // TODO 0.16.0: Including <fcntl.h> with -OReleaseSafe causes
    // __attribute__(__error__()) to be called. Below
    // is the workaround.
    termbox2.defineCMacro("_FORTIFY_SOURCE", "0");
    // Required on FreeBSD so that <sys/*.h> exposes the BSD-only declarations
    // termbox2 relies on.
    termbox2.defineCMacro("__BSD_VISIBLE", "1");
    mod.addImport("termbox2", termbox2.mod);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
