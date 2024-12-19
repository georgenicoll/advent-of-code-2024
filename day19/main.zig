const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    const Self = @This();

    delimiters: std.AutoHashMap(u8, bool),
    towels: *std.StringHashMap(void),
    max_towel_len: usize = 0,
    designs: *std.ArrayList([]const u8),

    fn print(self: Self, writer: anytype) !void {
        var it = self.towels.keyIterator();
        while (it.next()) |towel| {
            try writer.writeAll(towel.*);
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
        try writer.print("Max towel length: {d}\n", .{self.max_towel_len});
        try writer.writeAll("\n");
        for (self.designs.items) |design| {
            try writer.writeAll(design);
            try writer.writeAll("\n");
        }
        try writer.writeAll("\n");
    }
};

const Line = struct {};

pub fn main() !void {
    const day = "day19";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);
    try delimiters.put(',', true);

    var towels = std.StringHashMap(void).init(arena_allocator.allocator());
    defer towels.deinit();

    var designs = std.ArrayList([]const u8).init(arena_allocator.allocator());
    defer {
        for (designs.items) |design| {
            arena_allocator.allocator().free(design);
        }
        designs.deinit();
    }

    var context = Context{
        .delimiters = delimiters,
        .towels = &towels,
        .designs = &designs,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    try calculate(arena_allocator.allocator(), context);
    try calculate_2(arena_allocator.allocator(), context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    if (line.len == 0) {
        return .{};
    }

    var parser = shared.process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    if (context.towels.count() == 0) {
        var towel = parser.read_string() catch null;
        while (towel != null and towel.?.len > 0) {
            try context.towels.put(towel.?, {});
            context.max_towel_len = @max(context.max_towel_len, towel.?.len);
            towel = parser.read_string() catch null;
        }
        return .{};
    }

    const design = try parser.read_string();
    try context.designs.append(design);

    return .{};
}

fn countPossible(
    towels: *std.StringHashMap(void),
    max_towel_length: usize,
    design: []const u8,
    partials: *std.StringHashMap(usize),
) !usize {
    if (partials.get(design)) |calculated_possibilities| {
        return calculated_possibilities;
    }

    var possible: usize = 0;

    if (design.len <= max_towel_length and towels.contains(design)) {
        possible += 1;
    }

    //split if we can
    for (1..(@min(max_towel_length + 1, design.len))) |length| {
        const start = design[0..length];

        //stop looking if the start isn't a valid towel
        if (!towels.contains(start)) {
            continue;
        }

        //valid start add the possibilities following this
        const end = design[length..];
        const possible_end = try countPossible(towels, max_towel_length, end, partials);
        possible += possible_end;
    }

    try partials.put(design, possible);

    return possible;
}

fn calculate(allocator: std.mem.Allocator, context: Context) !void {
    var partials = std.StringHashMap(usize).init(allocator);
    defer partials.deinit();

    var sum: usize = 0;
    for (context.designs.items) |design| {
        const possible = try countPossible(
            context.towels,
            context.max_towel_len,
            design,
            &partials,
        );
        if (possible > 0) {
            sum += 1;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, context: Context) !void {
    var partials = std.StringHashMap(usize).init(allocator);
    defer partials.deinit();

    var sum: usize = 0;
    for (context.designs.items) |design| {
        const possible = try countPossible(
            context.towels,
            context.max_towel_len,
            design,
            &partials,
        );
        sum += possible;
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
