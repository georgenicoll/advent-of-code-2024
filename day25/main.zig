const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    grid: *shared.aoc.Grid(u8),
    locks: *std.ArrayList([]const u8),
    keys: *std.ArrayList([]const u8),

    fn print(self: Self, writer: anytype) !void {
        try writer.writeAll("=== Locks:\n");
        for (self.locks.items) |lock| {
            for (lock) |height| {
                try writer.print("{d},", .{height});
            }
            try writer.writeAll("\n");
        }
        try writer.writeAll("=== Keys:\n");
        for (self.keys.items) |key| {
            for (key) |height| {
                try writer.print("{d},", .{height});
            }
            try writer.writeAll("\n");
        }
        try writer.writeAll("\n");
    }

    fn constructNextKeyOrLock(self: *Self) !void {
        //key or lock?
        const maybe_top_left = self.grid.itemAt(0, 0);
        if (maybe_top_left) |top_left| {
            switch (top_left) {
                Space => try self.addKey(),
                Block => try self.addLock(),
                else => @panic("Unrecognised type"),
            }
        }
        self.grid.clear();
    }

    fn addKey(self: *Self) !void {
        //keys go from bottom to top ignore bottom row - we are expecting widths of 5
        var heights: []u8 = try self.allocator.alloc(u8, self.grid.width);
        zeroArray(heights);
        for (0..self.grid.height - 1) |j| {
            for (0..self.grid.width) |i| {
                const item = self.grid.itemAtU(i, j);
                if (item == Block) {
                    heights[i] += 1;
                }
            }
        }
        try self.keys.append(heights);
    }

    fn addLock(self: *Self) !void {
        //locks go from top to bottom ignore top row - we are expecting widths of 5
        var heights: []u8 = try self.allocator.alloc(u8, self.grid.width);
        zeroArray(heights);
        for (1..self.grid.height) |j| {
            for (0..self.grid.width) |i| {
                const item = self.grid.itemAtU(i, j);
                if (item == Block) {
                    heights[i] += 1;
                }
            }
        }
        try self.locks.append(heights);
    }
};

const Line = struct {};

pub fn main() !void {
    const day = "day25";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var grid = shared.aoc.Grid(u8).init(arena_allocator.allocator());
    defer grid.deinit();

    var locks = try std.ArrayList([]const u8).initCapacity(arena_allocator.allocator(), 1000);
    defer locks.deinit();

    var keys = try std.ArrayList([]const u8).initCapacity(arena_allocator.allocator(), 1000);
    defer keys.deinit();

    var context = Context{
        .allocator = arena_allocator.allocator(),
        .grid = &grid,
        .keys = &keys,
        .locks = &locks,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    //create any last key or lock
    try context.constructNextKeyOrLock();

    // const stdout = std.io.getStdOut();
    // for (context.grid.items) |row| {
    //     try stdout.writeAll(row.items);
    //     try stdout.writeAll("\n");
    // }
    // try stdout.writer().print("width: {d}, height: {d}\n", .{ context.width, context.height });

    try calculate(arena_allocator.allocator(), &context);
    try calculate_2(arena_allocator.allocator(), &context);
}

const Space: u8 = '.';
const Block: u8 = '#';

fn zeroArray(arr: []u8) void {
    for (0..arr.len) |i| {
        arr[i] = 0;
    }
}

fn parse_line(_: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    if (line.len == 0) {
        try context.constructNextKeyOrLock();
        return .{};
    }

    try context.grid.addRow(line);

    return .{};
}

fn hasOverlaps(lock: []const u8, key: []const u8) bool {
    //if any add up to more than 5, then they overlap
    for (0..lock.len) |i| {
        if (lock[i] + key[i] > 5) {
            return true;
        }
    }
    return false;
}

fn calculate(allocator: std.mem.Allocator, context: *const Context) !void {
    _ = allocator;

    //try context.print(std.io.getStdOut().writer());

    var sum: usize = 0;
    //try each key with each lock - how many will fit?
    for (context.locks.items) |lock| {
        for (context.keys.items) |key| {
            if (!hasOverlaps(lock, key)) {
                sum += 1;
            }
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, context: *const Context) !void {
    _ = allocator;
    _ = context;

    var sum: usize = 0;
    sum += 0;

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
