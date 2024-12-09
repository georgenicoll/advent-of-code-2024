//Adapted from https://cookbook.ziglang.cc/15-01-regex.html
const std = @import("std");
const print = std.debug.print;
const c = @cImport({
    @cInclude("regex.h");
    @cInclude("regex_slim.h");
});

// Following structs and types taken from running zig translate-c -lc lib/regex_slim.h
const struct_re_dfa_t_2 = opaque {};

const __re_long_size_t = c_ulong;

const reg_syntax_t = c_ulong;

const RegexTStart = extern struct {
    __buffer: ?*struct_re_dfa_t_2 = @import("std").mem.zeroes(?*struct_re_dfa_t_2),
    __allocated: __re_long_size_t = @import("std").mem.zeroes(__re_long_size_t),
    __used: __re_long_size_t = @import("std").mem.zeroes(__re_long_size_t),
    __syntax: reg_syntax_t = @import("std").mem.zeroes(reg_syntax_t),
    __fastmap: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    __translate: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    re_nsub: usize = @import("std").mem.zeroes(usize),
};
// End translate-c

pub const Match = struct {
    const Self = @This();

    full_match: []const u8,
    groups: std.ArrayList([]const u8),
};

pub const Matches = struct {
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
            self.allocator.free(match.full_match);
            for (match.groups.items) |group| {
                self.allocator.free(group);
            }
            match.groups.deinit();
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

    fn appendGroup(self: *Self, group: []const u8) !void {
        if (self.matches.items.len == 0) {
            return error.NoItemsAdded;
        }
        var match = self.matches.items[self.matches.items.len - 1];
        try match.groups.append(try self.allocator.dupe(u8, group));
    }
};

/// RegEx
///
/// init will compile the regex, then call match to see if a string matches, or call exec to return matches
///
/// For syntax see https://en.wikibooks.org/wiki/Regular_Expressions/POSIX_Basic_Regular_Expressions, this is
/// using the Extended RegEx syntax.
pub const Regex = struct {
    const Self = @This();

    inner: *c.regex_t,
    regext_start: *RegexTStart,

    pub fn init(pattern: [:0]const u8) !Self {
        const inner = c.alloc_regex_t().?;
        if (0 != c.regcomp(inner, pattern, c.REG_NEWLINE | c.REG_EXTENDED)) {
            return error.compile;
        }
        return .{
            .inner = inner,
            .regext_start = @ptrCast(@alignCast(inner)),
        };
    }

    pub fn deinit(self: Self) void {
        c.free_regex_t(self.inner);
    }

    pub fn numSubExpressions(self: Self) usize {
        return self.regext_start.re_nsub;
    }

    pub fn matches(self: Self, allocator: std.mem.Allocator, input: [:0]const u8) !bool {
        const match_size: usize = 1 + self.numSubExpressions();
        const pmatch = try allocator.alloc(c.regmatch_t, match_size);
        defer allocator.free(pmatch);
        return 0 == c.regexec(self.inner, input, match_size, pmatch.ptr, 0);
    }

    /// Execute the regex against the input string.
    /// Returns an array list containing array lists for each match - all should be cleaned up
    pub fn exec(self: Self, allocator: std.mem.Allocator, input: [:0]const u8) !Matches {
        const num_sub_expressions: usize = self.numSubExpressions();
        const match_size: usize = 1 + num_sub_expressions;
        const pmatch = try allocator.alloc(c.regmatch_t, match_size);
        defer allocator.free(pmatch);

        var re_matches = try Matches.init(allocator);
        var string = input;

        while (true) {
            if (0 != c.regexec(self.inner, string, match_size, pmatch.ptr, 0)) {
                break;
            }

            const start_match = @as(usize, @intCast(pmatch[0].rm_so));
            const end_match = @as(usize, @intCast(pmatch[0].rm_eo));

            if (start_match == end_match) {
                break;
            }

            const slice = string[start_match..end_match];
            try re_matches.appendMatch(slice);

            for (0..num_sub_expressions) |sub| {
                const start_sub = @as(usize, @intCast(pmatch[1 + sub].rm_so));
                const end_sub = @as(usize, @intCast(pmatch[1 + sub].rm_eo));
                const sub_slice = string[start_sub..end_sub];
                try re_matches.appendGroup(sub_slice);
            }

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
    try expect(try regex.matches(testing_alloc, "this should match nice!"));
}

test "exec simple" {
    const regex = try Regex.init("nice");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 0);

    const result = try regex.exec(testing_alloc, "this should nice match nice");
    defer result.deinit();
    try expect(result.matches.items.len == 2);
    try expect(eql(u8, result.matches.items[0].full_match, "nice"));
    try expect(eql(u8, result.matches.items[1].full_match, "nice"));
}

test "exec match :digit:" {
    const regex = try Regex.init("[[:digit:]]+");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 0);

    const result = try regex.exec(testing_alloc, "bob 123 rita 456 sue: 85");
    defer result.deinit();
    try expect(result.matches.items.len == 3);
    try expect(eql(u8, result.matches.items[0].full_match, "123"));
    try expect(eql(u8, result.matches.items[1].full_match, "456"));
    try expect(eql(u8, result.matches.items[2].full_match, "85"));
}

test "matches" {
    const regex = try Regex.init("mul\\([[:digit:]]+,[[:digit:]]+\\)");
    defer regex.deinit();

    try expect(try regex.matches(testing_alloc, "do()something((mul(123,456)))))()"));
    try expect(!(try regex.matches(testing_alloc, "do()something((mu(123,456)))))()")));
}

test "sub_expressions" {
    const regex = try Regex.init("mul\\(([[:digit:]]+),([[:digit:]]+)\\)");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 2);

    const text = "hello please mul(12,3) and also mul(3,44), kthnxbye";

    try expect(try regex.matches(testing_alloc, text));

    const result = try regex.exec(testing_alloc, text);
    defer result.deinit();

    try expect(result.matches.items.len == 2);
    try expect(eql(u8, result.matches.items[0].full_match, "mul(12,3)"));
    try expect(result.matches.items[0].groups.items.len == 2);
    try expect(eql(u8, result.matches.items[0].groups.items[0], "12"));
    try expect(eql(u8, result.matches.items[0].groups.items[1], "3"));
    try expect(eql(u8, result.matches.items[1].full_match, "mul(3,44)"));
    try expect(result.matches.items[1].groups.items.len == 2);
    try expect(eql(u8, result.matches.items[1].groups.items[0], "3"));
    try expect(eql(u8, result.matches.items[1].groups.items[1], "44"));
}
