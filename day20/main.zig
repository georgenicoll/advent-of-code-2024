const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Space: u8 = '.';
const Wall: u8 = '#';
const Start: u8 = 'S';
const End: u8 = 'E';

const Direction = enum {
    up,
    down,
    left,
    right,
};

const directions: [4]Direction = [4]Direction{
    Direction.up,
    Direction.down,
    Direction.left,
    Direction.right,
};

const Context = struct {
    const Self = @This();

    grid: shared.aoc.Grid(u8),
    start: ?Pos = null,
    end: ?Pos = null,

    fn print(self: Self, writer: anytype) !void {
        try self.grid.print(writer, "{c}");
        try writer.writeAll("\nStart: ");
        if (self.start) |start| {
            try start.print(writer);
        } else {
            try writer.writeAll("Not found");
        }
        try writer.writeAll(" End: ");
        if (self.end) |end| {
            try end.print(writer);
        } else {
            try writer.writeAll("Not found");
        }
        try writer.writeAll("\n\n");
    }
};

const Line = struct {};

pub fn main() !void {
    const day = "day20";
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

    var steps = try std.ArrayList(*Step).initCapacity(arena_allocator.allocator(), 1000);
    defer {
        for (steps.items) |step| {
            arena_allocator.allocator().destroy(step);
        }
        steps.deinit();
    }

    try findPath(arena_allocator.allocator(), &context, &steps);
    try calculate(arena_allocator.allocator(), &steps);
    try calculate_2(arena_allocator.allocator(), &steps);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;
    if (line.len == 0) {
        return .{};
    }

    //look for the start and end if we didn't already find them
    if (context.start == null or context.end == null) {
        for (line, 0..) |c, i| {
            if (c == Start) {
                context.start = Pos{ .i = @as(isize, @intCast(i)), .j = @as(isize, @intCast(context.grid.height)) };
                break;
            }
            if (c == End) {
                context.end = Pos{ .i = @as(isize, @intCast(i)), .j = @as(isize, @intCast(context.grid.height)) };
                break;
            }
        }
    }
    try context.grid.addRow(line);

    return .{};
}

const Pos = struct {
    const Self = @This();

    i: isize,
    j: isize,

    fn print(self: Self, writer: anytype) !void {
        try writer.print("({d},{d})", .{ self.i, self.j });
    }

    fn move(self: Self, direction: Direction) Self {
        return switch (direction) {
            Direction.up => Self{ .i = self.i, .j = self.j - 1 },
            Direction.down => Self{ .i = self.i, .j = self.j + 1 },
            Direction.left => Self{ .i = self.i + 1, .j = self.j },
            Direction.right => Self{ .i = self.i - 1, .j = self.j },
        };
    }

    fn distanceTo(self: Self, other: *Self) usize {
        const distance_i = @abs(other.i - self.i);
        const distance_j = @abs(other.j - self.j);
        return @as(usize, @intCast(distance_i + distance_j));
    }

    fn eql(self: Self, other: *const Self) bool {
        return self.i == other.i and self.j == other.j;
    }
};

const Step = struct {
    pos: Pos,
    step_number: usize,

    fn init(allocator: std.mem.Allocator, pos: Pos, step_number: usize) !*Step {
        const step: *Step = try allocator.create(Step);
        step.* = Step{
            .pos = pos,
            .step_number = step_number,
        };
        return step;
    }
};

//Steps will own the Steps
fn findPath(
    allocator: std.mem.Allocator,
    context: *const Context,
    steps: *std.ArrayList(*Step),
) !void {
    steps.clearRetainingCapacity();

    var visited = std.AutoHashMap(Pos, void).init(allocator);
    defer visited.deinit();

    //First step starts at the start
    var current_step = try Step.init(allocator, context.start.?, 0);
    try steps.append(current_step);

    //walk through from the start to the end... there is only one path - start at start and stop at end
    while (true) {
        //get the next step
        for (directions) |direction| {
            const candidate_pos = current_step.pos.move(direction);
            if (visited.contains(candidate_pos)) {
                continue; //been here
            }
            const maybe_space = context.grid.itemAt(candidate_pos.i, candidate_pos.j);
            if (maybe_space) |candidate| {
                const maybe_new_step: ?*Step = switch (candidate) {
                    Space, End => try Step.init(allocator, candidate_pos, current_step.step_number + 1),
                    else => null,
                };
                if (maybe_new_step) |new_step| {
                    try visited.put(new_step.pos, void{});
                    try steps.append(new_step);
                    current_step = new_step;
                }
                if (current_step.pos.eql(&context.end.?)) {
                    return; //got to end
                }
            }
        }
    }
}

const Cheat = struct {
    start_pos: Pos,
    end_pos: Pos,
    saves_steps: usize,
};

fn findCheats(
    steps: *const std.ArrayList(*Step),
    cheats: *std.ArrayList(Cheat),
    max_distance: usize,
) !void {
    //work through all of the steps trying to find cheats (jumps of up to max_distance away)
    for (0..steps.items.len) |start| {
        for (start + 1..steps.items.len) |end| {
            const start_step = steps.items[start];
            const end_step = steps.items[end];
            //is this close enough and does it save any time
            const distance = start_step.pos.distanceTo(&end_step.pos);
            if (distance > max_distance) {
                continue; //too far
            }
            if (end_step.step_number > start_step.step_number + distance) {
                const steps_saved = end_step.step_number - start_step.step_number - distance;
                const cheat = Cheat{
                    .start_pos = start_step.pos,
                    .end_pos = end_step.pos,
                    .saves_steps = steps_saved,
                };
                try cheats.append(cheat);
            }
        }
    }
}

fn calculate(allocator: std.mem.Allocator, steps: *const std.ArrayList(*Step)) !void {
    var cheats = try std.ArrayList(Cheat).initCapacity(allocator, steps.items.len);
    defer cheats.deinit();

    try findCheats(steps, &cheats, 2);

    var sum: usize = 0;
    for (cheats.items) |cheat| {
        if (cheat.saves_steps > 99) { //at least 100 for the main input
            sum += 1;
        }
    }
    try std.io.getStdOut().writer().print("Part 1 Cheats Saving enough time {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, steps: *const std.ArrayList(*Step)) !void {
    var cheats = try std.ArrayList(Cheat).initCapacity(allocator, steps.items.len);
    defer cheats.deinit();

    try findCheats(steps, &cheats, 20);

    var sum: usize = 0;
    for (cheats.items) |cheat| {
        if (cheat.saves_steps > 99) { //at least 100 for the main input
            sum += 1;
        }
    }
    try std.io.getStdOut().writer().print("Part 2 Cheats Saving enough time {d}\n", .{sum});
}
