const std = @import("std");
const process = @import("shared").process;

const Context = struct { delimiters: std.AutoHashMap(u8, bool) };

const Data = struct {
    x: usize,
    y: f64,
    z: []const u8,

    fn print(self: Data, writer: anytype) !void {
        try writer.print("x={d}, y={d}, z={s}", self);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(' ', true);

    const parsed_lines = try process.parse_file(
        Context,
        Data,
        parse_line,
        arena_allocator.allocator(),
        .{ .delimiters = delimiters },
        "testing2/test_file.txt",
    );
    defer parsed_lines.deinit();

    const stdout = std.io.getStdOut();
    for (parsed_lines.items) |data| {
        try data.print(stdout.writer());
        try stdout.writeAll("\n");
    }
}

fn parse_line(allocator: std.mem.Allocator, context: Context, line: []const u8) !Data {
    const next_x = try process.read_next(allocator, 0, line, context.delimiters);
    defer next_x.next.deinit();
    const x = try std.fmt.parseInt(usize, next_x.next.items, 10);

    const next_y = try process.read_next(allocator, next_x.new_start, line, context.delimiters);
    defer next_y.next.deinit();
    const y = try std.fmt.parseFloat(f64, next_y.next.items);

    const next_z = try process.read_next(allocator, next_y.new_start, line, context.delimiters);
    defer next_z.next.deinit();
    const z = try allocator.dupe(u8, next_z.next.items);

    return .{
        .x = x,
        .y = y,
        .z = z,
    };
}
