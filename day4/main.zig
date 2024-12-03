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
    const file_name = "day4/test_file.txt";
    //const file_name = "day4/test_cases.txt";
    //const file_name = "day4/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);

    const context = Context{
        .delimiters = delimiters,
    };

    const parsed_lines = try process.FileParser(Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        context,
        file_name,
    );
    defer parsed_lines.deinit();

    // const stdout = std.io.getStdOut();
    // for (context1.ops.items) |op| {
    //     try op.print(stdout.writer());
    //     try stdout.writeAll("\n");
    // }

    try calculate(arena_allocator.allocator(), parsed_lines);
    try calculate_2(arena_allocator.allocator(), parsed_lines);
}

fn parse_line(allocator: std.mem.Allocator, context: Context, line: []const u8) !Line {
    var parser = process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    //Do parsing

    return .{};
}

fn calculate(allocator: std.mem.Allocator, lines: std.ArrayList(Line)) !void {
    _ = allocator;
    _ = lines;
    const sum = 0;
    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, lines: std.ArrayList(Line)) !void {
    _ = allocator;
    _ = lines;
    const sum = 0;
    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
