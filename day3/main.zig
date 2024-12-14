const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context1 = struct {
    ops: *std.ArrayList(Mul),
};

const Context2 = struct {
    ops: *std.ArrayList(Op),
};

const Num = i64;

const Mul = struct {
    a: Num,
    b: Num,

    pub fn print(self: Mul, writer: anytype) !void {
        try writer.print("mul({d},{d})", self);
    }
};

const Do = struct {
    pub fn print(self: Do, writer: anytype) !void {
        _ = self;
        try writer.print("do", .{});
    }
};

const Dont = struct {
    pub fn print(self: Dont, writer: anytype) !void {
        _ = self;
        try writer.print("dont", .{});
    }
};

const Op = union(enum) {
    mul: Mul,
    do: Do,
    dont: Dont,

    pub fn print(self: Op, writer: anytype) !void {
        switch (self) {
            .mul => |mul| try mul.print(writer),
            .do => |do| try do.print(writer),
            .dont => |dont| try dont.print(writer),
        }
    }
};

const Line = struct {};

pub fn main() !void {
    // const stdout = std.io.getStdOut();

    //const file_name = "day3/test_file.txt";
    //const file_name = "day3/test_cases.txt";
    const file_name = "day3/input.txt";
    //const file_name2 = "day3/test_file2.txt";
    //const file_name2 = "day3/test_cases.txt";
    const file_name2 = "day3/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var ops1 = std.ArrayList(Mul).init(arena_allocator.allocator());
    defer ops1.deinit();

    const context1 = Context1{
        .ops = &ops1,
    };

    const parsed_lines1 = try process.FileParser(Context1, Line, parse_line1).parse(
        arena_allocator.allocator(),
        context1,
        file_name,
    );
    defer parsed_lines1.deinit();

    // for (context1.ops.items) |op| {
    //     try op.print(stdout.writer());
    //     try stdout.writeAll("\n");
    // }

    try calculate(arena_allocator.allocator(), context1.ops);

    var ops2 = std.ArrayList(Op).init(arena_allocator.allocator());
    defer ops2.deinit();

    const context2 = Context2{
        .ops = &ops2,
    };

    const parsed_lines2 = try process.FileParser(Context2, Line, parse_line2).parse(
        arena_allocator.allocator(),
        context2,
        file_name2,
    );
    defer parsed_lines2.deinit();

    // for (context2.ops.items) |op| {
    //     try op.print(stdout.writer());
    //     try stdout.writeAll("\n");
    // }

    try calculate_2(arena_allocator.allocator(), context2.ops);
}

fn parse_line1(allocator: std.mem.Allocator, context: Context1, line: []const u8) !Line {
    const regex = try shared.regex.Regex.init("(mul)\\(([[:digit:]]+),([[:digit:]]+)\\)");
    defer regex.deinit();

    const matches = try regex.exec(allocator, line);
    for (matches.matches.items) |match| {
        const num1 = match.groups.items[1];
        const num2 = match.groups.items[2];
        const a = try std.fmt.parseInt(Num, num1, 10);
        const b = try std.fmt.parseInt(Num, num2, 10);
        try context.ops.append(Mul{ .a = a, .b = b });
    }

    return .{};
}

const OpString = enum { mul, do, @"don't" };

fn parse_line2(allocator: std.mem.Allocator, context: Context2, line: []const u8) !Line {
    const regex = try shared.regex.Regex.init("(mul)\\(([[:digit:]]+),([[:digit:]]+)\\)|(do)\\(\\)|(don't)\\(\\)");
    defer regex.deinit();

    const matches = try regex.exec(allocator, line);
    for (matches.matches.items) |match| {
        const op_string = std.meta.stringToEnum(OpString, match.groups.items[0]) orelse continue;
        const op = switch (op_string) {
            .mul => mul: {
                const num1 = match.groups.items[1];
                const num2 = match.groups.items[2];
                const a = try std.fmt.parseInt(Num, num1, 10);
                const b = try std.fmt.parseInt(Num, num2, 10);
                break :mul Op{ .mul = Mul{ .a = a, .b = b } };
            },
            .do => Op{ .do = Do{} },
            .@"don't" => Op{ .dont = Dont{} },
        };
        try context.ops.append(op);
    }

    return .{};
}

fn calculate(allocator: std.mem.Allocator, ops: *std.ArrayList(Mul)) !void {
    _ = allocator;
    var sum: i64 = 0;
    for (ops.items) |op| {
        sum += op.a * op.b;
    }
    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, ops: *std.ArrayList(Op)) !void {
    _ = allocator;

    var sum: i64 = 0;
    var doing = true;
    for (ops.items) |op| {
        switch (op) {
            .mul => |mul| if (doing) {
                sum += mul.a * mul.b;
            },
            .do => |_| doing = true,
            .dont => |_| doing = false,
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
