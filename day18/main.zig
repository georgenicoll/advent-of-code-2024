const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

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

    fn eql(self: Self, other: *const Self) bool {
        return self.i == other.i and self.j == other.j;
    }
};

const Space: u8 = '.';
const Byte: u8 = '#';

const Direction = enum {
    up,
    down,
    left,
    right,
};

const Dimensions = Pos;

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
    dimensions: Dimensions,
    steps: usize,
    byte_positions: *std.ArrayList(Pos),
    start: Pos,
    end: Pos,
};

const Line = struct {};

pub fn main() !void {
    const day = "day18";
    // const file_name = day ++ "/test_file.txt";
    // const dimensions = Dimensions{ .i = 7, .j = 7 };
    // const steps: usize = 12;
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";
    const dimensions = Dimensions{ .i = 71, .j = 71 };
    const steps: usize = 1024;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(',', true);

    var byte_positions = try std.ArrayList(Pos).initCapacity(arena_allocator.allocator(), 4000);
    defer byte_positions.deinit();

    var context = Context{
        .delimiters = delimiters,
        .dimensions = dimensions,
        .steps = steps,
        .byte_positions = &byte_positions,
        .start = Pos{ .i = 0, .j = 0 },
        .end = Pos{ .i = dimensions.i - 1, .j = dimensions.j - 1 },
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    try calculate(arena_allocator.allocator(), &context);
    try calculate_2(arena_allocator.allocator(), &context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    if (line.len == 0) {
        return .{};
    }

    var parser = shared.process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    const i = try parser.read_int(isize, 10);
    const j = try parser.read_int(isize, 10);

    try context.byte_positions.append(Pos{ .i = i, .j = j });

    return .{};
}

//TODO: Generify - copied and adapted from Day 16

// const PosAndDirection = struct {
//     pos: Pos,
//     direction: Direction,
// };

const VisitedPos = struct {
    pos: Pos,
    cost: usize,
};

const VisitDetails = struct {
    const Self = @This();

    pos: Pos,
    cost: usize,
    from: *std.ArrayList(*VisitDetails),
    visited: bool,

    fn init(allocator: std.mem.Allocator, pos: Pos, cost: usize) !Self {
        const from: *std.ArrayList(*VisitDetails) = try allocator.create(std.ArrayList(*VisitDetails));
        from.* = try std.ArrayList(*VisitDetails).initCapacity(allocator, 4);
        return Self{
            .cost = cost,
            .pos = pos,
            .from = from,
            .visited = false,
        };
    }

    fn deinit(self: Self, allocator: std.mem.Allocator) void {
        self.from.deinit();
        allocator.destroy(self.from);
    }

    fn print(self: Self, writer: anytype) !void {
        try self.pos.print(writer);
        try writer.print(" Cost: {d}", .{self.cost});
    }
};

const directions: [4]Direction = [4]Direction{
    Direction.up,
    Direction.down,
    Direction.left,
    Direction.right,
};

fn closestNodeFn(ignored: void, a: VisitedPos, b: VisitedPos) std.math.Order {
    _ = ignored;
    const cost_ordering = std.math.order(a.cost, b.cost);
    if (cost_ordering != std.math.Order.eq) {
        return cost_ordering;
    }
    //break a tie with j then i then distance
    const j_ordering = std.math.order(a.pos.j, b.pos.j);
    if (j_ordering != std.math.Order.eq) {
        return j_ordering;
    }
    return std.math.order(a.pos.i, b.pos.i);
}

const UnvisitedQueue = std.PriorityQueue(VisitedPos, void, closestNodeFn);

fn populateVisitingStructs(
    allocator: std.mem.Allocator,
    context: *Context,
    grid: *shared.aoc.Grid(u8),
    visit_details_by_pos: *std.AutoHashMap(Pos, *VisitDetails),
    unvisited: *UnvisitedQueue,
) !void {
    visit_details_by_pos.clearRetainingCapacity();
    //populate the map and the priority queue - we can use the grid to populate all of the positions that are valid
    for (0..grid.height) |j_u| {
        const j = @as(isize, @intCast(j_u));
        for (0..grid.width) |i_u| {
            const i = @as(isize, @intCast(i_u));
            const item = grid.itemAt(i, j).?;
            if (item != Byte) {
                const pos = Pos{ .i = i, .j = j };
                const cost: usize = if (pos.eql(&context.start)) 0 else std.math.maxInt(usize);

                const vp = VisitedPos{ .pos = pos, .cost = cost };
                try unvisited.add(vp);

                const vd: *VisitDetails = try allocator.create(VisitDetails);
                vd.* = try VisitDetails.init(allocator, pos, cost);
                try visit_details_by_pos.put(pos, vd);
            }
        }
    }
}

/// Dijkstra - return the visited end node
///
/// visited_by_node_and_direction will own the VisitDetails that this creates and should free them
fn findCheapestRoute(
    context: *Context,
    visit_details_by_pos: *std.AutoHashMap(Pos, *VisitDetails),
    unvisited: *UnvisitedQueue,
) !*VisitDetails {
    //dijkstra
    while (unvisited.count() > 0) {
        //get the next one
        var visiting = unvisited.remove();
        //cost is max, didn't find the end
        if (visiting.cost == std.math.maxInt(usize)) {
            break;
        }
        //if end one, we got there, done
        const visiting_details = visit_details_by_pos.get(visiting.pos).?;
        if (visiting_details.pos.eql(&context.end)) {
            visiting_details.visited = true;
            break;
        }
        //Go to the next ones not visited
        for (directions) |direction| {
            const candidate_pos = visiting.pos.move(direction);
            const maybe_candidate_details = visit_details_by_pos.get(candidate_pos);
            if (maybe_candidate_details) |candidate_details| {
                if (candidate_details.visited) {
                    continue; //already got the shortest path to here from this direction
                }
                //calculate what the cost would be
                const move_cost: usize = 1; //only ever 1 in this case
                const cost_this_path = visiting.cost + move_cost;
                if (cost_this_path < candidate_details.cost) {
                    //update the VisitedPos in the priority queue
                    const previous = VisitedPos{
                        .pos = candidate_pos,
                        .cost = candidate_details.cost,
                    };
                    const updated = VisitedPos{
                        .pos = candidate_pos,
                        .cost = cost_this_path,
                    };
                    try unvisited.update(previous, updated);
                    //and update the details - we have a new shortest - replace the from_nodes - update in the unvisited_nodes
                    candidate_details.cost = cost_this_path;
                    candidate_details.from.clearRetainingCapacity();
                    try candidate_details.from.append(visiting_details);
                } else if (cost_this_path == candidate_details.cost) {
                    //Not a new path but add this to a possible from_path
                    try candidate_details.from.append(visiting_details);
                }
            }
        }
        visiting_details.visited = true;
    }

    return visit_details_by_pos.get(context.end).?;
}

fn freeUpVisitDetails(allocator: std.mem.Allocator, visit_details_by_pos: *std.AutoHashMap(Pos, *VisitDetails)) void {
    var it = visit_details_by_pos.valueIterator();
    while (it.next()) |details| {
        details.*.deinit(allocator);
        allocator.destroy(details.*);
    }
}

fn calculate(allocator: std.mem.Allocator, context: *Context) !void {
    //build and populate grid...
    const width = @as(usize, @intCast(context.dimensions.i));
    const height = @as(usize, @intCast(context.dimensions.j));

    var empty_line = try std.ArrayList(u8).initCapacity(allocator, width);
    defer empty_line.deinit();
    try empty_line.appendNTimes(Space, width);

    var grid = shared.aoc.Grid(u8).init(allocator);
    for (0..height) |_| {
        try grid.addRow(empty_line.items);
    }
    for (context.byte_positions.items[0..context.steps]) |pos| {
        try grid.setItemAt(pos.i, pos.j, Byte);
    }
    try grid.print(std.io.getStdOut().writer(), "{c}");
    try std.io.getStdOut().writeAll("\n");

    //structures for finding...
    var unvisited = UnvisitedQueue.init(allocator, {});
    defer unvisited.deinit();

    var visit_details_by_pos = std.AutoHashMap(Pos, *VisitDetails).init(allocator);
    defer {
        freeUpVisitDetails(allocator, &visit_details_by_pos);
        visit_details_by_pos.deinit();
    }

    try populateVisitingStructs(
        allocator,
        context,
        &grid,
        &visit_details_by_pos,
        &unvisited,
    );
    const details = try findCheapestRoute(
        context,
        &visit_details_by_pos,
        &unvisited,
    );

    try std.io.getStdOut().writer().print("Part 1 Steps {d}\n", .{details.cost});
}

/// This feels a bit brute force and has to be built with --release=fast to finish in an 'acceptable' time.
/// Should investigate ways of detecting a graph becoming split as we add nodes.
fn calculate_2(allocator: std.mem.Allocator, context: *Context) !void {
    //build and populate grid...
    const width = @as(usize, @intCast(context.dimensions.i));
    const height = @as(usize, @intCast(context.dimensions.j));

    var empty_line = try std.ArrayList(u8).initCapacity(allocator, width);
    defer empty_line.deinit();
    try empty_line.appendNTimes(Space, width);

    var grid = shared.aoc.Grid(u8).init(allocator);
    for (0..height) |_| {
        try grid.addRow(empty_line.items);
    }

    var visit_details_by_pos = std.AutoHashMap(Pos, *VisitDetails).init(allocator);
    defer {
        freeUpVisitDetails(allocator, &visit_details_by_pos);
        visit_details_by_pos.deinit();
    }

    //populate know good
    for (context.byte_positions.items[0..context.steps]) |pos| {
        try grid.setItemAt(pos.i, pos.j, Byte);
    }
    try grid.print(std.io.getStdOut().writer(), "{c}");
    try std.io.getStdOut().writeAll("\n");

    var blocking_pos: ?Pos = null;
    //now try adding each next one and see whether we can
    for (context.byte_positions.items[context.steps..]) |pos| {
        try grid.setItemAt(pos.i, pos.j, Byte);

        freeUpVisitDetails(allocator, &visit_details_by_pos);
        visit_details_by_pos.clearRetainingCapacity();
        //structures for finding...
        var unvisited = UnvisitedQueue.init(allocator, {});
        defer unvisited.deinit();

        try populateVisitingStructs(
            allocator,
            context,
            &grid,
            &visit_details_by_pos,
            &unvisited,
        );
        const details = try findCheapestRoute(
            context,
            &visit_details_by_pos,
            &unvisited,
        );
        if (details.cost == std.math.maxInt(usize)) {
            //couldn't get there
            blocking_pos = pos;
            break;
        }
    }
    try grid.print(std.io.getStdOut().writer(), "{c}");
    try std.io.getStdOut().writeAll("\n");

    try std.io.getStdOut().writeAll("Part 2 Blocking Pos: ");
    try blocking_pos.?.print(std.io.getStdOut().writer());
    try std.io.getStdOut().writeAll("\n");
}
