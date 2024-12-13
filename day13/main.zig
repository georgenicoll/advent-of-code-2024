const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Num = i64;

const Comb = struct {
    x: Num,
    y: Num,
};

const Machine = struct {
    const Self = @This();

    button_a: Comb,
    button_b: Comb,
    prize: Comb,

    fn print(self: Self, writer: anytype) !void {
        try writer.print("A: {d},{d}, B: {d},{d}, Prize: {d},{d}", .{
            self.button_a.x, self.button_a.y,
            self.button_b.x, self.button_b.y,
            self.prize.x,    self.prize.y,
        });
    }
};

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
    current_machine: ?Machine,
    machines: *std.ArrayList(Machine),
};

const Line = struct {};

pub fn main() !void {
    const day = "day13";
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
    try delimiters.put(',', true);
    try delimiters.put('+', true);
    try delimiters.put('X', true);
    try delimiters.put('Y', true);
    try delimiters.put('=', true);

    var machines = try std.ArrayList(Machine).initCapacity(arena_allocator.allocator(), 1000);
    defer machines.deinit();

    var context = Context{
        .delimiters = delimiters,
        .current_machine = null,
        .machines = &machines,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    // const stdout = std.io.getStdOut();
    // for (machines.items) |machine| {
    //     try machine.print(stdout.writer());
    //     try stdout.writeAll("\n");
    // }
    // try stdout.writer().print("Read in {d} machines...\n", .{machines.items.len});

    try calculate(arena_allocator.allocator(), &machines);
    try calculate_2(arena_allocator.allocator(), &machines);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    if (!(line.len > 0)) {
        return .{};
    }

    if (context.current_machine == null) {
        context.current_machine = Machine{
            .button_a = Comb{ .x = 0, .y = 0 },
            .button_b = Comb{ .x = 0, .y = 0 },
            .prize = Comb{ .x = 0, .y = 0 },
        };
    }

    var parser = shared.process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    //read the text (Button or Prize)
    const button_or_prize = try parser.read_string();
    defer allocator.free(button_or_prize);
    if (context.current_machine.?.button_b.x == 0) {
        //read the next button name (only for buttons)
        const button_name = try parser.read_string();
        defer allocator.free(button_name);
    }

    const x = try parser.read_int(Num, 10);
    const y = try parser.read_int(Num, 10);

    if (context.current_machine.?.button_a.x == 0) {
        context.current_machine.?.button_a.x = x;
        context.current_machine.?.button_a.y = y;
    } else if (context.current_machine.?.button_b.x == 0) {
        context.current_machine.?.button_b.x = x;
        context.current_machine.?.button_b.y = y;
    } else {
        context.current_machine.?.prize.x = x;
        context.current_machine.?.prize.y = y;
        try context.machines.append(context.current_machine.?);
        context.current_machine = null;
    }

    return .{};
}

const Presses = struct {
    a: usize,
    b: usize,
};

const NUM_AS_FLOAT = f128;
const DIFF = 0.0000000001;

fn positiveIntFromFloatNoRounding(num: NUM_AS_FLOAT) ?usize {
    if (num < 0) {
        return null;
    }
    const num_int: usize = @intFromFloat(num);
    //Check is an integer
    const back_to_float = @as(NUM_AS_FLOAT, @floatFromInt(num_int));
    if (@abs(back_to_float - num) > DIFF) {
        return null;
    }
    return num_int;
}

fn solve(machine: Machine) ?Presses {
    // 2 simultaneous equations with 2 unknowns...
    // 1: A.a_x + B.b_x = p_x
    // 2: A.a_y + B.b_y = p_y
    // rearranges to
    // B = (p_x.a_y - p_y.a_x) / (b_x.a_y - b_y.a_x)
    const a_x = @as(NUM_AS_FLOAT, @floatFromInt(machine.button_a.x));
    const a_y = @as(NUM_AS_FLOAT, @floatFromInt(machine.button_a.y));
    const b_x = @as(NUM_AS_FLOAT, @floatFromInt(machine.button_b.x));
    const b_y = @as(NUM_AS_FLOAT, @floatFromInt(machine.button_b.y));
    const p_x = @as(NUM_AS_FLOAT, @floatFromInt(machine.prize.x));
    const p_y = @as(NUM_AS_FLOAT, @floatFromInt(machine.prize.y));

    const num_b_presses = (p_x * a_y - p_y * a_x) / (b_x * a_y - b_y * a_x);
    const b = positiveIntFromFloatNoRounding(num_b_presses);
    if (b == null) {
        return null;
    }

    const num_a_presses = (p_x - num_b_presses * b_x) / a_x;
    const a = positiveIntFromFloatNoRounding(num_a_presses);
    if (a == null) {
        return null;
    }

    return .{ .a = a.?, .b = b.? };
}

fn calculate(allocator: std.mem.Allocator, machines: *std.ArrayList(Machine)) !void {
    _ = allocator;

    var sum: usize = 0;

    for (machines.items) |machine| {
        if (solve(machine)) |solution| {
            const cost = solution.a * 3 + solution.b * 1;
            sum += cost;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Total Cost {d}\n", .{sum});
}

const ADDITION = 10000000000000;

fn calculate_2(allocator: std.mem.Allocator, machines: *std.ArrayList(Machine)) !void {
    _ = allocator;

    var sum: usize = 0;

    for (machines.items) |machine| {
        //adjust the prize...
        const new_machine = Machine{
            .button_a = machine.button_a,
            .button_b = machine.button_b,
            .prize = Comb{
                .x = machine.prize.x + ADDITION,
                .y = machine.prize.y + ADDITION,
            },
        };
        if (solve(new_machine)) |solution| {
            const cost = solution.a * 3 + solution.b * 1;
            sum += cost;
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Total Cost {d}\n", .{sum});
}
