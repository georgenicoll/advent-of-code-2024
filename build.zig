const std = @import("std");

fn addExecutableWithName(
    comptime name: []const u8,
    b: *std.Build,
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
    b.installArtifact(exe);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    addExecutableWithName("testing", b, target, optimize);
    addExecutableWithName("testing2", b, target, optimize);
    addExecutableWithName("day1", b, target, optimize);
}
