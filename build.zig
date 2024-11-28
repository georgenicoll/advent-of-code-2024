const std = @import("std");

pub fn build(b: *std.Build) void {
    const process_mod = b.addModule("utils", .{ .root_source_file = b.path("utils/process.zig") });

    const testing_exe = b.addExecutable(.{
        .name = "testing",
        .root_source_file = b.path("testing/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    testing_exe.root_module.addImport("process", process_mod);
    b.installArtifact(testing_exe);
}
