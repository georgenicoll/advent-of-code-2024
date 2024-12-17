const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Num = usize;

const Context = struct {
    const Self = @This();

    delimiters: std.AutoHashMap(u8, bool),
    register_a: ?Num = null,
    register_b: ?Num = null,
    register_c: ?Num = null,
    program: std.ArrayList(Num),

    fn print(self: Self, writer: anytype) !void {
        try writer.print("A: {d}, B: {d}, C: {d}\n\n", .{ self.register_a.?, self.register_b.?, self.register_c.? });
        try writer.writeAll("Program: ");
        for (self.program.items) |item| {
            try writer.print("{d},", .{item});
        }
        try writer.writeAll("\n\n");
    }
};

const Line = struct {};

pub fn main() !void {
    const day = "day17";
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

    var program = try std.ArrayList(Num).initCapacity(arena_allocator.allocator(), 100);
    defer program.deinit();

    var context = Context{
        .delimiters = delimiters,
        .program = program,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    try calculate(arena_allocator.allocator(), &context);
    try calculate_2(arena_allocator.allocator(), &context);
}

fn read_register(allocator: std.mem.Allocator, parser: *shared.process.LineParser()) !Num {
    const register_string = try parser.read_string();
    defer allocator.free(register_string);
    const register_name = try parser.read_string();
    defer allocator.free(register_name);
    return try parser.read_int(Num, 10);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    if (line.len == 0) {
        return .{};
    }

    var parser = shared.process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    if (context.register_a == null) {
        context.register_a = try read_register(allocator, &parser);
        return .{};
    }
    if (context.register_b == null) {
        context.register_b = try read_register(allocator, &parser);
        return .{};
    }
    if (context.register_c == null) {
        context.register_c = try read_register(allocator, &parser);
        return .{};
    }

    const program_string = try parser.read_string();
    defer allocator.free(program_string);

    var value = parser.read_int(Num, 10) catch null;
    while (value != null) {
        try context.program.append(value.?);
        value = parser.read_int(Num, 10) catch null;
    }

    return .{};
}

const Registers = struct {
    reg_a: Num,
    reg_b: Num,
    reg_c: Num,
};

fn comboOperand(operand: Num, registers: *const Registers) Num {
    const combo_op = switch (operand) {
        0, 1, 3 => |value| value,
        4 => registers.reg_a,
        5 => registers.reg_b,
        6 => registers.reg_c,
        else => @panic("Invalid operand"),
    };
    return combo_op;
}

/// Run the op, if we should jump to a new instruction pointer, returns that, otherwise increment as usual
fn runOp(output: *std.ArrayList(Num), registers: *Registers, op_code: Num, operand: Num) !?usize {
    switch (op_code) {
        0 => { //adv
            const numerator = registers.reg_a;
            const denominator = std.math.pow(Num, 2, comboOperand(operand, registers));
            const result = @divTrunc(numerator, denominator);
            registers.reg_a = result;
        },
        1 => { //bxl
            const result = registers.reg_b ^ operand;
            registers.reg_b = result;
        },
        2 => { //bst
            const combo = comboOperand(operand, registers);
            registers.reg_b = @mod(combo, 8);
        },
        3 => { //jnz
            if (registers.reg_a != 0) {
                return @as(usize, @intCast(operand)); //set instruction pointer
            }
        },
        4 => { //bxc
            registers.reg_b = registers.reg_b ^ registers.reg_c;
        },
        5 => { //out
            const value = @mod(comboOperand(operand, registers), 8);
            try output.append(value);
        },
        6 => { //bdv
            const numerator = registers.reg_a;
            const denominator = std.math.pow(Num, 2, comboOperand(operand, registers));
            const result = @divTrunc(numerator, denominator);
            registers.reg_b = result;
        },
        7 => { //cdv
            const numerator = registers.reg_a;
            const denominator = std.math.pow(Num, 2, comboOperand(operand, registers));
            const result = @divTrunc(numerator, denominator);
            registers.reg_c = result;
        },
        else => @panic("Unrecognised op_code"),
    }
    return null;
}

/// Run the program, if the output limit is breached return false, otherwise return true
fn run(context: *const Context, output: *std.ArrayList(Num)) !void {
    var registers = Registers{
        .reg_a = context.register_a.?,
        .reg_b = context.register_b.?,
        .reg_c = context.register_c.?,
    };
    var instruction_pointer: usize = 0;
    while (instruction_pointer < context.program.items.len) {
        const op_code = context.program.items[instruction_pointer];
        const operand = context.program.items[instruction_pointer + 1];

        const jump_to = try runOp(output, &registers, op_code, operand);
        if (jump_to) |new_instruction_pointer| {
            instruction_pointer = new_instruction_pointer;
        } else instruction_pointer += 2;
    }
}

fn calculate(allocator: std.mem.Allocator, context: *Context) !void {
    try context.print(std.io.getStdOut().writer());

    var output = try std.ArrayList(Num).initCapacity(allocator, 1000);
    defer output.deinit();

    try run(context, &output);

    try std.io.getStdOut().writeAll("Part 1 Output:  \n");
    for (output.items) |item| {
        try std.io.getStdOut().writer().print("{d},", .{item});
    }
    try std.io.getStdOut().writeAll("\n");
}

fn calculate_2(allocator: std.mem.Allocator, context: *Context) !void {
    const input_registers = Registers{
        .reg_a = context.register_a.?,
        .reg_b = context.register_b.?,
        .reg_c = context.register_c.?,
    };

    var output = try std.ArrayList(Num).initCapacity(allocator, context.program.items.len + 1);
    defer output.deinit();
    //Loop through in reverse seeing if we can build up the input
    var a: Num = 0;
    while (true) {
        a <<= 3; //shift 3 bits left

        while (true) {
            context.register_a = a;
            context.register_b = input_registers.reg_b;
            context.register_c = input_registers.reg_c;

            output.clearRetainingCapacity();

            try run(context, &output);
            const output_length = output.items.len;
            const to_check_from_index = context.program.items.len - output_length;
            if (eql(Num, context.program.items[to_check_from_index..], output.items)) {
                break; //got it
            }

            a += 1;
        }

        if (output.items.len >= context.program.items.len) {
            break;
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Reg A {d}\n", .{a});
}

const expect = std.testing.expect;

test "division" {
    const num: Num = 5;
    const denom: Num = 2;
    try expect(num / denom == 2);
}
