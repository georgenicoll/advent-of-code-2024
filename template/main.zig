const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
};

const Line = struct {};

pub fn main() !void {
    const day = "template";
    const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    //const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);

    var context = Context{
        .delimiters = delimiters,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    // const stdout = std.io.getStdOut();
    // for (context.grid.items) |row| {
    //     try stdout.writeAll(row.items);
    //     try stdout.writeAll("\n");
    // }
    // try stdout.writer().print("width: {d}, height: {d}\n", .{ context.width, context.height });

    try calculate(arena_allocator.allocator(), context);
    try calculate_2(arena_allocator.allocator(), context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;
    _ = context;
    _ = line;
    return .{};
}

fn calculate(allocator: std.mem.Allocator, context: Context) !void {
    _ = allocator;
    _ = context;

    var sum: usize = 0;
    sum += 0;

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, context: Context) !void {
    _ = allocator;
    _ = context;

    var sum: usize = 0;
    sum += 0;

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
