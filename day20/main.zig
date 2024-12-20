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

    try calculate(arena_allocator.allocator(), &context);
    try calculate_2(arena_allocator.allocator(), &context);
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

    fn eql(self: Self, other: *const Self) bool {
        return self.i == other.i and self.j == other.j;
    }
};

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
            if (item != Wall) {
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
/// visited_details_by_pos will own the VisitDetails that this creates and should free them
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

// Maybe remove above

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
    steps_by_pos: *std.AutoHashMap(Pos, *Step),
) !void {
    steps.clearRetainingCapacity();

    var visited = std.AutoHashMap(Pos, void).init(allocator);
    defer visited.deinit();

    //First step starts at the start
    var current_step = try Step.init(allocator, context.start.?, 0);
    try steps.append(current_step);
    try steps_by_pos.put(current_step.pos, current_step);

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
                    try steps_by_pos.put(new_step.pos, new_step);
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
    steps: *std.ArrayList(*Step),
    steps_by_pos: *std.AutoHashMap(Pos, *Step),
    cheats: *std.ArrayList(Cheat),
) !void {
    //work through all of the steps trying to find cheats (jumps of 2 in any direction through a wall that find the path again)
    for (steps.items) |step| {
        for (directions) |direction| {
            const cheat_end = step.pos.move(direction).move(direction); //2 jumps
            //does this save?
            const maybe_on_path = steps_by_pos.get(cheat_end);
            if (maybe_on_path) |on_path| {
                //only worth it if steps would actually be saved
                if (on_path.step_number > step.step_number + 2) {
                    const steps_saved = on_path.step_number - step.step_number - 2;
                    const cheat = Cheat{
                        .start_pos = step.pos,
                        .end_pos = on_path.pos,
                        .saves_steps = steps_saved,
                    };
                    try cheats.append(cheat);
                }
            }
        }
    }
}

fn calculate(allocator: std.mem.Allocator, context: *const Context) !void {
    try context.print(std.io.getStdOut().writer());

    //first calculate the shortest path through the maze
    var steps = try std.ArrayList(*Step).initCapacity(allocator, 1000);
    defer {
        for (steps.items) |step| {
            allocator.destroy(step);
        }
        steps.deinit();
    }
    var steps_by_pos = std.AutoHashMap(Pos, *Step).init(allocator);
    defer steps_by_pos.deinit();

    try findPath(allocator, context, &steps, &steps_by_pos);

    var cheats = try std.ArrayList(Cheat).initCapacity(allocator, steps.items.len);
    defer cheats.deinit();

    try findCheats(&steps, &steps_by_pos, &cheats);

    var sum: usize = 0;
    for (cheats.items) |cheat| {
        if (cheat.saves_steps > 99) { //at least 100 for the main input
            sum += 1;
        }
    }
    try std.io.getStdOut().writer().print("Part 1 Cheats Saving enough time {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, context: *const Context) !void {
    _ = allocator;
    _ = context;

    var sum: usize = 0;
    sum += 0;

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
