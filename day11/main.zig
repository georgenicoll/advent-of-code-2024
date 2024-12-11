const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Num = u64;

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
};

const Line = struct {
    stones: std.ArrayList(Num),
};

pub fn main() !void {
    const day = "day11";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

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
    var line = parsed_lines.items[0];

    // const stdout = std.io.getStdOut();
    // for (context.grid.items) |row| {
    //     try stdout.writeAll(row.items);
    //     try stdout.writeAll("\n");
    // }
    // try stdout.writer().print("width: {d}, height: {d}\n", .{ context.width, context.height });

    try calculate1(arena_allocator.allocator(), &line.stones);
    try calculate2(arena_allocator.allocator(), &line.stones);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    var parser = shared.process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    var stones = std.ArrayList(Num).init(allocator);

    var number = parser.read_int(Num, 10) catch null;
    while (number != null) {
        try stones.append(number.?);
        number = parser.read_int(Num, 10) catch null;
    }

    return Line{
        .stones = stones,
    };
}

fn generateNextStones(
    number_as_string: *std.ArrayList(u8),
    stone: Num,
    next_stones: *std.ArrayList(Num),
) !void {
    next_stones.clearRetainingCapacity();
    //If the stone is engraved with the number 0, it is replaced by a stone engraved with the number 1.
    if (stone == 0) {
        try next_stones.append(1);
        return;
    }

    number_as_string.clearRetainingCapacity();
    try number_as_string.writer().print("{d}", .{stone});
    //If the stone is engraved with a number that has an even number of digits, it is replaced by two stones.
    //The left half of the digits are engraved on the new left stone, and the right half of the digits are engraved on the new right stone.
    //(The new numbers don't keep extra leading zeroes: 1000 would become stones 10 and 0.)
    if (number_as_string.items.len % 2 == 0) {
        const first_half = number_as_string.items[0 .. number_as_string.items.len / 2];
        const second_half = number_as_string.items[number_as_string.items.len / 2 ..];
        try next_stones.append(try std.fmt.parseInt(Num, first_half, 10));
        try next_stones.append(try std.fmt.parseInt(Num, second_half, 10));
        return;
    }

    //If none of the other rules apply, the stone is replaced by a new stone; the old stone's number multiplied by 2024 is engraved on the new stone.
    try next_stones.append(stone * 2024);
}

/// run a number of iterations
/// although ordering is mentioned in the task - ordering is not important so the stones
/// can be aggregated in each run
fn runIterations(
    allocator: std.mem.Allocator,
    stones: *std.ArrayList(Num),
    repetitions: usize,
) !usize {
    var number_string = try std.ArrayList(u8).initCapacity(allocator, 10);
    defer number_string.deinit();

    var nums_this_iteration = std.AutoHashMap(Num, usize).init(allocator);
    defer nums_this_iteration.deinit();

    var number_totals = std.AutoHashMap(Num, usize).init(allocator);
    defer number_totals.deinit();

    var next_stones = try std.ArrayList(Num).initCapacity(allocator, 2);
    defer next_stones.deinit();

    //first iteration each number has 1 instance
    for (stones.items) |stone| {
        try nums_this_iteration.put(stone, 1);
    }

    for (0..repetitions) |rep| {
        number_totals.clearRetainingCapacity();
        var stones_iterator = nums_this_iteration.iterator();
        while (stones_iterator.next()) |entry| {
            const stone = entry.key_ptr.*;
            const number = entry.value_ptr.*;
            try generateNextStones(&number_string, stone, &next_stones);
            for (next_stones.items) |next_stone| {
                const stone_total_entry = try number_totals.getOrPut(next_stone);
                if (stone_total_entry.found_existing) {
                    stone_total_entry.value_ptr.* += number;
                } else {
                    stone_total_entry.value_ptr.* = number;
                }
            }
        }
        //Set up for next iteration
        if (rep < repetitions - 1) {
            nums_this_iteration.clearRetainingCapacity();
            var totals_iterator = number_totals.iterator();
            while (totals_iterator.next()) |entry| {
                try nums_this_iteration.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    //final calc
    var sum: usize = 0;
    var totals_iterator = number_totals.valueIterator();
    while (totals_iterator.next()) |value| {
        sum += value.*;
    }
    return sum;
}

fn calculate1(allocator: std.mem.Allocator, stones: *std.ArrayList(Num)) !void {
    const count = try runIterations(allocator, stones, 25);
    try std.io.getStdOut().writer().print("Part 1 Count {d}\n", .{count});
}

fn calculate2(allocator: std.mem.Allocator, stones: *std.ArrayList(Num)) !void {
    const count = try runIterations(allocator, stones, 75);
    try std.io.getStdOut().writer().print("Part 2 Count {d}\n", .{count});
}
