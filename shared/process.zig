const std = @import("std");
const fs = std.fs;
const utils = @import("utils.zig");

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
        found_delimiters: std.ArrayList(u8),
        pos: usize = 0,

        pub fn init(
            allocator: std.mem.Allocator,
            delimiters: std.AutoHashMap(u8, bool),
            line: []const u8,
        ) Self {
            return Self{
                .allocator = allocator,
                .delimiters = delimiters,
                .line = line,
                .found_delimiters = std.ArrayList(u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.found_delimiters.deinit();
        }

        /// Reads the next set of chars up to any found delimiters putting the found delimiters into
        /// .found_delimiters
        fn read_next(self: *Self) !std.ArrayList(u8) {
            self.found_delimiters.clearRetainingCapacity();

            var next = std.ArrayList(u8).init(self.allocator);

            var found_delimiter = false;
            while (self.pos < self.line.len) : (self.pos += 1) {
                const char = self.line[self.pos];
                if (self.delimiters.contains(char)) {
                    try self.found_delimiters.append(char);
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

        /// Reads the next set of chars that are digits
        /// Remeber to deinit the returned array list
        pub fn read_next_int_chars(self: *Self) !std.ArrayList(u8) {
            var chars = std.ArrayList(u8).init(self.allocator);

            while (self.has_more()) {
                const next = self.peek_char();
                if (next == null) {
                    break;
                }
                if (!utils.is_digit(next.?)) {
                    break;
                }
                try chars.append(next.?);
                _ = self.read_char();
            }

            return chars;
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

        /// Reads the next u8 'char'
        pub fn read_char(self: *Self) ?u8 {
            self.found_delimiters.clearRetainingCapacity();

            if (!(self.pos < self.line.len)) {
                return null;
            }
            const next_char = self.line[self.pos];
            self.pos += 1;
            return next_char;
        }

        pub fn peek_char(self: *Self) ?u8 {
            if (!(self.pos < self.line.len)) {
                return null;
            }
            return self.line[self.pos];
        }

        //Peek the next few chars, or null if there aren't that many to go
        //Remember to free the returned ArrayList
        pub fn peek_chars(self: *Self, num: usize) !?std.ArrayList(u8) {
            if (!(self.line.len > self.pos + num - 1)) { //Not enough left
                return null;
            }

            var peek = try std.ArrayList(u8).initCapacity(self.allocator, num);

            //TODO can this be copied using a method on array list?
            for (0..num) |i| {
                const char = self.line[self.pos + i];
                try peek.append(char);
            }

            return peek;
        }

        pub fn has_more(self: Self) bool {
            return self.pos < self.line.len;
        }

        pub fn first_delimiter(self: Self) ?u8 {
            if (self.found_delimiters.items.len == 0) {
                return null;
            }
            return self.found_delimiters.items[0];
        }

        pub fn last_delimiter(self: Self) ?u8 {
            if (self.found_delimiters.items.len == 0) {
                return null;
            }
            return self.found_delimiters.items[self.found_delimiters.items.len - 1];
        }
    };
}

const expect = std.testing.expect;
const eql = std.mem.eql;

test "LineParser test 1" {
    var delims = std.AutoHashMap(u8, bool).init(std.testing.allocator);
    try delims.put(' ', true);
    try delims.put(',', true);
    defer delims.deinit();

    var parser = LineParser().init(std.testing.allocator, delims, "2 5.6,bob ,5 a");
    defer parser.deinit();

    try expect(parser.has_more());
    const val1 = try parser.read_int(i32, 10);
    try expect(val1 == 2);
    try expect(eql(u8, parser.found_delimiters.items, " "));
    try expect(parser.first_delimiter() == ' ');
    try expect(parser.last_delimiter() == ' ');
    try expect(parser.has_more());
    const val2 = try parser.read_float(f32);
    try expect(val2 == 5.6);
    try expect(eql(u8, parser.found_delimiters.items, ","));
    try expect(parser.first_delimiter() == ',');
    try expect(parser.last_delimiter() == ',');
    try expect(parser.has_more());
    const val3 = try parser.read_string();
    defer std.testing.allocator.free(val3);
    try expect(parser.has_more());
    try expect(eql(u8, val3, "bob"));
    try expect(eql(u8, parser.found_delimiters.items, " ,"));
    try expect(parser.first_delimiter() == ' ');
    try expect(parser.last_delimiter() == ',');
    const val4 = try parser.read_int(u32, 10);
    try expect(val4 == 5);
    try expect(parser.has_more());
    try expect(parser.read_char() == 'a');
    try expect(eql(u8, parser.found_delimiters.items, ""));
    try expect(parser.first_delimiter() == null);
    try expect(parser.last_delimiter() == null);
    try expect(parser.read_char() == null);
    try expect(!parser.has_more());
}

test "peek chars" {
    var delims = std.AutoHashMap(u8, bool).init(std.testing.allocator);
    try delims.put(' ', true);
    try delims.put(',', true);
    defer delims.deinit();

    var parser = LineParser().init(std.testing.allocator, delims, "abcd");
    defer parser.deinit();

    const peek1 = (try parser.peek_chars(1)).?;
    defer peek1.deinit();
    try expect(eql(u8, peek1.items, "a"));

    const peek2 = (try parser.peek_chars(2)).?;
    defer peek2.deinit();
    try expect(eql(u8, peek2.items, "ab"));

    const peek3 = (try parser.peek_chars(3)).?;
    defer peek3.deinit();
    try expect(eql(u8, peek3.items, "abc"));

    const peek4 = (try parser.peek_chars(4)).?;
    defer peek4.deinit();
    try expect(eql(u8, peek4.items, "abcd"));

    const peek5 = try parser.peek_chars(5);
    try expect(peek5 == null);

    _ = parser.read_char();
    const peek6 = (try parser.peek_chars(3)).?;
    defer peek6.deinit();
    try expect(eql(u8, peek6.items, "bcd"));

    const peek7 = try parser.peek_chars(4);
    try expect(peek7 == null);
}
