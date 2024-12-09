const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {};

const Line = struct {
    line: []const u8,
};

pub fn main() !void {
    const day = "day9";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var context = Context{};

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    // const stdout = std.io.getStdOut();
    // for (context.grid.items) |row| {
    //     try stdout.writeAll(row.items);
    //     try stdout.writeAll("\n");
    // }
    // try stdout.writer().print("width: {d}, height: {d}\n", .{ context.width, context.height });

    try calculate(arena_allocator.allocator(), parsed_lines.items[0].line);
    try calculate_2(arena_allocator.allocator(), parsed_lines.items[0].line);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = context;
    var parsed_line = try std.ArrayList(u8).initCapacity(allocator, line.len);
    var chars: [1]u8 = undefined;

    for (line) |char| {
        chars[0] = char;
        const number = try std.fmt.parseInt(u8, &chars, 10);
        try parsed_line.append(number);
    }

    return .{
        .line = parsed_line.items,
    };
}

const Area = struct {
    const Self = @This();

    free_space: bool,
    capacity: usize,
    blocks: *std.ArrayList(usize),

    fn init(allocator: std.mem.Allocator, free_space: bool, capacity: usize) !Self {
        const blocks: *std.ArrayList(usize) = try allocator.create(std.ArrayList(usize));
        blocks.* = try std.ArrayList(usize).initCapacity(allocator, capacity);
        return .{
            .free_space = free_space,
            .capacity = capacity,
            .blocks = blocks,
        };
    }

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.blocks.deinit();
        allocator.destroy(self.blocks);
    }

    fn add(self: *Self, data: usize) !void {
        if (self.blocks.items.len >= self.capacity) {
            return error.AreaAtCapacity;
        }
        try self.blocks.append(data);
    }

    fn print(self: Self, writer: anytype) !void {
        try writer.print("{d}: ", .{self.capacity});
        for (self.blocks.items) |block| {
            try writer.print("{d} ", .{block});
        }
    }
};

const DiskMap = struct {
    const Self = @This();

    areas: std.ArrayList(Area),

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.areas.items) |*area| {
            area.deinit(allocator);
        }
        self.areas.deinit();
    }

    fn print(self: Self, writer: anytype) !void {
        for (self.areas.items, 0..) |area, index| {
            try writer.print("{d} => ", .{index});
            try area.print(writer);
            try writer.writeAll("\n");
        }
    }
};

fn constructDiskMap(allocator: std.mem.Allocator, line: []const u8) !DiskMap {
    var areas = try std.ArrayList(Area).initCapacity(allocator, line.len);

    var i: usize = 0;
    var current_id: usize = 0;

    while (i < line.len) : (i += 1) {
        //space or file
        const is_file = i % 2 == 0;

        const length = line[i];
        var new_area = try Area.init(allocator, !is_file, length);

        if (is_file) {
            for (0..length) |_| {
                try new_area.add(current_id);
            }
            current_id += 1;
        }
        try areas.append(new_area);
    }

    return .{
        .areas = areas,
    };
}

fn pack(disk_map: *DiskMap) !void {
    var front: usize = 0;
    var back: usize = disk_map.areas.items.len - 1;

    //move file_ids from the back to the front
    while (front < back) {
        //find next space at the front
        var front_area = disk_map.areas.items[front];
        while (!(front_area.blocks.items.len < front_area.capacity)) {
            front += 1;
            front_area = disk_map.areas.items[front];
        }
        //find next populated at the back
        var back_area = disk_map.areas.items[back];
        while (back_area.blocks.items.len == 0) {
            back -= 1;
            back_area = disk_map.areas.items[back];
        }
        //did we meet?
        if (front >= back) {
            break;
        }
        //move the last one and append to the front.
        const file_id = back_area.blocks.pop();
        try front_area.add(file_id);
    }
}

fn calculate(allocator: std.mem.Allocator, line: []const u8) !void {
    var disk_map = try constructDiskMap(allocator, line);
    defer disk_map.deinit(allocator);

    try pack(&disk_map);

    var sum: u128 = 0;
    var overall_pos: usize = 0;
    for (disk_map.areas.items) |area| {
        if (area.blocks.capacity > 0 and area.blocks.items.len == 0) {
            break;
        }
        for (area.blocks.items) |file_id| {
            const contribution = @as(u128, @intCast(overall_pos)) * @as(u128, @intCast(file_id));
            sum += contribution;
            overall_pos += 1;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn pack2(disk_map: *DiskMap) !void {
    var back: usize = disk_map.areas.items.len - 1;
    var non_full_index: usize = 1; //index into the first free space we haven't filled yet

    //move file_ids from the back to the front - in blocks where we can find space
    while (back > 0) {
        //find next populated at the back
        var back_area = disk_map.areas.items[back];
        //find next bit of space we can fit this into
        const required_capacity = back_area.blocks.items.len;
        var search_index: usize = non_full_index;
        var space_to_fill_index: ?usize = null;
        while (search_index < back) {
            const area = disk_map.areas.items[search_index];
            const remaining_capacity = area.capacity - area.blocks.items.len;
            if (remaining_capacity >= required_capacity) {
                space_to_fill_index = search_index;
                break;
            } else {
                //look in next space
                search_index += 2;
            }
        }
        // if we didn't find anything move on to the next one
        if (space_to_fill_index == null) {
            if (back > 1) {
                back -= 2;
            }
            continue;
        }
        // found something, move it
        var space_to_fill = disk_map.areas.items[space_to_fill_index.?];
        for (back_area.blocks.items) |block| {
            try space_to_fill.add(block);
        }
        back_area.blocks.clearRetainingCapacity();
        back -= 2;
        // if we have just filled the one we searched from...  move the non_full_index
        const searching_from_area = disk_map.areas.items[non_full_index];
        if (searching_from_area.blocks.items.len == searching_from_area.capacity) {
            non_full_index += 2;
        }
    }
}

fn calculate_2(allocator: std.mem.Allocator, line: []const u8) !void {
    var disk_map = try constructDiskMap(allocator, line);
    defer disk_map.deinit(allocator);

    try pack2(&disk_map);

    var sum: u128 = 0;
    var overall_pos: usize = 0;
    for (disk_map.areas.items) |area| {
        for (0..area.capacity) |i| {
            if (i < area.blocks.items.len) {
                const file_id = area.blocks.items[i];
                const contribution = @as(u128, @intCast(overall_pos)) * @as(u128, @intCast(file_id));
                sum += contribution;
            }
            overall_pos += 1;
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
