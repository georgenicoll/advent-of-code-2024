const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const String = []const u8;

const StringSet = std.StringHashMap(void);

const Node = struct {
    const Self = @This();

    id: String,
    connected_to: *StringSet,

    fn init(allocator: std.mem.Allocator, id: String) !Self {
        const connected_to: *StringSet = try allocator.create(StringSet);
        connected_to.* = StringSet.init(allocator);
        return Self{
            .id = try allocator.dupe(u8, id),
            .connected_to = connected_to,
        };
    }

    fn deinit(self: Self, allocator: std.mem.Allocator) void {
        self.connected_to.deinit();
        allocator.free(self.id);
    }

    fn print(self: Self, writer: anytype) !void {
        try writer.writeAll(self.id);
        try writer.writeAll(" => ");
        var it = self.connected_to.keyIterator();
        while (it.next()) |connected_to| {
            try writer.writeAll(connected_to.*);
            try writer.writeAll(",");
        }
    }
};

const Edge = struct {
    const Self = @This();

    from: String,
    to: String,

    //Takes ownership of from and to
    fn initTakeOwnership(allocator: std.mem.Allocator, from: String, to: String) !Self {
        _ = allocator;
        return Self{
            .from = from,
            .to = to,
        };
    }

    fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.from);
        allocator.free(self.to);
    }
};

const Context = struct {
    const Self = @This();

    delimiters: std.AutoHashMap(u8, bool),
    edges: *std.ArrayList(*Edge),
    nodes: *std.StringHashMap(*Node),

    fn print(self: Self, writer: anytype) !void {
        var node_it = self.nodes.iterator();
        while (node_it.next()) |entry| {
            try writer.writeAll("Node ");
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeAll(" -> ");
            try entry.value_ptr.*.print(writer);
            try writer.writeAll("\n");
        }
    }
};

const Line = struct {};

pub fn main() !void {
    const day = "day23";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put('-', true);

    var edges = std.ArrayList(*Edge).init(arena_allocator.allocator());
    defer {
        for (edges.items) |edge| {
            edge.deinit(arena_allocator.allocator());
            arena_allocator.allocator().destroy(edge);
        }
        edges.deinit();
    }

    var nodes = std.StringHashMap(*Node).init(arena_allocator.allocator());
    defer {
        var it = nodes.valueIterator();
        while (it.next()) |node| {
            node.*.deinit(arena_allocator.allocator());
            arena_allocator.allocator().destroy(node);
        }
        nodes.deinit();
    }

    var context = Context{
        .delimiters = delimiters,
        .edges = &edges,
        .nodes = &nodes,
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

    const start = try parser.read_string();
    const end = try parser.read_string();

    const edge: *Edge = try allocator.create(Edge);
    edge.* = try Edge.initTakeOwnership(allocator, start, end);
    try context.edges.append(edge);

    //start node
    const start_result = try context.nodes.getOrPut(start);
    if (!start_result.found_existing) {
        const node: *Node = try allocator.create(Node);
        node.* = try Node.init(allocator, start);
        start_result.value_ptr.* = node;
    }
    try start_result.value_ptr.*.connected_to.put(end, {});

    //end node
    const end_result = try context.nodes.getOrPut(end);
    if (!end_result.found_existing) {
        const node: *Node = try allocator.create(Node);
        node.* = try Node.init(allocator, end);
        end_result.value_ptr.* = node;
    }
    try end_result.value_ptr.*.connected_to.put(start, {});

    return .{};
}

/// Caller owns the string set
fn constructNodeIdSet(allocator: std.mem.Allocator, node: *Node) !*StringSet {
    var result = try allocator.create(StringSet);
    result.* = StringSet.init(allocator);

    try result.put(node.id, {});

    var it = node.connected_to.keyIterator();
    while (it.next()) |connected_to| {
        try result.put(connected_to.*, {});
    }

    return result;
}

fn intersection(a: *StringSet, b: *StringSet, result: *StringSet) !void {
    result.clearRetainingCapacity();

    var it = a.keyIterator();
    while (it.next()) |key| {
        if (b.contains(key.*)) {
            try result.put(key.*, {});
        }
    }
}

fn removeNotFound(allocator: std.mem.Allocator, mainSet: *StringSet, other: *StringSet) !void {
    var toRemove = try std.ArrayList(String).initCapacity(allocator, mainSet.count());
    defer toRemove.deinit();

    var it = mainSet.keyIterator();
    while (it.next()) |key| {
        if (!other.contains(key.*)) {
            try toRemove.append(key.*);
        }
    }
    for (toRemove.items) |remove| {
        _ = mainSet.remove(remove);
    }
}

//Caller owns the string
fn keyForList(allocator: std.mem.Allocator, list: *std.ArrayList(String)) !String {
    std.mem.sort([]const u8, list.items, {}, stringLessThan);

    var result = try std.ArrayList(u8).initCapacity(allocator, list.items.len * 2);
    defer result.deinit();

    for (list.items) |key| {
        try result.writer().writeAll(key);
        try result.writer().writeAll(",");
    }
    return try result.toOwnedSlice();
}

//Caller owns the string
fn keyForSet(allocator: std.mem.Allocator, set: *StringSet) !String {
    //Order by lowest alphabetically
    var keys = try std.ArrayList(String).initCapacity(allocator, set.count());
    defer keys.deinit();

    var it = set.keyIterator();
    while (it.next()) |key| {
        try keys.append(key.*);
    }

    return keyForList(allocator, &keys);
}

fn stringLessThan(_: void, lhs: String, rhs: String) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn outputStringSet(set: *StringSet) !void {
    var it = set.keyIterator();
    while (it.next()) |value| {
        try std.io.getStdOut().writeAll(value.*);
        try std.io.getStdOut().writeAll(",");
    }
    try std.io.getStdOut().writeAll("\n");
}

fn calculate(allocator: std.mem.Allocator, context: *const Context) !void {
    // try context.print(std.io.getStdOut().writer());

    var found_keys = StringSet.init(allocator);
    defer found_keys.deinit();

    var results = try std.ArrayList(String).initCapacity(allocator, 3);
    defer results.deinit();

    var node_it = context.nodes.valueIterator();
    while (node_it.next()) |node| {
        var outer_it = node.*.connected_to.keyIterator();
        while (outer_it.next()) |outer| {
            var inner_it = node.*.connected_to.keyIterator();
            while (inner_it.next()) |inner| {
                if (eql(u8, outer.*, inner.*)) {
                    continue;
                }
                //Check if the outer points to the inner, if so we have a loop of 3 and a candidate
                const outer_node = context.nodes.get(outer.*).?;
                if (!outer_node.connected_to.contains(inner.*)) {
                    continue; //not a loop... go to the next one
                }
                //Does any of this begin with a 't'?  If not look again
                if (!(node.*.id[0] == 't' or outer.*[0] == 't' or inner.*[0] == 't')) {
                    continue;
                }
                //We have a 't' and we have a loop put into the result set
                results.clearRetainingCapacity();
                try results.append(node.*.id);
                try results.append(outer.*);
                try results.append(inner.*);
                const results_key = try keyForList(allocator, &results);
                try found_keys.put(results_key, {});
            }
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Count {d}\n", .{found_keys.count()});
}

fn calculate_2(allocator: std.mem.Allocator, context: *const Context) !void {
    var max_ids: ?StringSet = null;

    var node_it = context.nodes.valueIterator();
    while (node_it.next()) |node| {
        const node_ids = try constructNodeIdSet(allocator, node.*);

        var outer_it = node.*.connected_to.keyIterator();
        while (outer_it.next()) |outer_connected_to| {
            const outer_node = context.nodes.get(outer_connected_to.*).?;
            const outer_ids = try constructNodeIdSet(allocator, outer_node);

            var overlap = StringSet.init(allocator);

            try intersection(node_ids, outer_ids, &overlap);

            var overlap_it = overlap.keyIterator();
            while (overlap_it.next()) |overlap_id| {
                const overlap_node = context.nodes.get(overlap_id.*).?;
                const overlap_nodes_ids = try constructNodeIdSet(allocator, overlap_node);
                try removeNotFound(allocator, &overlap, overlap_nodes_ids);
            }

            //does this contain the most ids?
            if (max_ids == null or overlap.count() > max_ids.?.count()) {
                max_ids = overlap;
            }
        }
    }

    var results = try std.ArrayList(String).initCapacity(allocator, max_ids.?.count());
    var ids_it = max_ids.?.keyIterator();
    while (ids_it.next()) |id| {
        try results.append(id.*);
    }
    std.mem.sort(String, results.items, {}, stringLessThan);
    try std.io.getStdOut().writer().writeAll("Part 2 Result: ");
    for (results.items) |id| {
        try std.io.getStdOut().writer().writeAll(id);
        try std.io.getStdOut().writer().writeAll(",");
    }
    try std.io.getStdOut().writer().writeAll("\n");
}
