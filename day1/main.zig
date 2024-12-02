const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;

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

    const parsed_lines = try process.FileParser(Context, Line, parse_line).parse(
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
    var parser = process.LineParser().init(allocator, context.delimiters, line);

    const v1 = try parser.read_int(i32, 10);
    const v2 = try parser.read_int(i32, 10);

    try context.list1.append(v1);
    try context.list2.append(v2);

    return .{
        .v1 = v1,
        .v2 = v2,
    };
}

fn calculate(allocator: std.mem.Allocator, context: Context) !void {
    //sort the lists first
    std.mem.sort(i32, context.list1.items, {}, comptime std.sort.asc(i32));
    std.mem.sort(i32, context.list2.items, {}, comptime std.sort.asc(i32));

    const zip = iteration.Zip(i32, i32, u32).init(allocator);
    const diff_func = struct {
        fn diff(alloc: std.mem.Allocator, v1: i32, v2: i32) !u32 {
            _ = alloc;
            return @abs(v2 - v1);
        }
    }.diff;
    const res = try zip.zip(context.list1.items, context.list2.items, diff_func);
    const diffs = std.ArrayList(u32).fromOwnedSlice(allocator, res);
    defer diffs.deinit();

    //Final value is the sum of these
    const folder = iteration.Fold(u32, u32).init(allocator);
    const combiner = struct {
        pub fn fold(alloc: std.mem.Allocator, acc: u32, item: u32) !u32 {
            _ = alloc;
            return acc + item;
        }
    }.fold;
    const sum = try folder.fold(0, diffs.items, combiner);

    try std.io.getStdOut().writer().print("Sum is {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, context: Context) !void {
    //collect the number of times a number appears in the second list
    var occurrances = std.AutoArrayHashMap(i32, u32).init(allocator);
    defer occurrances.deinit();

    //NOTE: convert to fold?
    for (context.list2.items) |value| {
        const occurs = occurrances.get(value) orelse 0;
        try occurrances.put(value, occurs + 1);
    }

    //Now calculate the similarity score - NOTE:  convert to fold?
    var score: u64 = 0;
    for (context.list1.items) |value| {
        const occurs = occurrances.get(value) orelse 0;
        score += @as(u64, @abs(value)) * @as(u64, occurs);
    }

    try std.io.getStdOut().writer().print("Similarity Score is {d}\n", .{score});
}
