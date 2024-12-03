const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context1 = struct {
    delimiters: std.AutoHashMap(u8, bool),
    ops: *std.ArrayList(Mul),
};

const Context2 = struct {
    delimiters: std.AutoHashMap(u8, bool),
    ops: *std.ArrayList(Op),
};

const Mul = struct {
    a: i64,
    b: i64,

    pub fn print(self: Mul, writer: anytype) !void {
        try writer.print("mul({d},{d})", self);
    }
};

const Do = struct {
    ignored: i64 = 0,

    pub fn print(self: Do, writer: anytype) !void {
        _ = self;
        try writer.print("do", .{});
    }
};

const Dont = struct {
    ignored: i64 = 0,

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

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put('(', true);
    try delimiters.put(')', true);

    var ops1 = std.ArrayList(Mul).init(arena_allocator.allocator());
    defer ops1.deinit();

    const context1 = Context1{
        .delimiters = delimiters,
        .ops = &ops1,
    };

    const parsed_lines1 = try process.FileParser(Context1, Line, parse_line1).parse(
        arena_allocator.allocator(),
        context1,
        file_name,
    );
    defer parsed_lines1.deinit();

    // const stdout = std.io.getStdOut();
    // for (context1.ops.items) |op| {
    //     try op.print(stdout.writer());
    //     try stdout.writeAll("\n");
    // }

    try calculate(arena_allocator.allocator(), context1.ops);

    var ops2 = std.ArrayList(Op).init(arena_allocator.allocator());
    defer ops2.deinit();

    const context2 = Context2{
        .delimiters = delimiters,
        .ops = &ops2,
    };

    const parsed_lines2 = try process.FileParser(Context2, Line, parse_line2).parse(
        arena_allocator.allocator(),
        context2,
        file_name2,
    );
    defer parsed_lines2.deinit();

    const stdout = std.io.getStdOut();
    for (context2.ops.items) |op| {
        try op.print(stdout.writer());
        try stdout.writeAll("\n");
    }

    try calculate_2(arena_allocator.allocator(), context2.ops);
}

fn parse_line1(allocator: std.mem.Allocator, context: Context1, line: []const u8) !Line {
    var parser = process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    //read all of the ops
    while (parser.has_more()) {
        //read to the next '('
        const next_string = try parser.read_string();
        defer parser.allocator.free(next_string);

        //is there a 'mul' immediately before it?
        if (next_string.len < 3) {
            continue;
        }
        const possible_mul = next_string[next_string.len - 3 ..];
        if (eql(u8, "mul", possible_mul)) {
            // Expect mul(a,b)
            if (parser.first_delimiter() != '(') {
                continue;
            }

            // try to read an int
            const a_chars = try parser.read_next_int_chars();
            defer a_chars.deinit();
            const a = std.fmt.parseInt(i64, a_chars.items, 10) catch null;
            if (a == null) {
                continue;
            }
            // needs a , as the delimiter
            if (parser.peek_char() != ',') {
                continue;
            }
            //consume the ,
            _ = parser.read_char();

            // try to read an int
            const b_chars = try parser.read_next_int_chars();
            defer b_chars.deinit();
            const b = std.fmt.parseInt(i64, b_chars.items, 10) catch null;
            if (b == null) {
                continue;
            }
            // needs a ) as the delimiter
            if (parser.peek_char() != ')') {
                continue;
            }
            //consume the )
            _ = parser.read_char();

            const mul = Mul{ .a = a.?, .b = b.? };
            try context.ops.append(mul);
        }
    }

    return .{};
}

fn parse_line2(allocator: std.mem.Allocator, context: Context2, line: []const u8) !Line {
    var parser = process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    //read all of the ops
    while (parser.has_more()) {
        //read to the next '('
        const next_string = try parser.read_string();
        defer parser.allocator.free(next_string);

        //Is this a do?
        if (next_string.len >= 2) {
            const possible_do = next_string[next_string.len - 2 ..];
            if (eql(u8, "do", possible_do)) {
                //expect do()
                const found_delims = parser.found_delimiters.items;
                if (found_delims.len >= 2 and found_delims[0] == '(' and found_delims[1] == ')') {
                    try context.ops.append(Op{ .do = Do{} });
                    continue;
                }
            }
        }

        //Is this a don't?
        if (next_string.len >= 5) {
            const possible_dont = next_string[next_string.len - 5 ..];
            if (eql(u8, "don't", possible_dont)) {
                const found_delims = parser.found_delimiters.items;
                if (found_delims.len >= 2 and found_delims[0] == '(' and found_delims[1] == ')') {
                    try context.ops.append(Op{ .dont = Dont{} });
                    continue;
                }
            }
        }

        //TODO Refactor
        //is this a mul
        if (next_string.len < 3) {
            continue;
        }
        const possible_mul = next_string[next_string.len - 3 ..];
        if (eql(u8, "mul", possible_mul)) {
            // Expect mul(a,b)
            if (parser.first_delimiter() != '(') {
                continue;
            }

            // try to read an int
            const a_chars = try parser.read_next_int_chars();
            defer a_chars.deinit();
            const a = std.fmt.parseInt(i64, a_chars.items, 10) catch null;
            if (a == null) {
                continue;
            }
            // needs a , as the delimiter
            if (parser.peek_char() != ',') {
                continue;
            }
            //consume the ,
            _ = parser.read_char();

            // try to read an int
            const b_chars = try parser.read_next_int_chars();
            defer b_chars.deinit();
            const b = std.fmt.parseInt(i64, b_chars.items, 10) catch null;
            if (b == null) {
                continue;
            }
            // needs a ) as the delimiter
            if (parser.peek_char() != ')') {
                continue;
            }
            //consume the )
            _ = parser.read_char();

            const mul = Op{ .mul = Mul{ .a = a.?, .b = b.? } };
            try context.ops.append(mul);
        }
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

    var dos: usize = 0;
    var donts: usize = 0;
    for (ops.items) |op| {
        switch (op) {
            .mul => |_| {},
            .do => |_| dos += 1,
            .dont => |_| donts += 1,
        }
    }
    try std.io.getStdOut().writer().print("Do: {d}, Dont: {d}\n", .{ dos, donts });

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
