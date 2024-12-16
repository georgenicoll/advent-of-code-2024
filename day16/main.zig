const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Node = struct {
    const Self = @This();

    i: usize,
    j: usize,

    fn print(self: Self, writer: anytype) !void {
        try writer.print("({d},{d})", .{ self.i, self.j });
    }

    fn move(self: Self, direction: Direction) Node {
        return switch (direction) {
            Direction.north => Node{ .i = self.i, .j = self.j - 1 },
            Direction.south => Node{ .i = self.i, .j = self.j + 1 },
            Direction.east => Node{ .i = self.i + 1, .j = self.j },
            Direction.west => Node{ .i = self.i - 1, .j = self.j },
            Direction.none => @panic("Can't move none"),
        };
    }

    fn eql(self: Self, other: *Node) bool {
        return self.i == other.i and self.j == other.j;
    }
};

const Wall: u8 = '#';
const Space: u8 = '.';
const Start: u8 = 'S';
const End: u8 = 'E';

const Direction = enum {
    north,
    south,
    east,
    west,
    none,
};

const Context = struct {
    nodes: *std.ArrayList(Node),
    start: ?Node = null,
    end: ?Node = null,
    grid: *shared.aoc.Grid(u8),
};

const Line = struct {};

pub fn main() !void {
    const day = "day16";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var nodes = std.ArrayList(Node).init(arena_allocator.allocator());
    defer nodes.deinit();

    var grid = shared.aoc.Grid(u8).init(arena_allocator.allocator());
    defer grid.deinit();

    var context = Context{
        .nodes = &nodes,
        .grid = &grid,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    try calculate(arena_allocator.allocator(), &context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;
    //get all of the nodes
    for (line, 0..) |square, i| {
        const node: ?Node = switch (square) {
            Wall => null,
            Space => Node{ .i = i, .j = context.grid.height },
            Start => start: {
                const n = Node{ .i = i, .j = context.grid.height };
                context.start = n;
                break :start n;
            },
            End => end: {
                const n = Node{ .i = i, .j = context.grid.height };
                context.end = n;
                break :end n;
            },
            else => @panic("Unexpected Square"),
        };
        if (node) |n| {
            try context.nodes.append(n);
        }
    }
    //and add to the grid
    try context.grid.addRow(line);

    return .{};
}

fn outputContext(context: *Context) !void {
    const stdout = std.io.getStdOut();
    try stdout.writeAll("=== Nodes ===");
    for (context.nodes.items) |node| {
        try node.print(stdout.writer());
        try stdout.writeAll("\n");
    }
    try stdout.writeAll("\n");
    try stdout.writeAll("Start: ");
    try context.start.?.print(stdout.writer());
    try stdout.writeAll("\n");
    try stdout.writeAll("End: ");
    try context.end.?.print(stdout.writer());
    try stdout.writeAll("\n");
}

const NodeAndDirection = struct {
    node: Node,
    direction: Direction,
};

const VisitedNode = struct {
    const Self = @This();

    node_and_direction: NodeAndDirection,
    cost: usize,
    from_nodes: *std.ArrayList(*VisitedNode),
    visited: bool,

    fn init(allocator: std.mem.Allocator, node_and_direction: NodeAndDirection, cost: usize) !Self {
        const from_nodes: *std.ArrayList(*VisitedNode) = try allocator.create(std.ArrayList(*VisitedNode));
        from_nodes.* = try std.ArrayList(*VisitedNode).initCapacity(allocator, 4);
        return Self{
            .node_and_direction = node_and_direction,
            .cost = cost,
            .from_nodes = from_nodes,
            .visited = false,
        };
    }

    fn deinit(self: Self, allocator: std.mem.Allocator) void {
        self.from_nodes.deinit();
        allocator.destroy(self.from_nodes);
    }

    fn print(self: Self, writer: anytype) !void {
        try self.node_and_direction.node.print(writer);
        try writer.print(" {any}: {d}", .{ self.node_and_direction.direction, self.cost });
    }
};

fn leastCostLast(ignored: void, node_a: *VisitedNode, node_b: *VisitedNode) bool {
    _ = ignored;
    return node_a.cost > node_b.cost;
}

const directions: [4]Direction = [4]Direction{
    Direction.north,
    Direction.east,
    Direction.south,
    Direction.west,
};

/// Dijkstra - return the visited end node
///
/// visited_by_node_and_direction will own the VisitedNodes that this creates
fn findCheapestRoute(
    allocator: std.mem.Allocator,
    context: *Context,
    visited_by_node_and_direction: *std.AutoHashMap(NodeAndDirection, *VisitedNode),
) ![]*VisitedNode {
    var unvisited_nodes = try std.ArrayList(*VisitedNode).initCapacity(allocator, context.nodes.items.len * 4);
    defer {
        unvisited_nodes.deinit();
    }

    visited_by_node_and_direction.clearRetainingCapacity();
    //populate both unvisited
    for (context.nodes.items) |*node| {
        for (directions) |direction| {
            const nd = NodeAndDirection{
                .node = node.*,
                .direction = direction,
            };
            const uv: *VisitedNode = try allocator.create(VisitedNode);
            uv.* = try VisitedNode.init(allocator, nd, std.math.maxInt(usize));
            try unvisited_nodes.append(uv);
            try visited_by_node_and_direction.put(nd, uv);
        }
    }
    //set start to be cost0
    const start = NodeAndDirection{
        .node = context.start.?,
        .direction = Direction.east,
    };
    const visited = visited_by_node_and_direction.get(start).?;
    visited.cost = 0;

    //dijkstra
    while (unvisited_nodes.items.len > 0) {
        //get the shortest path one to the end
        std.mem.sort(*VisitedNode, unvisited_nodes.items, {}, leastCostLast);
        //get the last one
        const visiting = unvisited_nodes.pop();
        //cost is max, didn't find the end
        if (visiting.cost == std.math.maxInt(usize)) {
            break;
        }
        //end one, we got there - carry on searching
        if (visiting.node_and_direction.node.eql(&context.end.?)) {
            visiting.visited = true;
            continue;
        }
        //Go to the next ones not visited
        for (directions) |direction| {
            const candidate_node = visiting.node_and_direction.node.move(direction);
            const candidate_nandd = NodeAndDirection{
                .node = candidate_node,
                .direction = direction,
            };
            const candidate_uv = visited_by_node_and_direction.get(candidate_nandd);
            if (candidate_uv) |uv| {
                if (uv.visited) {
                    continue; //already got the shortest path to here from this direction
                }
                //calculate what the cost would be
                var move_cost: usize = 1;
                if (direction != visiting.node_and_direction.direction) {
                    move_cost += 1000; //have to turn
                }
                const cost_this_path = visiting.cost + move_cost;
                if (cost_this_path < uv.cost) {
                    //update it for the next round - we have a new shortest replace the from_nodes
                    uv.cost = cost_this_path;
                    uv.from_nodes.clearRetainingCapacity();
                    try uv.from_nodes.append(visiting);
                } else if (cost_this_path == uv.cost) {
                    //Not a new path but add this to a possible from_path
                    try uv.from_nodes.append(visiting);
                }
            }
        }
        visiting.visited = true;
    }

    const result = try allocator.alloc(*VisitedNode, directions.len);
    for (directions, 0..) |direction, i| {
        const nandd = NodeAndDirection{
            .node = context.end.?,
            .direction = direction,
        };
        const removed = visited_by_node_and_direction.fetchRemove(nandd).?;
        result[i] = removed.value;
    }
    return result;
}

fn calculate(allocator: std.mem.Allocator, context: *Context) !void {
    // try outputContext(context);

    var visited_by_node_and_direction = std.AutoHashMap(NodeAndDirection, *VisitedNode).init(allocator);
    defer {
        var it = visited_by_node_and_direction.valueIterator();
        while (it.next()) |visited| {
            visited.*.deinit(allocator);
            allocator.destroy(visited.*);
        }
        visited_by_node_and_direction.deinit();
    }

    var min: usize = std.math.maxInt(usize);
    const result = try findCheapestRoute(allocator, context, &visited_by_node_and_direction);
    defer {
        for (result) |visited| {
            visited.deinit(allocator);
            allocator.destroy(visited);
        }
        allocator.free(result);
    }
    var best: ?*VisitedNode = null;
    for (result) |visited| {
        try visited.print(std.io.getStdOut().writer());
        try std.io.getStdOut().writeAll("\n");
        if (visited.cost < min) {
            min = visited.cost;
            best = visited;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Cost {d}\n", .{min});

    try calculate_2(allocator, best.?);
}

fn calculate_2(allocator: std.mem.Allocator, best_end: *VisitedNode) !void {
    //walk backwards from the end gathering up all of the nodes
    var stack = try std.ArrayList(*VisitedNode).initCapacity(allocator, 1000);
    defer stack.deinit();

    var nodes_in_paths = std.AutoHashMap(Node, void).init(allocator);
    defer nodes_in_paths.deinit();

    try stack.append(best_end);
    while (stack.items.len > 0) {
        const visited_node = stack.pop();
        try nodes_in_paths.put(visited_node.node_and_direction.node, {});
        for (visited_node.from_nodes.items) |*from_node| {
            try stack.append(from_node.*);
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Number {d}\n", .{nodes_in_paths.count()});
}
