const std = @import("std");
const process = @import("shared").process;

const Context = struct {};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();

    const parsed_lines = try process.parse_file(
        Context,
        []u8,
        parse_line,
        arena_allocator.allocator(),
        .{},
        "testing/test_file.txt",
    );
    defer parsed_lines.deinit();

    const stdout = std.io.getStdOut();
    for (parsed_lines.items) |line| {
        try stdout.writeAll(line);
        try stdout.writeAll("\n");
    }
}

fn parse_line(allocator: std.mem.Allocator, context: Context, line: []const u8) ![]u8 {
    _ = context;
    _ = line;
    return try allocator.dupe(u8, "A non-parsed line");
}
