const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
};

const Line = struct {
    levels: std.ArrayList(i32),

    fn print(self: Line, writer: anytype) !void {
        for (self.levels.items) |level| {
            try writer.print("{d} ", .{level});
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);

    //const file_name = "day2/test_file.txt";
    //const file_name = "day2/test_cases.txt";
    const file_name = "day2/input.txt";

    const parsed_lines = try process.FileParser(Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        .{ .delimiters = delimiters },
        file_name,
    );
    defer parsed_lines.deinit();

    // const stdout = std.io.getStdOut();
    // for (parsed_lines.items) |data| {
    //     try data.print(stdout.writer());
    //     try stdout.writeAll("\n");
    // }

    try calculate(arena_allocator.allocator(), parsed_lines);
    try calculate_2(arena_allocator.allocator(), parsed_lines);
}

fn parse_line(allocator: std.mem.Allocator, context: Context, line: []const u8) !Line {
    var parser = process.LineParser().init(allocator, context.delimiters, line);

    var levels = std.ArrayList(i32).init(allocator);

    //read all of the integers
    while (parser.has_more()) {
        const next_int = try parser.read_int(i32, 10);
        try levels.append(next_int);
    }

    return .{ .levels = levels };
}

fn is_safe(a: i32, b: i32, is_increasing: ?bool) bool {
    const diff = b - a;
    //All must be increasing or decreasing by 1 or 2 or increasing by 1 or 2
    const this_increasing = diff > 0;
    if (is_increasing) |previous_increasing| {
        if (previous_increasing != this_increasing) {
            //Not safe
            return false;
        }
    }
    //Unsafe if the levels increase/decrease by more than 3
    const abs_diff = @abs(diff);
    if (abs_diff == 0 or abs_diff > 3) {
        //Not safe
        return false;
    }
    return true;
}

fn line_is_safe(line_levels: std.ArrayList(i32)) bool {
    const levels = line_levels.items;

    if (levels.len < 2) {
        @panic("level had < 2 items");
    }

    var is_increasing: ?bool = null;
    var pos: usize = 0;
    while (pos < levels.len - 1) : (pos += 1) {
        const a = levels[pos];
        const b = levels[pos + 1];
        if (!is_safe(a, b, is_increasing)) {
            return false;
        }
        //If we get here, this jump was safe
        is_increasing = (b - a) > 0;
    }
    return true;
}

fn calculate(allocator: std.mem.Allocator, lines: std.ArrayList(Line)) !void {
    const folder = iteration.Fold(Line, i32).init(allocator);
    const check_safety = struct {
        fn check_safety(
            alloc: std.mem.Allocator,
            num_safe: i32,
            line: Line,
        ) !i32 {
            _ = alloc;
            if (line_is_safe(line.levels)) {
                return num_safe + 1;
            }
            return num_safe;
        }
    }.check_safety;
    const num_safe = try folder.fold(0, lines.items, check_safety);

    try std.io.getStdOut().writer().print("Total Safe is {d}\n", .{num_safe});
}

fn calculate_2(allocator: std.mem.Allocator, lines: std.ArrayList(Line)) !void {
    const folder = iteration.Fold(Line, i32).init(allocator);
    const check_safety = struct {
        fn check_safety(
            alloc: std.mem.Allocator,
            num_safe: i32,
            line: Line,
        ) !i32 {
            _ = alloc;
            //Try the full line without removing anything
            if (line_is_safe(line.levels)) {
                return num_safe + 1;
            }
            //try removing each item and re-checking
            var i: usize = 0;
            while (i < line.levels.items.len) : (i += 1) {
                var levels_copy = try line.levels.clone();
                _ = levels_copy.orderedRemove(i);
                if (line_is_safe(levels_copy)) {
                    return num_safe + 1;
                }
            }
            return num_safe;
        }
    }.check_safety;
    const num_safe = try folder.fold(0, lines.items, check_safety);

    try std.io.getStdOut().writer().print("Total Safe Part 2 is {d}\n", .{num_safe});
}
