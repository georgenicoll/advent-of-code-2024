const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    codes: *std.ArrayList([]const u8),
};

const Line = struct {};

const buttons_keypad = "0123456789A";
const buttons_robot_keypad = "^v><A";

const ButtonComb = struct {
    start_button: u8,
    end_button: u8,
};

pub fn main() !void {
    const day = "day21";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var codes = try std.ArrayList([]const u8).initCapacity(arena_allocator.allocator(), 4);
    defer codes.deinit();

    var keypad = shared.aoc.Grid(u8).init(arena_allocator.allocator());
    defer keypad.deinit();
    try keypad.addRow("789");
    try keypad.addRow("456");
    try keypad.addRow("123");
    try keypad.addRow(".0A");

    var keypad_button_combs = std.AutoHashMap(ButtonComb, []const u8).init(arena_allocator.allocator());
    defer keypad_button_combs.deinit();
    try calculateCombinations(arena_allocator.allocator(), buttons_keypad, &keypad, &keypad_button_combs);

    var robot_keypad = shared.aoc.Grid(u8).init(arena_allocator.allocator());
    defer robot_keypad.deinit();
    try robot_keypad.addRow(".^A");
    try robot_keypad.addRow("<v>");

    var robot_button_combs = std.AutoHashMap(ButtonComb, []const u8).init(arena_allocator.allocator());
    defer robot_button_combs.deinit();
    try calculateCombinations(arena_allocator.allocator(), buttons_robot_keypad, &robot_keypad, &robot_button_combs);

    var context = Context{
        .codes = &codes,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    const part1 = try calculate(arena_allocator.allocator(), &context, &keypad_button_combs, &robot_button_combs, 2);
    try std.io.getStdOut().writer().print("Part 1 {d}\n", .{part1});

    const part2 = try calculate(arena_allocator.allocator(), &context, &keypad_button_combs, &robot_button_combs, 25);
    try std.io.getStdOut().writer().print("Part 2 {d}\n", .{part2});
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    if (line.len > 0) {
        try context.codes.append(try allocator.dupe(u8, line));
    }
    return .{};
}

//TODO: Generify - copied and adapted from Day 16/18 three now
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
            Direction.left => Self{ .i = self.i - 1, .j = self.j },
            Direction.right => Self{ .i = self.i + 1, .j = self.j },
        };
    }

    fn eql(self: Self, other: *const Self) bool {
        return self.i == other.i and self.j == other.j;
    }
};

const Space: u8 = '.';

const Direction = enum {
    const Self = @This();

    up,
    down,
    left,
    right,

    fn toButton(self: Self) u8 {
        return switch (self) {
            Direction.up => '^',
            Direction.down => 'v',
            Direction.left => '<',
            Direction.right => '>',
        };
    }
};

const PosAndDirection = struct {
    pos: Pos,
    direction: Direction,
};

const VisitedPosAndDirection = struct {
    pos_and_direction: PosAndDirection,
    cost: usize,
};

const VisitDetails = struct {
    const Self = @This();

    pos_and_direction: PosAndDirection,
    button: u8,
    cost: usize,
    from: *std.ArrayList(*VisitDetails),
    visited: bool,

    fn init(allocator: std.mem.Allocator, pos_and_direction: PosAndDirection, button: u8, cost: usize) !Self {
        const from: *std.ArrayList(*VisitDetails) = try allocator.create(std.ArrayList(*VisitDetails));
        from.* = try std.ArrayList(*VisitDetails).initCapacity(allocator, 4);
        return Self{
            .cost = cost,
            .pos_and_direction = pos_and_direction,
            .button = button,
            .from = from,
            .visited = false,
        };
    }

    fn deinit(self: Self, allocator: std.mem.Allocator) void {
        self.from.deinit();
        allocator.destroy(self.from);
    }

    fn print(self: Self, writer: anytype) !void {
        try self.pos_and_direction.pos.print(writer);
        try writer.print(" Direction {any} Button: {c} Cost: {d}", .{ self.pos_and_direction.direction, self.button, self.cost });
    }
};

const directions: [4]Direction = [4]Direction{
    Direction.up,
    Direction.down,
    Direction.left,
    Direction.right,
};

fn closestNodeFn(ignored: void, a: VisitedPosAndDirection, b: VisitedPosAndDirection) std.math.Order {
    _ = ignored;
    const cost_ordering = std.math.order(a.cost, b.cost);
    if (cost_ordering != std.math.Order.eq) {
        return cost_ordering;
    }
    //break a tie with j then i then distance
    const j_ordering = std.math.order(a.pos_and_direction.pos.j, b.pos_and_direction.pos.j);
    if (j_ordering != std.math.Order.eq) {
        return j_ordering;
    }
    const i_ordering = std.math.order(a.pos_and_direction.pos.i, b.pos_and_direction.pos.i);
    if (i_ordering != std.math.Order.eq) {
        return i_ordering;
    }
    return std.math.order(@intFromEnum(a.pos_and_direction.direction), @intFromEnum(b.pos_and_direction.direction));
}

const UnvisitedQueue = std.PriorityQueue(VisitedPosAndDirection, void, closestNodeFn);

fn populateVisitingStructs(
    allocator: std.mem.Allocator,
    start: u8,
    end: u8,
    grid: *shared.aoc.Grid(u8),
    visit_details_by_pos_and_direction: *std.AutoHashMap(PosAndDirection, *VisitDetails),
    unvisited: *UnvisitedQueue,
) !Pos {
    var end_button_pos: ?Pos = null;
    //populate the map and the priority queue - we can use the grid to populate all of the positions that are valid
    for (0..grid.height) |j_u| {
        const j = @as(isize, @intCast(j_u));
        for (0..grid.width) |i_u| {
            const i = @as(isize, @intCast(i_u));
            const item = grid.itemAt(i, j).?;
            if (item != Space) {
                const pos = Pos{ .i = i, .j = j };
                const cost: usize = if (item == start) 0 else std.math.maxInt(usize);
                if (item == end) {
                    end_button_pos = pos;
                }

                for (directions) |direction| {
                    const pos_and_direction = PosAndDirection{
                        .pos = pos,
                        .direction = direction,
                    };
                    const vp = VisitedPosAndDirection{
                        .pos_and_direction = pos_and_direction,
                        .cost = cost,
                    };
                    try unvisited.add(vp);

                    const vd: *VisitDetails = try allocator.create(VisitDetails);
                    vd.* = try VisitDetails.init(
                        allocator,
                        pos_and_direction,
                        item,
                        cost,
                    );
                    try visit_details_by_pos_and_direction.put(pos_and_direction, vd);
                }
            }
        }
    }
    return end_button_pos.?;
}

fn findCheapestRoute(
    allocator: std.mem.Allocator,
    end: Pos,
    visit_details_by_pos_and_direction: *std.AutoHashMap(PosAndDirection, *VisitDetails),
    unvisited: *UnvisitedQueue,
) ![]*VisitDetails {
    //dijkstra
    while (unvisited.count() > 0) {
        //get the next one
        var visiting = unvisited.remove();
        //cost is max, didn't find the end
        if (visiting.cost == std.math.maxInt(usize)) {
            break;
        }
        //if end one, we got there, done
        const visiting_details = visit_details_by_pos_and_direction.get(visiting.pos_and_direction).?;
        if (visiting_details.pos_and_direction.pos.eql(&end)) {
            visiting_details.visited = true;
            break;
        }
        //Go to the next ones not visited
        for (directions) |direction| {
            const candidate_pos = visiting.pos_and_direction.pos.move(direction);
            const candidate_pos_and_direction = PosAndDirection{
                .pos = candidate_pos,
                .direction = direction,
            };
            const maybe_candidate_details = visit_details_by_pos_and_direction.get(candidate_pos_and_direction);
            if (maybe_candidate_details) |candidate_details| {
                if (candidate_details.visited) {
                    continue; //already got the shortest path to here from this direction
                }
                //calculate what the cost would be
                //move cost is slightly more if we have to change direction
                const move_cost: usize = if (visiting.pos_and_direction.direction != direction) 11 else 10;
                const cost_this_path = visiting.cost + move_cost;
                if (cost_this_path < candidate_details.cost) {
                    //update the VisitedPos in the priority queue
                    const previous = VisitedPosAndDirection{
                        .pos_and_direction = candidate_pos_and_direction,
                        .cost = candidate_details.cost,
                    };
                    const updated = VisitedPosAndDirection{
                        .pos_and_direction = candidate_pos_and_direction,
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

    var possible_visit_details = try std.ArrayList(*VisitDetails).initCapacity(allocator, 2);
    defer possible_visit_details.deinit();

    var lowest_cost_so_far: usize = std.math.maxInt(usize);
    for (directions) |direction| {
        const end_and_direction = PosAndDirection{
            .pos = end,
            .direction = direction,
        };
        const maybe_details = visit_details_by_pos_and_direction.get(end_and_direction);
        if (maybe_details) |details| {
            if (details.cost < std.math.maxInt(usize)) {
                if (details.cost > lowest_cost_so_far) {
                    continue;
                }
                if (details.cost < lowest_cost_so_far) {
                    lowest_cost_so_far = details.cost;
                    possible_visit_details.clearRetainingCapacity();
                }
                try possible_visit_details.append(details);
            }
        }
    }
    return try possible_visit_details.toOwnedSlice();
}

fn leftBeforeUpBeforeDownBeforeRight(ignored: void, lhs: []const u8, rhs: []const u8) bool {
    _ = ignored;
    if (lhs[0] == '<') {
        return true;
    }
    if (rhs[0] == '<') {
        return false;
    }
    if (lhs[0] == '^') {
        return true;
    }
    if (rhs[0] == '^') {
        return false;
    }
    if (lhs[0] == 'v') {
        return true;
    }
    if (rhs[0] == 'v') {
        return false;
    }
    if (lhs[0] == '>') {
        return true;
    }
    return false;
}

fn calculateCombinations(
    allocator: std.mem.Allocator,
    buttons: []const u8,
    keypad: *shared.aoc.Grid(u8),
    combs: *std.AutoHashMap(ButtonComb, []const u8),
) !void {
    var visit_details_by_pos_and_direction = std.AutoHashMap(PosAndDirection, *VisitDetails).init(allocator);
    defer visit_details_by_pos_and_direction.deinit();

    for (0..buttons.len) |start| {
        const start_button = buttons[start];
        for (0..buttons.len) |end| {
            if (start == end) {
                continue;
            }
            const end_button = buttons[end];
            //populate structures first
            visit_details_by_pos_and_direction.clearRetainingCapacity();
            var unvisited = UnvisitedQueue.init(allocator, {});
            defer unvisited.deinit();

            const end_button_pos = try populateVisitingStructs(
                allocator,
                start_button,
                end_button,
                keypad,
                &visit_details_by_pos_and_direction,
                &unvisited,
            );
            //find the shortest paths
            const cheapest_routes = try findCheapestRoute(
                allocator,
                end_button_pos,
                &visit_details_by_pos_and_direction,
                &unvisited,
            );
            //record these
            const button_comb = ButtonComb{
                .start_button = start_button,
                .end_button = end_button,
            };

            var combinations: *std.ArrayList([]const u8) = try allocator.create(std.ArrayList([]const u8));
            combinations.* = try std.ArrayList([]const u8).initCapacity(allocator, 4);

            var path = try std.ArrayList(u8).initCapacity(allocator, 4);
            defer path.deinit();

            for (cheapest_routes) |cheapest| {
                path.clearRetainingCapacity();
                var current: ?*VisitDetails = cheapest;
                while (current != null) {
                    try path.append(current.?.pos_and_direction.direction.toButton());
                    if (current.?.from.items.len > 0) {
                        current = current.?.from.items[0];
                    } else {
                        current = null;
                    }
                }
                //drop the first direction this will be the direction on the initial button
                path.items.len = path.items.len - 1;
                const this_path_buttons = try allocator.dupe(u8, path.items);
                std.mem.reverse(u8, this_path_buttons);
                try combinations.append(this_path_buttons);
            }
            //Order the combinations by the left before up before down before right
            std.mem.sort([]const u8, combinations.items, {}, leftBeforeUpBeforeDownBeforeRight);
            try combs.put(button_comb, combinations.swapRemove(0));
        }
    }
}

const CombAndLevel = struct {
    comb: ButtonComb,
    level: usize,
};

const back_to_a = &[_]u8{'A'};

fn calculatePresses(
    cached_presses: *std.AutoHashMap(CombAndLevel, u128),
    code: []const u8,
    button_combs: []*const std.AutoHashMap(ButtonComb, []const u8),
    start_button: u8,
) !u128 {
    var presses: u128 = 0;
    //work through all the required presses for the code - this applies to the first button combs
    const this_keypad = button_combs[0];
    var current_button = start_button;
    for (code) |button| {
        //if it's the same button nothing to do but press it
        if (button == current_button) {
            presses += 1;
            continue;
        }
        //move to the next button
        const button_comb = ButtonComb{
            .start_button = current_button,
            .end_button = button,
        };
        current_button = button; //can set current now

        //get the cached value if it exists
        const comb_and_level = CombAndLevel{
            .comb = button_comb,
            .level = button_combs.len,
        };
        const cached = cached_presses.get(comb_and_level);
        if (cached) |num_presses| {
            presses += num_presses;
            continue;
        }

        const combinations = this_keypad.get(button_comb).?;

        var this_presses: u128 = 0;

        if (button_combs.len == 1) {
            this_presses += combinations.len; //navigate to it
            this_presses += 1; //press 'A'
        } else {
            //work out the presses for the robot - note in order to press we need to go to the button and then back to 'A' each time
            this_presses += try calculatePresses(cached_presses, combinations, button_combs[1..], 'A');
            this_presses += try calculatePresses(cached_presses, back_to_a, button_combs[1..], combinations[combinations.len - 1]);
        }

        //cache the result
        try cached_presses.put(comb_and_level, this_presses);

        presses += this_presses;
    }

    return presses;
}

fn calculate(
    allocator: std.mem.Allocator,
    context: *const Context,
    keypad_button_combs: *std.AutoHashMap(ButtonComb, []const u8),
    robot_button_combs: *std.AutoHashMap(ButtonComb, []const u8),
    num_robots: usize,
) !u128 {
    var string = try std.ArrayList(u8).initCapacity(allocator, 5);
    defer string.deinit();

    var cached_presses = std.AutoHashMap(CombAndLevel, u128).init(allocator);
    defer cached_presses.deinit();

    var button_combs = try std.ArrayList(*std.AutoHashMap(ButtonComb, []const u8)).initCapacity(
        allocator,
        num_robots + 1,
    );
    defer button_combs.deinit();
    try button_combs.append(keypad_button_combs);
    try button_combs.appendNTimes(robot_button_combs, num_robots);

    var sum: u128 = 0;
    for (context.codes.items) |code| {
        const presses = try calculatePresses(&cached_presses, code, button_combs.items, 'A');

        //get the number, remove the trailing 'A'
        string.clearRetainingCapacity();
        try string.writer().writeAll(code[0 .. code.len - 1]);
        const numeric_code = try std.fmt.parseInt(u128, string.items, 10);
        sum += presses * numeric_code;
    }
    return sum;
}
