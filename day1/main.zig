const std = @import("std");
const process = @import("shared").process;

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
    list1: *std.ArrayList(i32),
    list2: *std.ArrayList(i32),
};

const Line = struct {
    v1: i32,
    v2: i32,

    fn print(self: Line, writer: anytype) !void {
        try writer.print("v1={d}, v2={d}", self);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);

    var list1 = std.ArrayList(i32).init(gpa.allocator());
    defer list1.deinit();
    var list2 = std.ArrayList(i32).init(gpa.allocator());
    defer list2.deinit();
    const context = Context{
        .delimiters = delimiters,
        .list1 = &list1,
        .list2 = &list2,
    };

    //const file_name = "day1/test_file.txt";
    const file_name = "day1/input.txt";

    const parsed_lines = try process.parse_file(
        Context,
        Line,
        parse_line,
        arena_allocator.allocator(),
        context,
        file_name,
    );
    defer parsed_lines.deinit();

    // const stdout = std.io.getStdOut();
    // for (parsed_lines.items) |data| {
    //     try data.print(stdout.writer());
    //     try stdout.writeAll("\n");
    // }

    try calculate(arena_allocator.allocator(), context);
    try calculate_2(arena_allocator.allocator(), context);
}

fn parse_line(allocator: std.mem.Allocator, context: Context, line: []const u8) !Line {
    const next_1 = try process.read_next(allocator, 0, line, context.delimiters);
    defer next_1.next.deinit();
    const value_1 = try std.fmt.parseInt(i32, next_1.next.items, 10);

    const next_2 = try process.read_next(allocator, next_1.new_start, line, context.delimiters);
    defer next_2.next.deinit();
    const value_2 = try std.fmt.parseInt(i32, next_2.next.items, 10);

    try context.list1.append(value_1);
    try context.list2.append(value_2);

    return .{
        .v1 = value_1,
        .v2 = value_2,
    };
}

fn calculate(allocator: std.mem.Allocator, context: Context) !void {
    //sort the lists first
    std.mem.sort(i32, context.list1.items, {}, comptime std.sort.asc(i32));
    std.mem.sort(i32, context.list2.items, {}, comptime std.sort.asc(i32));

    //calculate all of the differences
    var diffs = std.ArrayList(u32).init(allocator);
    defer diffs.deinit();

    //NOTE: create a zip
    var i: usize = 0;
    while (i < context.list1.items.len) : (i += 1) {
        const v1 = context.list1.items[i];
        const v2 = context.list2.items[i];
        const diff = @abs(v2 - v1);
        try diffs.append(diff);
    }

    //Final value is the sum of these - note create a fold
    var sum: u32 = 0;
    for (diffs.items) |diff| {
        sum += diff;
    }

    try std.io.getStdOut().writer().print("Sum is {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, context: Context) !void {
    //collect the number of times a number appears in the second list
    var occurrances = std.AutoArrayHashMap(i32, u32).init(allocator);
    defer occurrances.deinit();

    for (context.list2.items) |value| {
        const occurs = occurrances.get(value) orelse 0;
        try occurrances.put(value, occurs + 1);
    }

    //Now calculate the similarity score
    var score: u64 = 0;
    for (context.list1.items) |value| {
        const occurs = occurrances.get(value) orelse 0;
        score += @as(u64, @abs(value)) * @as(u64, occurs);
    }

    try std.io.getStdOut().writer().print("Similarity Score is {d}\n", .{score});
}