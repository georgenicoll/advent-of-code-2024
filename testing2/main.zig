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

    const parsed_lines = try process.FileParser(Context, Data, parse_line).parse(
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
    var parser = process.LineParser().init(allocator, context.delimiters, line);

    const x = try parser.read_int(usize, 10);
    const y = try parser.read_float(f64);
    const z = try parser.read_string();

    return .{
        .x = x,
        .y = y,
        .z = z,
    };
}
