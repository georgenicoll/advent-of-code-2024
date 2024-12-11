const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Num = u64;

const Node = struct {
    value: ?Num,
    left: ?*Node,
    right: ?*Node,
};

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
};

const Line = struct {
    stones: std.ArrayList(*Node),
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

    var delimiters1 = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters1.put(' ', true);

    var context1 = Context{
        .delimiters = delimiters1,
    };

    const parsed_lines1 = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context1,
        file_name,
    );
    //defer parsed_lines1.deinit(); //deinited on arena_allocator reset
    var line1 = parsed_lines1.items[0];

    // const stdout = std.io.getStdOut();
    // for (context.grid.items) |row| {
    //     try stdout.writeAll(row.items);
    //     try stdout.writeAll("\n");
    // }
    // try stdout.writer().print("width: {d}, height: {d}\n", .{ context.width, context.height });

    try calculate1(arena_allocator.allocator(), &line1.stones);
    _ = arena_allocator.reset(std.heap.ArenaAllocator.ResetMode.free_all);

    var delimiters2 = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters2.put(' ', true);

    var context2 = Context{
        .delimiters = delimiters2,
    };

    const parsed_lines2 = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context2,
        file_name,
    );
    // defer parsed_lines2.deinit(); //deinited on arena_allocator reset
    var line2 = parsed_lines2.items[0];

    try calculate2(arena_allocator.allocator(), &line2.stones);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    var parser = shared.process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    var stones = std.ArrayList(*Node).init(allocator);

    var number = parser.read_int(Num, 10) catch null;
    while (number != null) {
        const node: *Node = try allocator.create(Node);
        node.* = Node{
            .value = number,
            .left = null,
            .right = null,
        };
        try stones.append(node);
        number = parser.read_int(Num, 10) catch null;
    }

    return Line{
        .stones = stones,
    };
}

///Visit each stone in the tree and perform an operation on it
fn operateOnStone(
    comptime Type: type,
    comptime ContextType: type,
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(*Node),
    stone: *Node,
    initial_value: Type,
    context: ContextType,
    operation: fn (std.mem.Allocator, *Node, Type, ContextType) anyerror!Type,
) !Type {
    //depth first search - visit each node and apply the function
    stack.clearRetainingCapacity();
    try stack.append(stone);

    var current_value: Type = initial_value;

    while (stack.items.len > 0) {
        const current = stack.pop();
        //If this has a right node, visit that - we do this before applying any ops - note - this goes first so that left is processed first
        if (current.right) |right| {
            try stack.append(right);
        }
        //If this has a left node, visit that - we do this before applying any ops - after right, left gets popped first
        if (current.left) |left| {
            try stack.append(left);
        }
        //visit this item
        current_value = try operation(allocator, current, current_value, context);
    }

    return current_value;
}

// Visit all of the stones in the tree and perform an operation on them
fn operateOnStones(
    comptime Type: type,
    comptime ContextType: type,
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(*Node),
    stones: *std.ArrayList(*Node),
    initial_value: Type,
    context: ContextType,
    operation: fn (std.mem.Allocator, *Node, Type, ContextType) anyerror!Type,
) !Type {
    var current_value = initial_value;
    for (stones.items) |stone| {
        current_value = try operateOnStone(Type, ContextType, allocator, stack, stone, current_value, context, operation);
    }
    return current_value;
}

fn outputStones(
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(*Node),
    stones: *std.ArrayList(*Node),
) !void {
    const outputOp = struct {
        fn outputOp(alloc: std.mem.Allocator, stone: *Node, ignored_value: void, ignored_context: void) !void {
            _ = alloc;
            _ = ignored_value;
            _ = ignored_context;
            if (stone.value) |value| {
                try std.io.getStdOut().writer().print("{d} ", .{value});
            }
        }
    }.outputOp;
    try operateOnStones(void, void, allocator, stack, stones, {}, {}, outputOp);
}

fn countStones(
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(*Node),
    stones: *std.ArrayList(*Node),
) !usize {
    const countOp = struct {
        fn countOp(alloc: std.mem.Allocator, stone: *Node, count: usize, ignored_context: void) !usize {
            _ = alloc;
            _ = ignored_context;
            if (stone.value) |_| {
                return count + 1;
            }
            return count;
        }
    }.countOp;
    return try operateOnStones(usize, void, allocator, stack, stones, 0, {}, countOp);
}

fn blink(
    allocator: std.mem.Allocator,
    number_as_string: *std.ArrayList(u8),
    stack: *std.ArrayList(*Node),
    stones: *std.ArrayList(*Node),
) !void {
    const OpContext = struct {
        number_as_string: *std.ArrayList(u8),
    };
    const blinkOp = struct {
        fn blinkOp(alloc: std.mem.Allocator, stone: *Node, ignored: void, op_context: OpContext) !void {
            _ = ignored;
            // If we got to a value, then split according to the rules
            if (stone.value) |value| {
                //If the stone is engraved with the number 0, it is replaced by a stone engraved with the number 1.
                if (value == 0) {
                    stone.value = 1;
                    return;
                }

                op_context.number_as_string.clearRetainingCapacity();
                try op_context.number_as_string.writer().print("{d}", .{value});
                //If the stone is engraved with a number that has an even number of digits, it is replaced by two stones.
                //The left half of the digits are engraved on the new left stone, and the right half of the digits are engraved on the new right stone.
                //(The new numbers don't keep extra leading zeroes: 1000 would become stones 10 and 0.)
                if (op_context.number_as_string.items.len % 2 == 0) {
                    const first_half = op_context.number_as_string.items[0 .. op_context.number_as_string.items.len / 2];
                    const second_half = op_context.number_as_string.items[op_context.number_as_string.items.len / 2 ..];
                    const left_value = try std.fmt.parseInt(Num, first_half, 10);
                    const right_value = try std.fmt.parseInt(Num, second_half, 10);
                    stone.value = null;
                    const left: *Node = try alloc.create(Node);
                    left.* = Node{
                        .value = left_value,
                        .left = null,
                        .right = null,
                    };
                    stone.left = left;
                    const right: *Node = try alloc.create(Node);
                    right.* = Node{
                        .value = right_value,
                        .left = null,
                        .right = null,
                    };
                    stone.right = right;
                    return;
                }
                //If none of the other rules apply, the stone is replaced by a new stone; the old stone's number multiplied by 2024 is engraved on the new stone.
                stone.value = value * 2024;
            }
        }
    }.blinkOp;
    try operateOnStones(
        void,
        OpContext,
        allocator,
        stack,
        stones,
        {},
        .{ .number_as_string = number_as_string },
        blinkOp,
    );
}

fn calculate(allocator: std.mem.Allocator, stack: *std.ArrayList(*Node), stones: *std.ArrayList(*Node), repetitions: usize) !usize {
    var number_as_string = try std.ArrayList(u8).initCapacity(allocator, 20);
    defer number_as_string.deinit();

    // try outputStones(allocator, stack, stones);
    // try std.io.getStdOut().writeAll("\n");

    for (0..repetitions) |i| {
        _ = i;
        // try std.io.getStdOut().writer().print("Rep {d}\n", .{i});
        try blink(allocator, &number_as_string, stack, stones);
        // try outputStones(allocator, &stack, stones);
        //const rep_count = try countStones(allocator, &stack, stones);
        //try std.io.getStdOut().writer().print(":{d}\n", .{rep_count});
    }

    const count = try countStones(allocator, stack, stones);
    return count;
}

fn calculate1(allocator: std.mem.Allocator, stones: *std.ArrayList(*Node)) !void {
    var stack = try std.ArrayList(*Node).initCapacity(allocator, 1000);
    defer stack.deinit();
    const count = try calculate(allocator, &stack, stones, 25);
    try std.io.getStdOut().writer().print("Part 1 Count {d}\n", .{count});
}

fn gatherNumbers(
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(*Node),
    numbers: *std.AutoHashMap(Num, usize),
    stones: *std.ArrayList(*Node),
) !void {
    const OpContext = struct {
        numbers: *std.AutoHashMap(Num, usize),
    };
    const gatherOp = struct {
        fn gatherOp(alloc: std.mem.Allocator, stone: *Node, ignored: void, op_context: OpContext) !void {
            _ = alloc;
            _ = ignored;
            if (stone.value) |value| {
                var nums = op_context.numbers;
                const res = try nums.getOrPut(value);
                if (res.found_existing) {
                    res.value_ptr.* += 1;
                } else {
                    res.value_ptr.* = 1;
                }
            }
        }
    }.gatherOp;
    const op_context = OpContext{
        .numbers = numbers,
    };
    return try operateOnStones(void, OpContext, allocator, stack, stones, {}, op_context, gatherOp);
}

fn getIterationNumbers(
    allocator: std.mem.Allocator,
    stack: *std.ArrayList(*Node),
    repetitions: usize,
    num: Num,
    generated_by_number: *std.AutoHashMap(Num, *std.AutoHashMap(Num, usize)),
) !*std.AutoHashMap(Num, usize) {
    //Do we already know which numbers we will generate from this number?
    const generated = try generated_by_number.getOrPut(num);
    if (generated.found_existing) {
        return generated.value_ptr.*;
    }
    //calculate the numbers and add to the map
    const numbers: *std.AutoHashMap(Num, usize) = try allocator.create(std.AutoHashMap(Num, usize));
    numbers.* = std.AutoHashMap(Num, usize).init(allocator);
    generated.value_ptr.* = numbers;

    var stones = try std.ArrayList(*Node).initCapacity(allocator, 1);
    defer stones.deinit();

    var stone = Node{
        .value = num,
        .left = null,
        .right = null,
    };
    try stones.append(&stone);

    _ = try calculate(allocator, stack, &stones, repetitions);
    try gatherNumbers(allocator, stack, numbers, &stones);
    return numbers;
}

fn calculate2(allocator: std.mem.Allocator, stones: *std.ArrayList(*Node)) !void {
    var stack = try std.ArrayList(*Node).initCapacity(allocator, 1000);
    defer stack.deinit();

    var generated_by_number = std.AutoHashMap(Num, *std.AutoHashMap(Num, usize)).init(allocator);
    defer generated_by_number.deinit();

    var numbers_running_total = std.AutoHashMap(Num, usize).init(allocator);
    defer numbers_running_total.deinit();

    var this_iter_nums = std.AutoHashMap(Num, usize).init(allocator);
    defer this_iter_nums.deinit();

    for (stones.items) |stone| {
        try this_iter_nums.put(stone.value.?, 1);
    }

    const rep_size: usize = 5;
    const num_iters: usize = 75 / rep_size;
    for (0..num_iters) |i| { //25 * 3 is 75
        numbers_running_total.clearRetainingCapacity();
        var nums_iter = this_iter_nums.iterator();
        while (nums_iter.next()) |num| {
            const numbers_with_counts = try getIterationNumbers(allocator, &stack, rep_size, num.key_ptr.*, &generated_by_number);
            var it = numbers_with_counts.iterator();
            while (it.next()) |entry| {
                const res = try numbers_running_total.getOrPut(entry.key_ptr.*);
                const total_nums_generated = entry.value_ptr.* * num.value_ptr.*;
                if (res.found_existing) {
                    res.value_ptr.* += total_nums_generated;
                } else {
                    res.value_ptr.* = total_nums_generated;
                }
            }
        }

        //set up for the next iteration
        if (i < num_iters - 1) {
            this_iter_nums.clearRetainingCapacity();
            var it = numbers_running_total.iterator();
            while (it.next()) |entry| {
                try this_iter_nums.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    //Total them all up from the final iteration
    var count: usize = 0;
    var it = numbers_running_total.iterator();
    while (it.next()) |entry| {
        count += entry.value_ptr.*;
    }

    try std.io.getStdOut().writer().print("Part 2 Count {d}\n", .{count});
}
