const std = @import("std");
const fs = std.fs;

pub fn FileParser(
    comptime CONTEXT: type,
    comptime LINE_TYPE: type,
    comptime line_parser: fn (std.mem.Allocator, CONTEXT, []const u8) anyerror!LINE_TYPE,
) type {
    return struct {
        const Self = @This();
        pub fn parse(
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
    };
}

pub fn LineParser() type {
    return struct {
        const Self = @This();

        const Next = struct {
            new_start: usize,
            next: std.ArrayList(u8),
        };

        allocator: std.mem.Allocator,
        delimiters: std.AutoHashMap(u8, bool),
        line: []const u8,
        pos: usize,

        pub fn init(allocator: std.mem.Allocator, delimiters: std.AutoHashMap(u8, bool), line: []const u8) Self {
            return Self{
                .allocator = allocator,
                .delimiters = delimiters,
                .line = line,
                .pos = 0,
            };
        }

        /// Reads the next set of chars up to any found delimiter (or end of line)
        fn read_next(self: *Self) !std.ArrayList(u8) {
            var next = std.ArrayList(u8).init(self.allocator);

            var found_delimiter = false;
            while (self.pos < self.line.len) : (self.pos += 1) {
                const char = self.line[self.pos];
                if (self.delimiters.contains(char)) {
                    found_delimiter = true;
                    continue;
                }
                if (found_delimiter) {
                    break;
                }
                try next.append(char);
            }

            return next;
        }

        /// Reads the next int
        pub fn read_int(self: *Self, comptime T: type, base: u8) !T {
            const next = try self.read_next();
            defer next.deinit();
            return try std.fmt.parseInt(T, next.items, base);
        }

        /// Reads the next float
        pub fn read_float(self: *Self, comptime T: type) !T {
            const next = try self.read_next();
            defer next.deinit();
            return try std.fmt.parseFloat(T, next.items);
        }

        /// Reads the next string
        /// Remember to free the returned string using the LineParser's allocator
        pub fn read_string(self: *Self) ![]u8 {
            var next = try self.read_next();
            defer next.deinit();
            return next.toOwnedSlice();
        }

        pub fn has_more(self: Self) bool {
            return self.pos < self.line.len;
        }
    };
}

const expect = std.testing.expect;
const eql = std.mem.eql;

test "LineParser test 1" {
    var delims = std.AutoHashMap(u8, bool).init(std.testing.allocator);
    try delims.put(' ', true);
    defer delims.deinit();

    var parser = LineParser().init(std.testing.allocator, delims, "2 5.6 bob 5");

    try expect(parser.has_more());
    const val1 = try parser.read_int(i32, 10);
    try expect(val1 == 2);
    try expect(parser.has_more());
    const val2 = try parser.read_float(f32);
    try expect(val2 == 5.6);
    try expect(parser.has_more());
    const val3 = try parser.read_string();
    defer std.testing.allocator.free(val3);
    try expect(parser.has_more());
    try expect(eql(u8, val3, "bob"));
    const val4 = try parser.read_int(u32, 10);
    try expect(val4 == 5);
    try expect(!parser.has_more());
}
