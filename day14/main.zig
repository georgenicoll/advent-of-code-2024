const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Num = isize;

const Comb = struct {
    const Self = @This();

    x: Num,
    y: Num,

    fn print(self: Self, writer: anytype) !void {
        try writer.print("{d},{d}", .{ self.x, self.y });
    }
};
const Position = Comb;
const Velocity = Comb;
const Dimensions = Comb;

const Robot = struct {
    const Self = @This();

    position: Position,
    velocity: Velocity,

    fn print(self: Self, writer: anytype) !void {
        try writer.writeAll("p=");
        try self.position.print(writer);
        try writer.writeAll(" v=");
        try self.velocity.print(writer);
    }
};

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
    robots: std.ArrayList(Robot),
    dimensions: Dimensions,
};

const Line = struct {};

fn outputContext(context: *Context) !void {
    const writer = std.io.getStdOut().writer();
    for (context.robots.items) |robot| {
        try robot.print(writer);
        try writer.writeAll("\n");
    }
    try writer.print("width={d} height={d}", .{ context.dimensions.x, context.dimensions.y });
    try writer.writeAll("\n\n");
}

pub fn main() !void {
    const day = "day14";
    //const file_name = day ++ "/test_file.txt";
    //const dimensions = Dimensions{ .x = 11, .y = 7 };
    //const file_name = day ++ "/test_cases.txt";
    //const dimensions = Dimensions{ .x = ?, .y = ? };
    const file_name = day ++ "/input.txt";
    const dimensions = Dimensions{ .x = 101, .y = 103 };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put('p', true);
    try delimiters.put('=', true);
    try delimiters.put(',', true);
    try delimiters.put(' ', true);
    try delimiters.put('v', true);
    try delimiters.put('=', true);

    var robots1 = try std.ArrayList(Robot).initCapacity(arena_allocator.allocator(), 500);
    defer robots1.deinit();

    var context1 = Context{
        .delimiters = delimiters,
        .robots = robots1,
        .dimensions = dimensions,
    };

    const parsed_lines1 = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context1,
        file_name,
    );
    defer parsed_lines1.deinit();

    try calculate(arena_allocator.allocator(), &context1);

    var robots2 = try std.ArrayList(Robot).initCapacity(arena_allocator.allocator(), 500);
    defer robots2.deinit();

    var context2 = Context{
        .delimiters = delimiters,
        .robots = robots2,
        .dimensions = dimensions,
    };

    const parsed_lines2 = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context2,
        file_name,
    );
    defer parsed_lines2.deinit();

    try calculate_2(arena_allocator.allocator(), &context2);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    var parser = shared.process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    try parser.consume_delimiters();
    const pos_x = try parser.read_int(Num, 10);
    const pos_y = try parser.read_int(Num, 10);
    const vel_x = try parser.read_int(Num, 10);
    const vel_y = try parser.read_int(Num, 10);

    const robot = Robot{
        .position = Position{ .x = pos_x, .y = pos_y },
        .velocity = Velocity{ .x = vel_x, .y = vel_y },
    };
    try context.robots.append(robot);

    return .{};
}

fn updatePosition(dimensions: *const Dimensions, robot: *Robot, seconds: isize) void {
    //Move the robot as if it wasn't constrained
    robot.position.x = robot.position.x + robot.velocity.x * seconds;
    robot.position.y = robot.position.y + robot.velocity.y * seconds;

    robot.position.x = @mod(robot.position.x, dimensions.x);
    robot.position.y = @mod(robot.position.y, dimensions.y);
}

/// returns 0 if north, 1 if south or null if middle
fn northOrSouth(dimensions: *const Dimensions, robot: *const Robot) ?u8 {
    const middle_horizontal = @divFloor(dimensions.y, 2);
    if (robot.position.y < middle_horizontal) {
        return 0;
    }
    if (robot.position.y > middle_horizontal) {
        return 1;
    }
    return null;
}

const NW: u8 = 0;
const NE: u8 = 1;
const SW: u8 = 2;
const SE: u8 = 3;

fn assignQuadrant(dimensions: *const Dimensions, robot: *const Robot) ?u8 {
    const north_or_south = northOrSouth(dimensions, robot);
    if (north_or_south == null) {
        return null;
    }

    const middle_vertical = @divFloor(dimensions.x, 2);

    if (robot.position.x > middle_vertical) {
        //east
        if (north_or_south == 0) {
            return NE;
        } else {
            return SE;
        }
    }
    if (robot.position.x < middle_vertical) {
        //west
        if (north_or_south == 0) {
            return NW;
        } else {
            return SW;
        }
    }
    return null; //middle
}

fn calculate(allocator: std.mem.Allocator, context: *Context) !void {
    _ = allocator;
    // try outputContext(context);

    var quads: [4]usize = [4]usize{ 0, 0, 0, 0 };

    //Move the robots and assign to a quadrant
    for (context.robots.items) |*robot| {
        updatePosition(&context.dimensions, robot, 100);
        const quadrant = assignQuadrant(&context.dimensions, robot);
        if (quadrant) |quad| {
            quads[quad] += 1;
        }
    }

    // try outputContext(context);

    var total: usize = 1;
    for (quads) |quadrant| {
        total *= quadrant;
    }

    try std.io.getStdOut().writer().print("Part 1 Total {d}\n", .{total});
}

fn populateGrid(grid: *shared.aoc.Grid(u8), robots: *std.ArrayList(Robot), c: u8) !void {
    for (robots.items) |robot| {
        try grid.setItemAt(robot.position.x, robot.position.y, c);
    }
}

fn isInteresting(robot: *Robot) bool {
    //return robot.position.y == 0 and robot.position.x == 50;
    _ = robot;
    return true;
}

fn calculate_2(allocator: std.mem.Allocator, context: *Context) !void {
    var grid = shared.aoc.Grid(u8).init(allocator);
    defer grid.deinit();

    const x_u = @as(usize, @intCast(context.dimensions.x));
    const y_u = @as(usize, @intCast(context.dimensions.y));
    var row = try std.ArrayList(u8).initCapacity(allocator, x_u);
    defer row.deinit();

    for (0..y_u) |_| {
        row.clearRetainingCapacity();
        for (0..x_u) |_| {
            try row.append('.');
        }
        try grid.addRow(row.items);
    }

    try populateGrid(&grid, &context.robots, '*');
    try grid.print(std.io.getStdOut().writer(), "{c}");
    try populateGrid(&grid, &context.robots, '.');

    var second: usize = 0;
    while (second < 10000) {
        for (context.robots.items) |*robot| {
            updatePosition(&context.dimensions, robot, 1);
        }
        second += 1;

        //Magic numbers found by looking at the full output of a 1000 iterations....
        if (second > 42 and (second - 42) % 103 == 0) {
            try std.io.getStdOut().writer().print("== Second {d} ==\n", .{second});
            try populateGrid(&grid, &context.robots, '*');
            try grid.print(std.io.getStdOut().writer(), "{c}");
            try populateGrid(&grid, &context.robots, '.');
            try std.io.getStdOut().writeAll("\n");
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{second});
}

const expect = std.testing.expect;

test "move" {
    const dimensions = Dimensions{ .x = 2, .y = 2 };

    var robot1 = Robot{
        .position = Position{ .x = 0, .y = 1 },
        .velocity = Velocity{ .x = 0, .y = 1 },
    };
    updatePosition(&dimensions, &robot1, 1);
    try expect(robot1.position.x == 0);
    try expect(robot1.position.y == 0);

    var robot2 = Robot{
        .position = Position{ .x = 0, .y = 0 },
        .velocity = Velocity{ .x = 0, .y = -1 },
    };
    updatePosition(&dimensions, &robot2, 1);
    try expect(robot2.position.x == 0);
    try expect(robot2.position.y == 1);

    var robot3 = Robot{
        .position = Position{ .x = 1, .y = 0 },
        .velocity = Velocity{ .x = 1, .y = 0 },
    };
    updatePosition(&dimensions, &robot3, 1);
    try expect(robot3.position.x == 0);
    try expect(robot3.position.y == 0);

    var robot4 = Robot{
        .position = Position{ .x = 0, .y = 0 },
        .velocity = Velocity{ .x = -1, .y = 0 },
    };
    updatePosition(&dimensions, &robot4, 1);
    try expect(robot4.position.x == 1);
    try expect(robot4.position.y == 0);

    const dimensions2 = Dimensions{ .x = 11, .y = 7 };
    var robot5 = Robot{
        .position = Position{ .x = 2, .y = 4 },
        .velocity = Velocity{ .x = 2, .y = -3 },
    };
    updatePosition(&dimensions2, &robot5, 3);
    try expect(robot5.position.x == 8);
    try expect(robot5.position.y == 2);
}

test "assign quadrant" {
    const dimensions = Dimensions{ .x = 5, .y = 7 };
    const velocity = Velocity{ .x = 0, .y = 0 };

    const ne_robot = Robot{
        .position = Position{ .x = 4, .y = 1 },
        .velocity = velocity,
    };
    try expect(assignQuadrant(&dimensions, &ne_robot) == NE);

    const nw_robot = Robot{
        .position = Position{ .x = 1, .y = 2 },
        .velocity = velocity,
    };
    try expect(assignQuadrant(&dimensions, &nw_robot) == NW);

    const se_robot = Robot{
        .position = Position{ .x = 3, .y = 5 },
        .velocity = velocity,
    };
    try expect(assignQuadrant(&dimensions, &se_robot) == SE);

    const sw_robot = Robot{
        .position = Position{ .x = 0, .y = 4 },
        .velocity = velocity,
    };
    try expect(assignQuadrant(&dimensions, &sw_robot) == SW);

    const middle_robot1 = Robot{
        .position = Position{ .x = 2, .y = 1 },
        .velocity = velocity,
    };
    try expect(assignQuadrant(&dimensions, &middle_robot1) == null);

    const middle_robot2 = Robot{
        .position = Position{ .x = 3, .y = 3 },
        .velocity = velocity,
    };
    try expect(assignQuadrant(&dimensions, &middle_robot2) == null);
}
