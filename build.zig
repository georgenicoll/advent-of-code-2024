const std = @import("std");

fn addExecutableWithName(
    comptime name: []const u8,
    b: *std.Build,
    shared_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(name ++ "/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.root_module.addImport("shared", shared_mod);
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
    regex_lib.addIncludePath(b.path("shared/include"));
    regex_lib.addCSourceFiles(.{
        .files = &.{"shared/src/regex_slim.c"},
        .flags = &.{"-std=c99"},
    });
    regex_lib.installHeader(b.path("shared/include/regex_slim.h"), "regex_slim.h");
    regex_lib.linkLibC();
    b.installArtifact(regex_lib);

    const shared_mod = b.addModule("shared", .{
        .root_source_file = b.path("shared/src/shared.zig"),
    });
    shared_mod.linkLibrary(regex_lib);
    shared_mod.addIncludePath(b.path("shared/include"));

    addExecutableWithName("testing", b, shared_mod, target, optimize);
    addExecutableWithName("testing2", b, shared_mod, target, optimize);
    addExecutableWithName("template", b, shared_mod, target, optimize);
    addExecutableWithName("day1", b, shared_mod, target, optimize);
    addExecutableWithName("day2", b, shared_mod, target, optimize);
    addExecutableWithName("day3", b, shared_mod, target, optimize);
    addExecutableWithName("day4", b, shared_mod, target, optimize);
    addExecutableWithName("day5", b, shared_mod, target, optimize);
    addExecutableWithName("day6", b, shared_mod, target, optimize);
    addExecutableWithName("day7", b, shared_mod, target, optimize);
    addExecutableWithName("day8", b, shared_mod, target, optimize);
    addExecutableWithName("day9", b, shared_mod, target, optimize);
    addExecutableWithName("day10", b, shared_mod, target, optimize);
    addExecutableWithName("day11", b, shared_mod, target, optimize);
    addExecutableWithName("day12", b, shared_mod, target, optimize);
    addExecutableWithName("day13", b, shared_mod, target, optimize);
    addExecutableWithName("day14", b, shared_mod, target, optimize);
    addExecutableWithName("day15", b, shared_mod, target, optimize);
    addExecutableWithName("day16", b, shared_mod, target, optimize);
    addExecutableWithName("day17", b, shared_mod, target, optimize);
    addExecutableWithName("day18", b, shared_mod, target, optimize);
    addExecutableWithName("day19", b, shared_mod, target, optimize);
}
