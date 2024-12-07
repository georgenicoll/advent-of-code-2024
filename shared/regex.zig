//Adapted from https://cookbook.ziglang.cc/15-01-regex.html
const std = @import("std");
const print = std.debug.print;
const c = @cImport({
    @cInclude("regex.h");
    @cInclude("regex_slim.h");
});

const Match = struct {
    const Self = @This();

    full_match: []const u8,
    groups: std.ArrayList([]const u8),

    fn deinit(self: Self) void {
        self.groups.deinit();
    }
};

const Matches = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    matches: std.ArrayList(*Match),

    fn init(allocator: std.mem.Allocator) !Self {
        const matches = std.ArrayList(*Match).init(allocator);
        return .{
            .allocator = allocator,
            .matches = matches,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.matches.items) |match| {
            match.*.deinit(); //free up the stuff contained by the ArrayList
            self.allocator.destroy(match); //now free up the ArrayList on the heap itself
        }
        self.matches.deinit();
    }

    fn appendMatch(self: *Self, full_match: []const u8) !void {
        const match: *Match = try self.allocator.create(Match);
        match.* = Match{
            .full_match = try self.allocator.dupe(u8, full_match),
            .groups = std.ArrayList([]const u8).init(self.allocator),
        };
        try self.matches.append(match);
    }
};

const RegexTStart = struct {
    buffer: c_uint, //pointer
    allocated: c_ulong,
    used: c_ulong,
    syntax: c_ulong,
    fastmap: usize, //pointer
    translate: usize, //pointer
    re_nsub: usize,
};

const Regex = struct {
    const Self = @This();

    inner: *c.regex_t,
    regext_start: *RegexTStart,

    fn init(pattern: [:0]const u8) !Self {
        const inner = c.alloc_regex_t().?;
        if (0 != c.regcomp(inner, pattern, c.REG_NEWLINE | c.REG_EXTENDED)) {
            return error.compile;
        }
        return .{
            .inner = inner,
            .regext_start = @ptrCast(@alignCast(inner)),
        };
    }

    fn deinit(self: Self) void {
        c.free_regex_t(self.inner);
    }

    pub fn numSubExpressions(self: Self) usize {
        return self.regext_start.re_nsub;
    }

    pub fn matches(self: Self, input: [:0]const u8) bool {
        const match_size = 1;
        var pmatch: [match_size]c.regmatch_t = undefined;
        return 0 == c.regexec(self.inner, input, match_size, &pmatch, 0);
    }

    /// Execute the regex against the input string.
    /// Returns an array list containing array lists for each match - all should be cleaned up
    pub fn exec(self: Self, allocator: std.mem.Allocator, input: [:0]const u8) !Matches {
        const match_size = 1;
        var pmatch: [match_size]c.regmatch_t = undefined;

        var re_matches = try Matches.init(allocator);
        var string = input;

        while (true) {
            if (0 != c.regexec(self.inner, string, match_size, &pmatch, 0)) {
                break;
            }

            const start_match = @as(usize, @intCast(pmatch[0].rm_so));
            const end_match = @as(usize, @intCast(pmatch[0].rm_eo));

            if (start_match == end_match) {
                break;
            }

            const slice = string[start_match..end_match];
            try re_matches.appendMatch(slice);

            string = string[end_match..];
        }

        return re_matches;
    }
};

const expect = std.testing.expect;
const eql = std.mem.eql;
const testing_alloc = std.testing.allocator;

test "matches simple" {
    const regex = try Regex.init("nice");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 0);
    try expect(regex.matches("this should match nice!"));
}

test "exec simple" {
    const regex = try Regex.init("nice");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 0);

    const result = try regex.exec(testing_alloc, "this should nice match nice");
    defer result.deinit();
    try expect(result.matches.items.len == 2);
    try expect(eql(u8, result.matches.items[0].items, "nice"));
    try expect(eql(u8, result.matches.items[1].items, "nice"));
}

test "exec match :digit:" {
    const regex = try Regex.init("[[:digit:]]+");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 0);

    const result = try regex.exec(testing_alloc, "bob 123 rita 456 sue: 85");
    defer result.deinit();
    try expect(result.matches.items.len == 3);
    try expect(eql(u8, result.matches.items[0].items, "123"));
    try expect(eql(u8, result.matches.items[1].items, "456"));
    try expect(eql(u8, result.matches.items[2].items, "85"));
}

test "matches" {
    const regex = try Regex.init("mul\\([[:digit:]]+,[[:digit:]]+\\)");
    defer regex.deinit();

    try expect(regex.matches("do()something((mul(123,456)))))()"));
    try expect(!regex.matches("do()something((mu(123,456)))))()"));
}

test "sub_expressions" {
    const regex = try Regex.init("mul\\(([[:digit:]]+),([[:digit:]]+)\\))");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 2);

    const result = try regex.exec(testing_alloc, "hello please mul(12,3) and also mul(3,44), kthnxbye");
    defer result.deinit();

    try expect(result.matches.items.len == 2);
    try expect(eql(u8, result.matches.items[0].full_match, "mul(12,3)"));
    try expect(eql(u8, result.matches.items[0].groups.items[0], "12"));
    try expect(eql(u8, result.matches.items[0].groups.items[1], "3"));
    try expect(eql(u8, result.matches.items[1].full_match, "mul(3,4)"));
    try expect(eql(u8, result.matches.items[1].groups.items[0], "3"));
    try expect(eql(u8, result.matches.items[1].groups.items[1], "44"));
}
