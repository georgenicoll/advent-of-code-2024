const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    grid: shared.aoc.Grid(u8),
};

const Line = struct {};

pub fn main() !void {
    const day = "day10";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var grid = shared.aoc.Grid(u8).init(arena_allocator.allocator());
    defer grid.deinit();

    var context = Context{
        .grid = grid,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    const stdout = std.io.getStdOut();
    try context.grid.print(stdout.writer(), "{c}");

    try calculate(arena_allocator.allocator(), &context);
    try calculate_2(arena_allocator.allocator(), &context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;
    try context.grid.addRow(line);
    return .{};
}

const Pos = struct {
    const Self = @This();

    i: isize,
    j: isize,

    fn move(self: Self, direction: Self) Self {
        return Self{
            .i = self.i + direction.i,
            .j = self.j + direction.j,
        };
    }
};

const Up = Pos{ .i = 0, .j = -1 };
const Down = Pos{ .i = 0, .j = 1 };
const Left = Pos{ .i = -1, .j = 0 };
const Right = Pos{ .i = 1, .j = 0 };
const directions: []const Pos = &.{ Up, Down, Left, Right };

fn trailheadScore(
    allocator: std.mem.Allocator,
    visited: *std.AutoHashMap(Pos, void),
    context: *Context,
    start_i: isize,
    start_j: isize,
) !usize {
    //Only start from 0
    const start_height = context.grid.itemAt(start_i, start_j);
    if (start_height != '0') {
        return 0;
    }

    visited.clearRetainingCapacity();

    var stack = try std.ArrayList(Pos).initCapacity(allocator, 1000);
    defer stack.deinit();

    const start_pos = Pos{ .i = start_i, .j = start_j };
    try stack.append(start_pos);

    var score: usize = 0;
    while (stack.items.len > 0) {
        const next_pos = stack.pop();
        //did we already visit?
        if (visited.contains(next_pos)) {
            continue;
        }
        //visit
        try visited.put(next_pos, {});
        //done?
        const this_value = context.grid.itemAt(next_pos.i, next_pos.j);
        if (this_value == null) {
            continue; //shouldn't ever but...
        }
        if (this_value.? == '9') {
            score += 1;
            continue;
        }
        //work out where we can go next
        for (directions) |direction| {
            const next = next_pos.move(direction);
            const next_value = context.grid.itemAt(next.i, next.j);
            if (next_value) |value| {
                if (value >= this_value.? and (value - this_value.? == 1) and !visited.contains(next)) {
                    try stack.append(next);
                }
            }
        }
    }

    return score;
}

fn calculate(allocator: std.mem.Allocator, context: *Context) !void {
    var sum: usize = 0;

    var visited = std.AutoHashMap(Pos, void).init(allocator);
    defer visited.deinit();

    for (0..context.grid.height) |j_u| {
        const j = @as(isize, @intCast(j_u));
        for (0..context.grid.width) |i_u| {
            const i = @as(isize, @intCast(i_u));
            const score = try trailheadScore(allocator, &visited, context, i, j);
            sum += score;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

const Step = struct {
    step_id: usize,
    pos: Pos,
};

fn trailheadRating(
    allocator: std.mem.Allocator,
    completedTrails: *std.AutoHashMap(Step, void),
    context: *Context,
    start_i: isize,
    start_j: isize,
) !usize {
    //Only start from 0
    const start_height = context.grid.itemAt(start_i, start_j);
    if (start_height != '0') {
        return 0;
    }

    completedTrails.clearRetainingCapacity();

    var stack = try std.ArrayList(Step).initCapacity(allocator, 10000);
    defer stack.deinit();

    var next_step_id: usize = 0;
    const start_step = Step{
        .step_id = next_step_id,
        .pos = .{ .i = start_i, .j = start_j },
    };
    next_step_id += 1;
    try stack.append(start_step);

    while (stack.items.len > 0) {
        const next_step = stack.pop();
        //done?
        const this_value = context.grid.itemAt(next_step.pos.i, next_step.pos.j);
        if (this_value == null) {
            continue; //shouldn't ever but...
        }
        if (this_value.? == '9') {
            //Add this step to the completed trails
            try completedTrails.put(next_step, {});
            continue;
        }
        //work out where we can go next
        for (directions) |direction| {
            const next = next_step.pos.move(direction);
            const next_value = context.grid.itemAt(next.i, next.j);
            if (next_value) |value| {
                if (value >= this_value.? and (value - this_value.? == 1)) {
                    try stack.append(.{
                        .step_id = next_step_id,
                        .pos = next,
                    });
                    next_step_id += 1;
                }
            }
        }
    }

    return completedTrails.count();
}

fn calculate_2(allocator: std.mem.Allocator, context: *Context) !void {
    var sum: usize = 0;

    var completedTrails = std.AutoHashMap(Step, void).init(allocator);
    defer completedTrails.deinit();

    for (0..context.grid.height) |j_u| {
        const j = @as(isize, @intCast(j_u));
        for (0..context.grid.width) |i_u| {
            const i = @as(isize, @intCast(i_u));
            const rating = try trailheadRating(allocator, &completedTrails, context, i, j);
            sum += rating;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}
