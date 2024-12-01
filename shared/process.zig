const std = @import("std");
const fs = std.fs;

pub fn parse_file(
    comptime CONTEXT: type,
    comptime LINE_TYPE: type,
    comptime line_parser: fn (std.mem.Allocator, CONTEXT, []const u8) anyerror!LINE_TYPE,
    allocator: std.mem.Allocator,
    context: CONTEXT,
    file_name: []const u8,
) !std.ArrayList(LINE_TYPE) {
    //load the file, line by line
    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();

    var collector = std.ArrayList(LINE_TYPE).init(allocator);

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    const stdout = std.io.getStdOut();
    const writer = line.writer();
    var line_no: usize = 0;
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        const parsed: LINE_TYPE = try line_parser(allocator, context, line.items);
        try collector.append(parsed);
        line_no += 1;
    } else |err| switch (err) {
        error.EndOfStream => {
            if (line.items.len > 0) {
                const parsed: LINE_TYPE = try line_parser(allocator, context, line.items);
                try collector.append(parsed);
                line_no += 1;
            }
        },
        else => return err, //propagate it
    }

    try stdout.writer().print("Parsed {d} lines\n", .{line_no});

    return collector;
}

pub const Next = struct {
    new_start: usize,
    next: std.ArrayList(u8),
};

pub fn read_next(
    allocator: std.mem.Allocator,
    start: usize,
    line: []const u8,
    delimiters: std.AutoHashMap(u8, bool),
) !Next {
    var next = std.ArrayList(u8).init(allocator);

    var found_delimiter = false;
    var pos = start;
    while (pos < line.len) : (pos += 1) {
        const char = line[pos];
        if (delimiters.contains(char)) {
            found_delimiter = true;
            continue;
        }
        if (found_delimiter) {
            break;
        }
        try next.append(char);
    }
    return .{
        .new_start = pos,
        .next = next,
    };
}
