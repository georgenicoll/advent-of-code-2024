const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Num = u128;

const Context = struct {
    numbers: *std.ArrayList(Num),
};

const Line = struct {};

pub fn main() !void {
    const day = "day22";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var numbers = std.ArrayList(Num).init(arena_allocator.allocator());
    defer numbers.deinit();

    var context = Context{
        .numbers = &numbers,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    try calculate(arena_allocator.allocator(), &context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;
    const number = try std.fmt.parseInt(Num, line, 10);
    try context.numbers.append(number);
    return .{};
}

const SequenceValues = struct {
    const Self = @This();

    a: i8,
    b: i8,
    c: i8,
    d: i8,

    fn init(sequence: *std.ArrayList(i8)) Self {
        return Self{
            .a = sequence.items[0],
            .b = sequence.items[1],
            .c = sequence.items[2],
            .d = sequence.items[3],
        };
    }

    fn areAllChanges(self: Self) bool {
        return self.a != 0 and self.b != 0 and self.c != 0 and self.d != 0;
    }

    fn print(self: Self, writer: anytype) !void {
        try writer.print("{d},{d},{d},{d}", .{ self.a, self.b, self.c, self.d });
    }
};

const PriceForNumberIndex = std.AutoHashMap(usize, usize);

fn calculateSecret(
    allocator: std.mem.Allocator,
    number: Num,
    number_index: usize,
    base: usize,
    repetitions: usize,
    string: *std.ArrayList(u8),
    sequence: *std.ArrayList(i8),
    first_price_for_number_index_by_sequence: *std.AutoHashMap(SequenceValues, *PriceForNumberIndex),
) !Num {
    sequence.clearRetainingCapacity();

    var current = number;

    string.clearRetainingCapacity();
    try string.writer().print("{d}", .{current});
    var previous_digit: i8 = try std.fmt.parseInt(i8, string.items[string.items.len - 1 ..], 10);

    for (0..repetitions) |_| {
        var next = current * 64;
        next = next ^ current; //mix
        next = next % base; //prune
        var next2 = @divTrunc(next, 32);
        next2 = next2 ^ next; //mix
        next2 = next2 % base; //prune
        var next3 = next2 * 2048;
        next3 = next3 ^ next2; //mix
        next3 = next3 % base; //prune
        current = next3;

        string.clearRetainingCapacity();
        try string.writer().print("{d}", .{current});
        const one_digit: i8 = try std.fmt.parseInt(i8, string.items[string.items.len - 1 ..], 10);

        const diff = one_digit - previous_digit;
        try sequence.append(diff);
        while (sequence.items.len > 4) {
            _ = sequence.orderedRemove(0);
        }
        if (sequence.items.len == 4) {
            const sequence_values = SequenceValues.init(sequence);
            //only interested in 4 consecutive changes
            // if (sequence_values.areAllChanges()) {
            const first_price_for_number_index_result = try first_price_for_number_index_by_sequence.getOrPut(sequence_values);
            if (!first_price_for_number_index_result.found_existing) {
                const first_price_for_number_index: *PriceForNumberIndex = try allocator.create(PriceForNumberIndex);
                first_price_for_number_index.* = PriceForNumberIndex.init(allocator);
                first_price_for_number_index_result.value_ptr.* = first_price_for_number_index;
            }
            const price_for_number_index = first_price_for_number_index_result.value_ptr.*;
            const price_result = try price_for_number_index.getOrPut(number_index);
            if (!price_result.found_existing) { //only care about the first we find
                price_result.value_ptr.* = @as(usize, @intCast(one_digit));
            }
            // }
        }

        previous_digit = one_digit;
    }
    return current;
}

fn calculate(allocator: std.mem.Allocator, context: *const Context) !void {
    var string = try std.ArrayList(u8).initCapacity(allocator, 30);
    defer string.deinit();
    var sequence = try std.ArrayList(i8).initCapacity(allocator, 5);
    defer sequence.deinit();
    var first_price_for_number_index_by_sequence = std.AutoHashMap(SequenceValues, *PriceForNumberIndex).init(allocator);
    defer first_price_for_number_index_by_sequence.deinit();

    var sum: Num = 0;
    for (context.numbers.items, 0..) |number, number_index| {
        const new_secret = try calculateSecret(
            allocator,
            number,
            number_index,
            16777216,
            2000,
            &string,
            &sequence,
            &first_price_for_number_index_by_sequence,
        );
        sum += new_secret;
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});

    //work through each possible sequence finding the maximum price for all sequences
    var max_sum_so_far: usize = 0;
    var max_price_sequence_values = SequenceValues{ .a = 0, .b = 0, .c = 0, .d = 0 };
    var by_sequence_it = first_price_for_number_index_by_sequence.iterator();
    while (by_sequence_it.next()) |by_sequence_entry| {
        var sum2: usize = 0;
        var by_number_index_it = by_sequence_entry.value_ptr.*.iterator();
        while (by_number_index_it.next()) |by_number_index_entry| {
            sum2 += by_number_index_entry.value_ptr.*;
        }
        if (sum2 > max_sum_so_far) {
            max_sum_so_far = sum2;
            max_price_sequence_values = by_sequence_entry.key_ptr.*;
        }
    }

    try std.io.getStdOut().writer().writeAll("Part 2, Sequence: ");
    try max_price_sequence_values.print(std.io.getStdOut().writer());
    try std.io.getStdOut().writer().print(", Sum {d}\n", .{max_sum_so_far});
}
