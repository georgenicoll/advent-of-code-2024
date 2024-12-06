const std = @import("std");

fn addExecutableWithName(
    comptime name: []const u8,
    b: *std.Build,
    regex_lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(name ++ "/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addAnonymousImport("shared", .{ .root_source_file = b.path("shared/shared.zig") });
    exe.linkLibrary(regex_lib);
    exe.addIncludePath(b.path("lib"));
    exe.linkLibC();
    b.installArtifact(exe);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //Adapted from https://github.com/zigcc/zig-cookbook/blob/main/build.zig#L47
    const regex_lib = b.addStaticLibrary(.{
        .name = "regex_slim",
        .optimize = optimize,
        .target = target,
    });
    regex_lib.addCSourceFiles(.{
        .files = &.{"lib/regex_slim.c"},
        .flags = &.{"-std=c99"},
    });
    regex_lib.linkLibC();
    b.installArtifact(regex_lib);

    addExecutableWithName("testing", b, regex_lib, target, optimize);
    addExecutableWithName("testing2", b, regex_lib, target, optimize);
    addExecutableWithName("template", b, regex_lib, target, optimize);
    addExecutableWithName("day1", b, regex_lib, target, optimize);
    addExecutableWithName("day2", b, regex_lib, target, optimize);
    addExecutableWithName("day3", b, regex_lib, target, optimize);
    addExecutableWithName("day4", b, regex_lib, target, optimize);
    addExecutableWithName("day5", b, regex_lib, target, optimize);
    addExecutableWithName("day6", b, regex_lib, target, optimize);
    addExecutableWithName("day7", b, regex_lib, target, optimize);
}
