const std = @import("std");
const sokol = @import("lib/sokol-zig/build.zig");

// ...
// pub fn build(b: *std.build.Builder) void {
// ...

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const shd = b.addSystemCommand(&[_][]const u8{ "sokol-shdc", "--input=src/shaders/main.glsl", "--output=src/shaders/main.glsl.zig", "--slang=glsl330:hlsl5:metal_macos", "--format=sokol_zig" });

    const map = b.addSystemCommand(&[_][]const u8{"luajit buildmap.lua"});

    const exe = b.addExecutable("sokamoka", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const sokol_build = sokol.buildSokol(b, target, mode, "lib/sokol-zig/");
    exe.linkLibrary(sokol_build);

    exe.addPackagePath("znt", "lib/znt.zig");
    exe.addPackagePath("sokol", "lib/sokol-zig/src/sokol/sokol.zig");
    exe.addPackagePath("mp3", "lib/audio/minimp3.zig");

    exe.addIncludeDir("lib/image/");
    exe.addCSourceFile("lib/image/stb_image_impl.c", &[_][]const u8{"-DIMPL"});
    
    exe.addIncludeDir("lib/audio/");
    exe.addCSourceFile("lib/audio/minimp3.c", &[_][]const u8{});

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const shd_step = b.step("shader", "Compile the shaders (requires sokol-shdc)");
    shd_step.dependOn(&shd.step);

    const map_step = b.step("maps", "Compile the maps (requires lua and dkjson)");
    map_step.dependOn(&map.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
