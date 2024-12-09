const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Position = struct {
    const Self = @This();

    i: isize,
    j: isize,

    fn print(self: Self, writer: anytype) !void {
        try writer.print("({d},{d})", .{ self.i, self.j });
    }
};

const Positions = struct {
    const Self = @This();

    positions: *std.ArrayList(Position),

    fn init(allocator: std.mem.Allocator) !Self {
        const list: *std.ArrayList(Position) = try allocator.create(std.ArrayList(Position));
        list.* = try std.ArrayList(Position).initCapacity(allocator, 8);
        return .{
            .positions = list,
        };
    }

    fn deinit(self: *Self) void {
        self.positions.deinit();
    }

    fn print(self: Self, writer: anytype) !void {
        for (self.positions.items) |pos| {
            try pos.print(writer);
            try writer.writeAll(" ");
        }
    }
};

const Context = struct {
    const Self = @This();

    grid: shared.aoc.Grid(u8),
    locations_by_frequency: std.AutoHashMap(u8, Positions),

    fn print(self: Self, writer: anytype) !void {
        try self.grid.print(writer, "{c}");
        try writer.writeAll("\n");
        var it = self.locations_by_frequency.iterator();
        while (it.next()) |entry| {
            try writer.print("{c}: ", .{entry.key_ptr.*});
            try entry.value_ptr.*.print(writer);
            try writer.writeAll("\n");
        }
        try writer.writeAll("\n");
    }
};

const Space = '.';
const Space2 = '#';

const Line = struct {};

pub fn main() !void {
    const day = "day8";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var grid = shared.aoc.Grid(u8).init(arena_allocator.allocator());
    defer grid.deinit();

    var locations_by_frequency = std.AutoHashMap(u8, Positions).init(arena_allocator.allocator());
    defer {
        var it = locations_by_frequency.valueIterator();
        while (it.next()) |positions| {
            positions.deinit();
        }
        locations_by_frequency.deinit();
    }

    var context = Context{
        .grid = grid,
        .locations_by_frequency = locations_by_frequency,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    const stdout = std.io.getStdOut();
    try context.print(stdout.writer());

    try calculate(arena_allocator.allocator(), context);
    try calculate_2(arena_allocator.allocator(), context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    try context.grid.addRow(line);
    //search the line to find any antennae
    const j = @as(isize, @intCast(context.grid.height - 1));
    for (line, 0..) |char, i| {
        if (char != Space and char != Space2) {
            const position = Position{
                .i = @as(isize, @intCast(i)),
                .j = j,
            };
            const entry = try context.locations_by_frequency.getOrPut(char);
            if (!entry.found_existing) {
                entry.value_ptr.* = try Positions.init(allocator);
            }
            try entry.value_ptr.positions.append(position);
        }
    }
    return .{};
}

fn calculate(allocator: std.mem.Allocator, context: Context) !void {
    //Set of positions of antinodes
    var antinode_positions = std.AutoHashMap(Position, void).init(allocator);
    defer antinode_positions.deinit();

    //look for all combinations of antinode positions
    var node_iterator = context.locations_by_frequency.iterator();
    while (node_iterator.next()) |node| {
        const positions = node.value_ptr.*;
        for (0..positions.positions.items.len - 1) |a| {
            const position_a = positions.positions.items[a];
            for (a + 1..positions.positions.items.len) |b| {
                const position_b = positions.positions.items[b];
                //calculate anti node positions and add to map if not out_of_bound
                const diff = Position{
                    .i = position_b.i - position_a.i,
                    .j = position_b.j - position_a.j,
                };
                //antinode b to a
                const antinode_b_a = Position{
                    .i = position_a.i - diff.i,
                    .j = position_a.j - diff.j,
                };
                if (context.grid.inBounds(antinode_b_a.i, antinode_b_a.j)) {
                    try antinode_positions.put(antinode_b_a, {});
                }
                //antinode a to b
                const antinode_a_b = Position{
                    .i = position_b.i + diff.i,
                    .j = position_b.j + diff.j,
                };
                if (context.grid.inBounds(antinode_a_b.i, antinode_a_b.j)) {
                    try antinode_positions.put(antinode_a_b, {});
                }
            }
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{antinode_positions.count()});
}

fn calculate_2(allocator: std.mem.Allocator, context: Context) !void {
    //Set of positions of antinodes
    var antinode_positions = std.AutoHashMap(Position, void).init(allocator);
    defer antinode_positions.deinit();

    //look for all combinations of antinode positions
    var node_iterator = context.locations_by_frequency.iterator();
    while (node_iterator.next()) |node| {
        const positions = node.value_ptr.*;
        for (0..positions.positions.items.len - 1) |a| {
            const position_a = positions.positions.items[a];
            for (a + 1..positions.positions.items.len) |b| {
                const position_b = positions.positions.items[b];
                //calculate anti node positions and add to map if not out_of_bound
                const diff = Position{
                    .i = position_b.i - position_a.i,
                    .j = position_b.j - position_a.j,
                };
                //Now project out as far as we can go in both directions..
                //antinode b to a
                var current_pos = position_a;
                while (context.grid.inBounds(current_pos.i, current_pos.j)) {
                    //add the antinode
                    try antinode_positions.put(current_pos, {});
                    //move to the next position
                    current_pos = Position{
                        .i = current_pos.i - diff.i,
                        .j = current_pos.j - diff.j,
                    };
                }
                //antinode a to b
                current_pos = position_b;
                while (context.grid.inBounds(current_pos.i, current_pos.j)) {
                    //add the antinode
                    try antinode_positions.put(current_pos, {});
                    //move to the next position
                    current_pos = Position{
                        .i = current_pos.i + diff.i,
                        .j = current_pos.j + diff.j,
                    };
                }
            }
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{antinode_positions.count()});
}
