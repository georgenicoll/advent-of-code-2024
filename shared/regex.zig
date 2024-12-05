//Adapted from https://cookbook.ziglang.cc/15-01-regex.html
const std = @import("std");
const print = std.debug.print;
const c = @cImport({
    @cInclude("regex.h");
    @cInclude("regex_slim.h");
});

const Matches = struct {
    const Self = @This();

    matches: *std.ArrayList(*std.ArrayList(u8)),

    fn init(allocator: std.mem.Allocator) !Self {
        const matches = try allocator.create(std.ArrayList(*std.ArrayList(u8)));
        matches.* = std.ArrayList(*std.ArrayList(u8)).init(allocator);
        return .{
            .matches = matches,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.matches.items) |match| {
            match.deinit();
        }
        self.matches.deinit();
    }

    fn appendMatch(self: *Self, allocator: std.mem.Allocator, match: []const u8) !void {
        const map: *std.ArrayList(u8) = try allocator.create(std.ArrayList(u8));
        map.* = std.ArrayList(u8).init(allocator);
        try map.*.appendSlice(match);
        try self.matches.append(map);
    }
};

const Regex = struct {
    inner: *c.regex_t,

    fn init(pattern: [:0]const u8) !Regex {
        const inner = c.alloc_regex_t().?;
        if (0 != c.regcomp(inner, pattern, c.REG_NEWLINE | c.REG_EXTENDED)) {
            return error.compile;
        }

        return .{
            .inner = inner,
        };
    }

    fn deinit(self: Regex) void {
        c.free_regex_t(self.inner);
    }

    fn matches(self: Regex, input: [:0]const u8) bool {
        const match_size = 1;
        var pmatch: [match_size]c.regmatch_t = undefined;
        return 0 == c.regexec(self.inner, input, match_size, &pmatch, 0);
    }

    /// Execute the regex against the input string.
    /// Returns an array list containing array lists for each match - all should be cleaned up
    fn exec(self: Regex, allocator: std.mem.Allocator, input: [:0]const u8) !Matches {
        const match_size = 1;
        var pmatch: [match_size]c.regmatch_t = undefined;

        var re_matches = try Matches.init(allocator);
        var string = input;

        while (true) {
            if (0 != c.regexec(self.inner, string, match_size, &pmatch, 0)) {
                break;
            }

            const slice = string[@as(usize, @intCast(pmatch[0].rm_so))..@as(usize, @intCast(pmatch[0].rm_eo))];
            try re_matches.appendMatch(allocator, slice);

            string = string[@intCast(pmatch[0].rm_eo)..];
        }

        return re_matches;
    }
};

const expect = std.testing.expect;
const eql = std.mem.eql;
const testing_alloc = std.testing.allocator;

test "matches simple" {
    const regex1 = try Regex.init("nice");
    defer regex1.deinit();

    try expect(regex1.matches("this should match nice!"));
}

test "exec simple" {
    const regex1 = try Regex.init("nice");
    defer regex1.deinit();

    const result = try regex1.exec(testing_alloc, "this should nice match nice");
    try expect(result.matches.items.len == 2);
    try expect(eql(u8, result.matches.items[0].items, "nice"));
    try expect(eql(u8, result.matches.items[1].items, "nice"));
}

test "matches" {
    const regex1 = try Regex.init(".*mul\\([:digit:]*,[:digit:]\\).*");
    defer regex1.deinit();

    try expect(regex1.matches("do()something((mul(123,456)))))()"));
    try expect(!regex1.matches("do()something((mu(123,456)))))()"));
}
