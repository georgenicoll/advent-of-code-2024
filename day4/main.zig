const std = @import("std");
const shared = @import("shared");
const aoc = shared.aoc;
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    const Self = @This();

    delimiters: std.AutoHashMap(u8, bool),
    grid: aoc.Grid(u8),
};

const Line = struct {};

pub fn main() !void {
    //const file_name = "day4/test_file.txt";
    //const file_name = "day4/test_cases.txt";
    const file_name = "day4/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);

    var grid = aoc.Grid(u8).init(arena_allocator.allocator());
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
    // try context.grid.print(stdout.writer(), "{d},");

    //Playing with the amount of memory needed - the minimum is 10 bytes (1 + 2 + 3 + 4) for the required array lists
    const allocator_buffer = try gpa.allocator().alloc(u8, 10);
    defer gpa.allocator().free(allocator_buffer);
    var fba = std.heap.FixedBufferAllocator.init(allocator_buffer);
    try calculate(fba.allocator(), context);

    try calculate_2(arena_allocator.allocator(), context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;
    try context.grid.addRow(line);
    return .{};
}

fn search(
    allocator: std.mem.Allocator,
    grid: aoc.Grid(u8),
    to_find: []const u8,
    found_so_far: std.ArrayList(u8),
    current_i: isize,
    current_j: isize,
    direction_i: isize,
    direction_j: isize,
) !usize {
    //try to get the next char
    const next = grid.itemAt(current_i + direction_i, current_j + direction_j);
    if (next == null) {
        return 0; //can't get any more
    }

    var new_found_so_far = try std.ArrayList(u8).initCapacity(allocator, found_so_far.items.len + 1);
    defer new_found_so_far.deinit();

    try new_found_so_far.appendSlice(found_so_far.items);
    try new_found_so_far.append(next.?);

    //got the full string?
    //strings are same length - do our final check
    if (new_found_so_far.items.len >= to_find.len) {
        if (eql(u8, new_found_so_far.items, to_find)) {
            return 1;
        }
        return 0;
    }

    //Not a full string - keep going in the same direction
    return try search(allocator, grid, to_find, new_found_so_far, current_i + direction_i, current_j + direction_j, direction_i, direction_j);
}

fn calculate(allocator: std.mem.Allocator, context: Context) !void {
    const grid = context.grid;

    var sum: usize = 0;

    //Go to each point in the grid and search in a straight line to see if we have the word XMAS
    for (0..grid.height) |j_u| {
        const j = @as(isize, @intCast(j_u));
        for (0..grid.width) |i_u| {
            const i = @as(isize, @intCast(i_u));
            const start_char = grid.itemAt(i, j);
            if (start_char != 'X') {
                continue;
            }

            var found_so_far = try std.ArrayList(u8).initCapacity(allocator, 1);
            defer found_so_far.deinit();
            try found_so_far.append(start_char.?);

            sum += try search(allocator, grid, "XMAS", found_so_far, i, j, 0, -1); //N
            sum += try search(allocator, grid, "XMAS", found_so_far, i, j, 1, -1); //NE
            sum += try search(allocator, grid, "XMAS", found_so_far, i, j, 1, 0); //E
            sum += try search(allocator, grid, "XMAS", found_so_far, i, j, 1, 1); //SE
            sum += try search(allocator, grid, "XMAS", found_so_far, i, j, 0, 1); //S
            sum += try search(allocator, grid, "XMAS", found_so_far, i, j, -1, 1); //SW
            sum += try search(allocator, grid, "XMAS", found_so_far, i, j, -1, 0); //W
            sum += try search(allocator, grid, "XMAS", found_so_far, i, j, -1, -1); //NW
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

fn calculate_2(allocator: std.mem.Allocator, context: Context) !void {
    _ = allocator;
    const grid = context.grid;

    var sum: usize = 0;

    //Go to each point in the grid and search for the X
    for (0..grid.height) |j_u| {
        const j = @as(isize, @intCast(j_u));
        for (0..grid.width) |i_u| {
            const i = @as(isize, @intCast(i_u));
            const start_char = grid.itemAt(i, j);
            if (start_char != 'A') {
                continue;
            }

            //need diagonal MAS or SAM in both diagonal directions - these are independent of each other
            const nw = grid.itemAt(i - 1, j - 1);
            const se = grid.itemAt(i + 1, j + 1);
            const ne = grid.itemAt(i + 1, j - 1);
            const sw = grid.itemAt(i - 1, j + 1);

            const nw_to_se_diagonal_ok = (nw == 'M' and se == 'S') or (nw == 'S' and se == 'M');
            const ne_to_sw_diagonal_ok = (ne == 'M' and sw == 'S') or (ne == 'S' and sw == 'M');

            if (nw_to_se_diagonal_ok and ne_to_sw_diagonal_ok) {
                sum += 1;
            }
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}
