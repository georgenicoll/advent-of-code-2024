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

    fn eql(self: Self, other: *const Node) bool {
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
    rows_processed: usize = 0,
    nodes: *std.ArrayList(Node),
    start: ?Node = null,
    end: ?Node = null,
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

    var context = Context{
        .nodes = &nodes,
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
            Space => Node{ .i = i, .j = context.rows_processed },
            Start => start: {
                const n = Node{ .i = i, .j = context.rows_processed };
                context.start = n;
                break :start n;
            },
            End => end: {
                const n = Node{ .i = i, .j = context.rows_processed };
                context.end = n;
                break :end n;
            },
            else => @panic("Unexpected Square"),
        };
        if (node) |n| {
            try context.nodes.append(n);
        }
    }
    context.rows_processed += 1;

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
    node_and_direction: NodeAndDirection,
    cost: usize,
};

const VisitDetails = struct {
    const Self = @This();

    node_and_direction: NodeAndDirection,
    cost: usize,
    from_nodes: *std.ArrayList(*VisitDetails),
    visited: bool,

    fn init(allocator: std.mem.Allocator, node_and_direction: NodeAndDirection, cost: usize) !Self {
        const from_nodes: *std.ArrayList(*VisitDetails) = try allocator.create(std.ArrayList(*VisitDetails));
        from_nodes.* = try std.ArrayList(*VisitDetails).initCapacity(allocator, 4);
        return Self{
            .cost = cost,
            .node_and_direction = node_and_direction,
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
        try writer.print(" {any}, Cost: {d}", .{ self.node_and_direction.direction, self.cost });
    }
};

const directions: [4]Direction = [4]Direction{
    Direction.north,
    Direction.east,
    Direction.south,
    Direction.west,
};

fn closestNodeFn(ignored: void, a: VisitedNode, b: VisitedNode) std.math.Order {
    _ = ignored;
    const cost_ordering = std.math.order(a.cost, b.cost);
    if (cost_ordering != std.math.Order.eq) {
        return cost_ordering;
    }
    //break a tie with j then i then distance
    const j_ordering = std.math.order(a.node_and_direction.node.j, b.node_and_direction.node.j);
    if (j_ordering != std.math.Order.eq) {
        return j_ordering;
    }
    const i_ordering = std.math.order(a.node_and_direction.node.i, b.node_and_direction.node.i);
    if (i_ordering != std.math.Order.eq) {
        return i_ordering;
    }
    return std.math.order(@intFromEnum(a.node_and_direction.direction), @intFromEnum(b.node_and_direction.direction));
}

/// Dijkstra - return the visited end node
///
/// visited_by_node_and_direction will own the VisitDetails that this creates and should free them
fn findCheapestRoute(
    allocator: std.mem.Allocator,
    context: *Context,
    visit_details_by_node_and_direction: *std.AutoHashMap(NodeAndDirection, *VisitDetails),
) ![]*VisitDetails {
    var unvisited_nodes = std.PriorityQueue(VisitedNode, void, closestNodeFn).init(allocator, {});
    defer unvisited_nodes.deinit();

    visit_details_by_node_and_direction.clearRetainingCapacity();
    //populate the map and the priority queue
    for (context.nodes.items) |node| {
        for (directions) |direction| {
            const nd = NodeAndDirection{
                .node = node,
                .direction = direction,
            };
            const cost: usize = if (direction == Direction.east and node.eql(&context.start.?)) 0 else std.math.maxInt(usize);

            const vn = VisitedNode{ .node_and_direction = nd, .cost = cost };
            try unvisited_nodes.add(vn);

            const vd: *VisitDetails = try allocator.create(VisitDetails);
            vd.* = try VisitDetails.init(allocator, nd, cost);
            try visit_details_by_node_and_direction.put(nd, vd);
        }
    }

    //dijkstra
    while (unvisited_nodes.count() > 0) {
        //get the next one
        var visiting_node = unvisited_nodes.remove();
        //cost is max, didn't find the end
        if (visiting_node.cost == std.math.maxInt(usize)) {
            break;
        }
        //end one, we got there - carry on searching
        const visiting_details = visit_details_by_node_and_direction.get(visiting_node.node_and_direction).?;
        if (visiting_node.node_and_direction.node.eql(&context.end.?)) {
            visiting_details.visited = true;
            continue;
        }
        //Go to the next ones not visited
        for (directions) |direction| {
            const candidate_node = visiting_node.node_and_direction.node.move(direction);
            const candidate_nandd = NodeAndDirection{
                .node = candidate_node,
                .direction = direction,
            };
            const maybe_candidate_vd = visit_details_by_node_and_direction.get(candidate_nandd);
            if (maybe_candidate_vd) |candidate_vd| {
                if (candidate_vd.visited) {
                    continue; //already got the shortest path to here from this direction
                }
                //calculate what the cost would be
                var move_cost: usize = 1;
                if (direction != visiting_node.node_and_direction.direction) {
                    move_cost += 1000; //have to turn
                }
                const cost_this_path = visiting_node.cost + move_cost;
                if (cost_this_path < candidate_vd.cost) {
                    //update the visited node in the priority queue
                    const previous_vn = VisitedNode{
                        .node_and_direction = candidate_nandd,
                        .cost = candidate_vd.cost,
                    };
                    const updated_vn = VisitedNode{
                        .node_and_direction = candidate_nandd,
                        .cost = cost_this_path,
                    };
                    try unvisited_nodes.update(previous_vn, updated_vn);
                    //and update the details - we have a new shortest - replace the from_nodes - update in the unvisited_nodes
                    candidate_vd.cost = cost_this_path;
                    candidate_vd.from_nodes.clearRetainingCapacity();
                    try candidate_vd.from_nodes.append(visiting_details);
                } else if (cost_this_path == candidate_vd.cost) {
                    //Not a new path but add this to a possible from_path
                    try candidate_vd.from_nodes.append(visiting_details);
                }
            }
        }
        visiting_details.visited = true;
    }

    const result = try allocator.alloc(*VisitDetails, directions.len);
    for (directions, 0..) |direction, i| {
        const nandd = NodeAndDirection{
            .node = context.end.?,
            .direction = direction,
        };
        const removed = visit_details_by_node_and_direction.fetchRemove(nandd).?;
        result[i] = removed.value;
    }
    return result;
}

fn calculate(allocator: std.mem.Allocator, context: *Context) !void {
    // try outputContext(context);

    var visit_details_by_node_and_direction = std.AutoHashMap(NodeAndDirection, *VisitDetails).init(allocator);
    defer {
        var it = visit_details_by_node_and_direction.valueIterator();
        while (it.next()) |details| {
            details.*.deinit(allocator);
            allocator.destroy(details.*);
        }
        visit_details_by_node_and_direction.deinit();
    }

    var min: usize = std.math.maxInt(usize);
    const result = try findCheapestRoute(allocator, context, &visit_details_by_node_and_direction);
    defer {
        for (result) |details| {
            details.deinit(allocator);
            allocator.destroy(details);
        }
        allocator.free(result);
    }
    var best: ?*VisitDetails = null;
    for (result) |details| {
        try details.print(std.io.getStdOut().writer());
        try std.io.getStdOut().writeAll("\n");
        if (details.cost < min) {
            min = details.cost;
            best = details;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Cost {d}\n", .{min});

    try calculate_2(allocator, best.?);
}

fn calculate_2(allocator: std.mem.Allocator, best_end: *VisitDetails) !void {
    //walk backwards from the end gathering up all of the nodes
    var stack = try std.ArrayList(*VisitDetails).initCapacity(allocator, 1000);
    defer stack.deinit();

    var nodes_in_paths = std.AutoHashMap(Node, void).init(allocator);
    defer nodes_in_paths.deinit();

    try stack.append(best_end);
    while (stack.items.len > 0) {
        const visit_details = stack.pop();
        try nodes_in_paths.put(visit_details.node_and_direction.node, {});
        for (visit_details.from_nodes.items) |*from_node| {
            try stack.append(from_node.*);
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Number {d}\n", .{nodes_in_paths.count()});
}
