const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
};

const Num = u64;

const Line = struct {
    result: Num,
    numbers: []const Num,

    fn print(self: Line, writer: anytype) !void {
        try writer.print("{d}: ", .{self.result});
        for (self.numbers) |number| {
            try writer.print("{d} ", .{number});
        }
    }
};

// Timings on old surface laptop:
// zig build: ~8s
// zig build --release=fast: ~0.5s
// Timings on trigkey - not using fized buffer allocator on part 2:
// zig build: ~6s
// zig build --release=fast: ~0.25s
// Timings on trigkey - using fized buffer allocator on part 2:
// zig build: ~5.8s
// zig build --release=fast: ~0.25s
pub fn main() !void {
    const day = "day7";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);
    try delimiters.put(':', true);

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
    // for (parsed_lines.items) |line| {
    //     try line.print(stdout.writer());
    //     try stdout.writeAll("\n");
    // }

    try calculate(arena_allocator.allocator(), parsed_lines);
    try calculate_2(arena_allocator.allocator(), parsed_lines);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    var parser = process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    const result = try parser.read_int(Num, 10);
    var numbers = std.ArrayList(Num).init(allocator);
    defer numbers.deinit();

    var number = parser.read_int(Num, 10) catch null;
    while (number != null) {
        try numbers.append(number.?);
        number = parser.read_int(Num, 10) catch null;
    }

    return .{
        .result = result,
        .numbers = try numbers.toOwnedSlice(),
    };
}

const concat_expected_integer_digits = 10;
const concat_combined_integer_digits = concat_expected_integer_digits * 2;

fn concat(allocator: std.mem.Allocator, a: Num, b: Num) !Num {
    var num1 = try std.ArrayList(u8).initCapacity(allocator, concat_combined_integer_digits);
    defer num1.deinit();
    var num2 = try std.ArrayList(u8).initCapacity(allocator, concat_expected_integer_digits);
    defer num2.deinit();

    try num1.writer().print("{d}", .{a});
    try num2.writer().print("{d}", .{b});
    try num1.appendSlice(num2.items);

    return try std.fmt.parseInt(Num, num1.items, 10);
}

const Op = enum {
    Add,
    Multiply,
    Concat,

    fn calculate(self: Op, allocator: std.mem.Allocator, a: Num, b: Num) !Num {
        return switch (self) {
            Op.Add => |_| a + b,
            Op.Multiply => |_| a * b,
            Op.Concat => |_| try concat(allocator, a, b),
        };
    }
};

const Level = struct {
    op: Op,
    level: usize,
    result_so_far: Num,
};

fn is_possible(allocator: std.mem.Allocator, line: Line, stack: *std.ArrayList(Level), allowed_ops: []const Op) !bool {
    stack.clearRetainingCapacity();

    //first ops. level correspond to left number's index
    for (allowed_ops) |op| {
        try stack.append(Level{
            .op = op,
            .level = 0,
            .result_so_far = line.numbers[0],
        });
    }

    while (stack.items.len > 0) {
        const level = stack.pop();

        const next_level = level.level + 1;
        const next_value = line.numbers[next_level];
        const next_result_so_far = try level.op.calculate(allocator, level.result_so_far, next_value);

        //did we reach the end??? check the value - we don't add any more
        if (next_level >= line.numbers.len - 1) {
            if (next_result_so_far == line.result) {
                return true;
            }
            continue;
        }

        //If this is greater or equal to expected, stop looking on this branch now
        if (next_result_so_far > line.result) {
            continue;
        }

        //Otherwise, search the next operations
        for (allowed_ops) |op| {
            try stack.append(Level{
                .op = op,
                .level = next_level,
                .result_so_far = next_result_so_far,
            });
        }
    }

    return false; //nothing worked
}

fn calculate(allocator: std.mem.Allocator, lines: std.ArrayList(Line)) !void {
    var stack = try std.ArrayList(Level).initCapacity(allocator, 2000);
    defer stack.deinit();

    var sum: usize = 0;

    for (lines.items) |line| {
        if (try is_possible(allocator, line, &stack, &[_]Op{ Op.Add, Op.Multiply })) {
            sum += line.result;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, lines: std.ArrayList(Line)) !void {
    var stack = try std.ArrayList(Level).initCapacity(allocator, 2000);
    defer stack.deinit();

    // Following can only be done as we know that we only need the allocater in is_possible for the conact call
    // and this needs 2 buffers of size concat_combined_integer_digits + concat_expected_integer_digits
    var buffer: [concat_combined_integer_digits + concat_expected_integer_digits]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fba_allocator = fba.allocator();

    var sum: usize = 0;

    for (lines.items) |line| {
        if (try is_possible(fba_allocator, line, &stack, &[_]Op{ Op.Add, Op.Multiply, Op.Concat })) {
            sum += line.result;
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}

const expect = std.testing.expect;
const testing_allocator = std.testing.allocator;

test "concat" {
    try expect(try concat(testing_allocator, 1, 2) == 12);
    try expect(try concat(testing_allocator, 11, 387) == 11387);
}
