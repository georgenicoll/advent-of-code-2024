const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
    grid: shared.aoc.Grid(u8),
    guard_position: ?Position = null,
};

const Line = struct {};

const Direction = enum {
    NORTH,
    EAST,
    SOUTH,
    WEST,

    fn turnRight(self: Direction) Direction {
        return switch (self) {
            Direction.NORTH => |_| Direction.EAST,
            Direction.EAST => |_| Direction.SOUTH,
            Direction.SOUTH => |_| Direction.WEST,
            Direction.WEST => |_| Direction.NORTH,
        };
    }

    fn nextPosition(self: Direction, currentPosition: Position) Position {
        const delta = switch (self) {
            Direction.NORTH => |_| Position{ .x = 0, .y = -1 },
            Direction.EAST => |_| Position{ .x = 1, .y = 0 },
            Direction.SOUTH => |_| Position{ .x = 0, .y = 1 },
            Direction.WEST => |_| Position{ .x = -1, .y = 0 },
        };
        return Position{
            .x = currentPosition.x + delta.x,
            .y = currentPosition.y + delta.y,
        };
    }
};

const Position = struct {
    x: isize,
    y: isize,

    fn print(self: Position, writer: anytype) !void {
        try writer.print("({d},{d})", .{ self.x, self.y });
    }
};

const SPACE = '.';
const OBSTACLE = '#';

/// On my old surface pro
/// zig build:  1m 4s
/// zig build --release=fast: 4s !!
pub fn main() !void {
    const day = "day6";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);

    var grid = shared.aoc.Grid(u8).init(arena_allocator.allocator());
    defer grid.deinit();

    var context = Context{
        .delimiters = delimiters,
        .grid = grid,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    // const stdout = std.io.getStdOut();
    // try context.grid.print(stdout.writer(), "{c}");
    // try stdout.writer().writeAll("guard pos: ");
    // try context.guard_position.?.print(stdout.writer());
    // try stdout.writer().writeAll("\n");

    try calculate(arena_allocator.allocator(), context);
    try calculate_2(arena_allocator.allocator(), &context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;
    try context.grid.addRow(line);
    if (context.guard_position == null) {
        //scan the added line to see if we can find the position
        for (0..context.grid.width) |x| {
            if (context.grid.itemAtU(x, context.grid.height - 1) == '^') {
                context.guard_position = Position{
                    .x = @as(isize, @intCast(x)),
                    .y = @as(isize, @intCast(context.grid.height - 1)),
                };
                try context.grid.setItemAtU(x, context.grid.height - 1, SPACE);
            }
        }
    }
    return .{};
}

fn calculate(allocator: std.mem.Allocator, context: Context) !void {
    var visited_positions = std.AutoHashMap(Position, void).init(allocator);
    defer visited_positions.deinit();

    var currentPosition = context.guard_position.?;
    var currentDirection = Direction.NORTH;

    //Walk until we go out of bounds
    while (context.grid.itemAt(currentPosition.x, currentPosition.y) != null) {
        try visited_positions.put(currentPosition, {});
        const nextPosition = currentDirection.nextPosition(currentPosition);
        const thingAtNextPosition = context.grid.itemAt(nextPosition.x, nextPosition.y);
        if (thingAtNextPosition == OBSTACLE) {
            //Just turn right and go round again
            currentDirection = currentDirection.turnRight();
            continue;
        }
        //Move to the next position
        currentPosition = nextPosition;
    }

    try std.io.getStdOut().writer().print("Part 1 Visited {d}\n", .{visited_positions.count()});
}

const PositionAndDirection = struct {
    position: Position,
    direction: Direction,
};

/// Perform a walk - return true if this is a loop, or false if this would go out of bounds
fn walk(
    context: *Context,
    visited_position_directions: *std.AutoHashMap(PositionAndDirection, void),
) !bool {
    visited_position_directions.clearRetainingCapacity();
    var currentPosition = context.guard_position.?;
    var currentDirection = Direction.NORTH;

    //Walk until we go out of bounds
    while (context.grid.itemAt(currentPosition.x, currentPosition.y) != null) {
        const position_and_direction = PositionAndDirection{
            .position = currentPosition,
            .direction = currentDirection,
        };
        //Did we get here alread going in the same direction?  if so we have a loop
        if (visited_position_directions.contains(position_and_direction)) {
            return true;
        }
        //Do the walk...
        try visited_position_directions.put(position_and_direction, {});
        const nextPosition = currentDirection.nextPosition(currentPosition);
        const thingAtNextPosition = context.grid.itemAt(nextPosition.x, nextPosition.y);
        if (thingAtNextPosition == OBSTACLE) {
            //Just turn right and go round again
            currentDirection = currentDirection.turnRight();
            continue;
        }
        //Move to the next position
        currentPosition = nextPosition;
    }

    return false; //no loop we went out of bounds
}

fn calculate_2(allocator: std.mem.Allocator, context: *Context) !void {
    var visited_position_directions = std.AutoHashMap(PositionAndDirection, void).init(allocator);
    defer visited_position_directions.deinit();

    var sum: usize = 0;
    for (0..context.grid.height) |y_u| {
        const y = @as(isize, @intCast(y_u));
        // try std.io.getStdOut().writer().print("Processing row {d}\n", .{y});
        for (0..context.grid.width) |x_u| {
            const x = @as(isize, @intCast(x_u));
            //Just carry on if there is an obstacle here
            if (context.grid.itemAt(x, y) == OBSTACLE) {
                continue;
            }
            //Place an obstacle
            try context.grid.setItemAt(x, y, OBSTACLE);
            //see if we get a loop
            if (try walk(context, &visited_position_directions)) {
                sum += 1;
            }
            //remove the obstacle
            try context.grid.setItemAt(x, y, SPACE);
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
