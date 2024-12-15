const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Square = u8;
const Move = u8;

const Wall: Square = '#';
const Box: Square = 'O';
const Space: Square = '.';
const Robot: Square = '@';
const BoxLeft: Square = '[';
const BoxRight: Square = ']';

const Up: Move = '^';
const Down: Move = 'v';
const Left: Move = '<';
const Right: Move = '>';

const Pos = struct {
    const Self = @This();

    i: isize,
    j: isize,

    fn move(self: Self, direction: Move) Self {
        return switch (direction) {
            Up => |_| Pos{ .i = self.i, .j = self.j - 1 },
            Down => |_| Pos{ .i = self.i, .j = self.j + 1 },
            Left => |_| Pos{ .i = self.i - 1, .j = self.j },
            Right => |_| Pos{ .i = self.i + 1, .j = self.j },
            else => @panic("Unrecognised direction!!!"),
        };
    }
};

const Context = struct {
    const Self = @This();

    grid: *shared.aoc.Grid(Square),
    moves: *std.ArrayList(Move),
    robot_pos: ?Pos = null,
    done_grid: bool = false,
    expanded_line: *std.ArrayList(Square),

    fn print(self: Self, writer: anytype) !void {
        try self.grid.print(writer, "{c}");
        try writer.writeAll("\n");
        try writer.writeAll(self.moves.items);
        try writer.writeAll("\n");
        if (self.robot_pos) |pos| {
            try writer.print("Robot Pos: {d},{d}\n\n", .{ pos.i, pos.j });
        }
    }
};

const Line = struct {};

pub fn main() !void {
    const day = "day15";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var expanded_line = try std.ArrayList(u8).initCapacity(arena_allocator.allocator(), 110);
    defer expanded_line.deinit();

    var grid1 = shared.aoc.Grid(Square).init(arena_allocator.allocator());
    defer grid1.deinit();

    var moves1 = std.ArrayList(Move).init(arena_allocator.allocator());
    defer moves1.deinit();

    var context1 = Context{
        .grid = &grid1,
        .moves = &moves1,
        .expanded_line = &expanded_line,
    };

    const parsed_lines1 = try process.FileParser(*Context, Line, parse_line1).parse(
        arena_allocator.allocator(),
        &context1,
        file_name,
    );
    defer parsed_lines1.deinit();

    try calculate(arena_allocator.allocator(), &context1);

    var grid2 = shared.aoc.Grid(Square).init(arena_allocator.allocator());
    defer grid2.deinit();

    var moves2 = std.ArrayList(Move).init(arena_allocator.allocator());
    defer moves2.deinit();

    var context2 = Context{
        .grid = &grid2,
        .moves = &moves2,
        .expanded_line = &expanded_line,
    };

    const parsed_lines2 = try process.FileParser(*Context, Line, parse_line2).parse(
        arena_allocator.allocator(),
        &context2,
        file_name,
    );
    defer parsed_lines2.deinit();

    try calculate_2(arena_allocator.allocator(), &context2);
}

fn parse_line1(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;

    if (context.done_grid) {
        try context.moves.appendSlice(line);
    } else {
        if (line.len == 0) {
            context.done_grid = true;
            return .{};
        }
        //look for the robot?
        if (context.robot_pos == null) {
            for (line, 0..) |square, i| {
                if (square == Robot) {
                    context.robot_pos = Pos{
                        .i = @as(isize, @intCast(i)),
                        .j = @as(isize, @intCast(context.grid.height)),
                    };
                    break;
                }
            }
        }
        try context.grid.addRow(line);
    }

    return .{};
}

fn parse_line2(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;
    if (context.done_grid) {
        try context.moves.appendSlice(line);
    } else {
        if (line.len == 0) {
            context.done_grid = true;
            return .{};
        }
        //expand the line
        context.expanded_line.clearRetainingCapacity();
        for (line) |square| {
            switch (square) {
                '#' => try context.expanded_line.appendSlice("##"),
                'O' => try context.expanded_line.appendSlice("[]"),
                '.' => try context.expanded_line.appendSlice(".."),
                '@' => try context.expanded_line.appendSlice("@."),
                else => @panic("Unrecognised square!!!"),
            }
        }
        //look for the robot?
        if (context.robot_pos == null) {
            for (context.expanded_line.items, 0..) |square, i| {
                if (square == Robot) {
                    context.robot_pos = Pos{
                        .i = @as(isize, @intCast(i)),
                        .j = @as(isize, @intCast(context.grid.height)),
                    };
                    break;
                }
            }
        }
        try context.grid.addRow(context.expanded_line.items);
    }

    return .{};
}

//Move thing in direction replacing where it was with a space
fn moveThing(grid: *shared.aoc.Grid(Square), pos: Pos, direction: Move) !void {
    const maybe_square = grid.itemAt(pos.i, pos.j);
    if (maybe_square) |square| {
        const new_pos = pos.move(direction);
        try grid.setItemAt(new_pos.i, new_pos.j, square);
        try grid.setItemAt(pos.i, pos.j, Space);
    }
}

fn isHorizontal(direction: Move) bool {
    return direction == Left or direction == Right;
}

fn handleBigBox(
    added_to_layer: *std.AutoHashMap(Pos, void),
    things_to_move: *std.ArrayList(Pos),
    next_layer: *std.ArrayList(Pos),
    direction: Move,
    this_side: Pos,
    other_side: Pos,
) !void {
    if (!added_to_layer.contains(this_side)) {
        try things_to_move.append(this_side);
        if (!isHorizontal(direction)) { //must be moving right or left so don't need to add this side to the next layer
            try next_layer.append(this_side);
        }
        try added_to_layer.put(this_side, {});
    }
    if (!added_to_layer.contains(other_side)) {
        try things_to_move.append(other_side);
        try next_layer.append(other_side);
        try added_to_layer.put(other_side, {});
    }
}

fn doMoves(allocator: std.mem.Allocator, context: *Context) !void {
    var things_to_move = try std.ArrayList(Pos).initCapacity(allocator, 100);
    defer things_to_move.deinit();

    var layer_being_moved: *std.ArrayList(Pos) = try allocator.create(std.ArrayList(Pos));
    layer_being_moved.* = try std.ArrayList(Pos).initCapacity(allocator, 50);
    defer {
        layer_being_moved.deinit();
        allocator.destroy(layer_being_moved);
    }

    var next_layer: *std.ArrayList(Pos) = try allocator.create(std.ArrayList(Pos));
    next_layer.* = try std.ArrayList(Pos).initCapacity(allocator, 50);
    defer {
        next_layer.deinit();
        allocator.destroy(next_layer);
    }

    var added_to_layer = std.AutoHashMap(Pos, void).init(allocator);
    defer added_to_layer.deinit();

    var robot = context.robot_pos.?;

    for (context.moves.items) |direction| {
        // try std.io.getStdOut().writer().print("Move {c}\n", .{direction});
        things_to_move.clearRetainingCapacity();

        layer_being_moved.clearRetainingCapacity();
        try layer_being_moved.append(robot);
        //Look in the direction from all in the layer until we reach a wall or a space.
        //we will move all of these in that direction, if we get to a space in all
        var can_move = false;

        outer: while (true) {
            //decide what to include in the next layer adding to what we'll move.  If we find a Wall, we can't move
            next_layer.clearRetainingCapacity();
            added_to_layer.clearRetainingCapacity();
            for (layer_being_moved.items) |item| {
                const next_pos = item.move(direction);
                const next = context.grid.itemAt(next_pos.i, next_pos.j);
                switch (next.?) {
                    Space => {}, //spaces don't get moved
                    Wall => { //can't move - bomb out here
                        can_move = false;
                        break :outer;
                    },
                    Robot => @panic("Unexpectedly got the robot"),
                    Box => { //we will try to move it, also add to the next layer
                        try things_to_move.append(next_pos);
                        try next_layer.append(next_pos);
                        try added_to_layer.put(next_pos, {});
                    },
                    BoxLeft => { //add the whole box
                        const right = next_pos.move(Right); //have to be moving right
                        try handleBigBox(&added_to_layer, &things_to_move, next_layer, direction, next_pos, right);
                    },
                    BoxRight => { //add the whole box
                        const left = next_pos.move(Left); //have to be moving left
                        try handleBigBox(&added_to_layer, &things_to_move, next_layer, direction, next_pos, left);
                    },
                    else => @panic("Unexpected square type"),
                }
            }
            //Next layer is all spaces (i.e. nothing in it) means we're done
            if (next_layer.items.len == 0) {
                can_move = true;
                break :outer;
            }
            const temp_layer = next_layer;
            next_layer = layer_being_moved;
            layer_being_moved = temp_layer;
        }
        //If Last layer was all spaces, move everything in direction, all other cases don't do anything
        if (can_move) {
            //we should have added in the order such that processing in reverse won't blat anything
            while (things_to_move.items.len > 0) {
                try moveThing(context.grid, things_to_move.pop(), direction);
            }
            //Now move the robot
            try moveThing(context.grid, robot, direction);
            robot = robot.move(direction);
            context.robot_pos = robot;
        }
        // try context.print(std.io.getStdOut().writer());
    }
}

fn calculateGPSSum(grid: *shared.aoc.Grid(Square), interesting_square: Square) usize {
    var sum: usize = 0;
    for (0..grid.height) |j| {
        const j_component = j * 100;
        for (0..grid.width) |i| {
            const square = grid.itemAtU(i, j);
            if (square == interesting_square) {
                sum += j_component + i;
            }
        }
    }
    return sum;
}

fn calculate(allocator: std.mem.Allocator, context: *Context) !void {
    // try context.print(std.io.getStdOut().writer());
    try doMoves(allocator, context);
    // try context.print(std.io.getStdOut().writer());
    const sum = calculateGPSSum(context.grid, Box);
    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, context: *Context) !void {
    // try context.print(std.io.getStdOut().writer());
    try doMoves(allocator, context);
    // try context.print(std.io.getStdOut().writer());
    const sum = calculateGPSSum(context.grid, BoxLeft);
    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
