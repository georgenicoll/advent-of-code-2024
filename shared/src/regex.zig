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

    allocator: std.mem.Allocator,
    full_match: []const u8,
    groups: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator, full_match: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .full_match = try allocator.dupe(u8, full_match),
            .groups = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: Self) void {
        self.allocator.free(self.full_match);
        self.groups.deinit();
    }
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
            match.deinit();
            self.allocator.destroy(match);
        }
        self.matches.deinit();
    }

    fn append(self: *Self, match: *Match) !void {
        try self.matches.append(match);
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

    pub fn matches(self: Self, allocator: std.mem.Allocator, input: []const u8) !bool {
        const match_size: usize = 1 + self.numSubExpressions();
        const pmatch = try allocator.alloc(c.regmatch_t, match_size);
        defer allocator.free(pmatch);
        const input_c: [*c]const u8 = @ptrCast(input);
        return 0 == c.regexec(self.inner, input_c, match_size, pmatch.ptr, 0);
    }

    /// Execute the regex against the input string.
    /// Returns a Matches struct containing array lists for each match - deinit must be called on the returned Matches
    pub fn exec(self: Self, allocator: std.mem.Allocator, input: []const u8) !Matches {
        var re_matches = try Matches.init(allocator);
        const matchFound = struct {
            fn matchFound(matches_context: *Matches, match: *Match) !bool {
                try matches_context.append(match);
                return true; //we are taking ownership
            }
        }.matchFound;
        try self.execWithCallback(*Matches, allocator, input, &re_matches, matchFound);
        return re_matches;
    }

    pub fn execWithCallback(
        self: Self,
        comptime Context: type,
        allocator: std.mem.Allocator,
        input: []const u8,
        context: Context,
        matchFoundFn: fn (Context, match: *Match) anyerror!bool, //Return true to take ownership
    ) !void {
        const num_sub_expressions: usize = self.numSubExpressions();
        const match_size: usize = 1 + num_sub_expressions;
        const pmatch = try allocator.alloc(c.regmatch_t, match_size);
        defer allocator.free(pmatch);

        const input_null_terminated: [:0]u8 = try allocator.allocSentinel(u8, input.len, 0);
        defer allocator.free(input_null_terminated);
        std.mem.copyForwards(u8, input_null_terminated, input);
        var string = input_null_terminated;

        while (true) {
            const string_c: [*c]const u8 = @ptrCast(string);
            if (0 != c.regexec(self.inner, string_c, match_size, pmatch.ptr, 0)) {
                break;
            }

            const start_match = @as(usize, @intCast(pmatch[0].rm_so));
            const end_match = @as(usize, @intCast(pmatch[0].rm_eo));

            if (start_match == end_match) {
                break;
            }

            const slice = string[start_match..end_match];

            const match: *Match = try allocator.create(Match);
            match.* = try Match.init(allocator, slice);
            for (0..num_sub_expressions) |sub| {
                const start_sub = @as(isize, @intCast(pmatch[1 + sub].rm_so));
                if (start_sub < 0) {
                    continue;
                }
                const end_sub = @as(usize, @intCast(pmatch[1 + sub].rm_eo));
                const sub_slice = string[@as(usize, @intCast(start_sub))..end_sub];
                try match.groups.append(sub_slice);
            }
            if (!(try matchFoundFn(context, match))) {
                match.deinit();
                allocator.destroy(match);
            }

            if (end_match >= string.len) {
                break; //we got to the end of the string
            }
            string = string[end_match..];
        }
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

test "match_at_start_and_end" {
    const regex = try Regex.init("(mul)\\(([[:digit:]]+),([[:digit:]]+)\\)");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 3);

    const text = "mul(12,3) and mul(3,44)";

    try expect(try regex.matches(testing_alloc, text));

    const result = try regex.exec(testing_alloc, text);
    defer result.deinit();

    try expect(result.matches.items.len == 2);
    try expect(eql(u8, result.matches.items[0].full_match, "mul(12,3)"));
    try expect(result.matches.items[0].groups.items.len == 3);
    try expect(eql(u8, result.matches.items[0].groups.items[0], "mul"));
    try expect(eql(u8, result.matches.items[0].groups.items[1], "12"));
    try expect(eql(u8, result.matches.items[0].groups.items[2], "3"));
    try expect(eql(u8, result.matches.items[1].full_match, "mul(3,44)"));
    try expect(result.matches.items[1].groups.items.len == 3);
    try expect(eql(u8, result.matches.items[1].groups.items[0], "mul"));
    try expect(eql(u8, result.matches.items[1].groups.items[1], "3"));
    try expect(eql(u8, result.matches.items[1].groups.items[2], "44"));
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

test "or_expression" {
    const regex = try Regex.init("(mul)\\(([[:digit:]]+),([[:digit:]]+)\\)|(do)\\(\\)|(don't)\\(\\)");
    defer regex.deinit();

    try expect(regex.numSubExpressions() == 5);

    const text = "xmul(1,2)ab%do()hgfdon't()bob";

    try expect(try regex.matches(testing_alloc, text));

    const result = try regex.exec(testing_alloc, text);
    defer result.deinit();

    try expect(result.matches.items.len == 3);

    try expect(eql(u8, result.matches.items[0].full_match, "mul(1,2)"));
    try expect(result.matches.items[0].groups.items.len == 3);
    try expect(eql(u8, result.matches.items[0].groups.items[0], "mul"));
    try expect(eql(u8, result.matches.items[0].groups.items[1], "1"));
    try expect(eql(u8, result.matches.items[0].groups.items[2], "2"));

    try expect(eql(u8, result.matches.items[1].full_match, "do()"));
    try expect(result.matches.items[1].groups.items.len == 1);
    try expect(eql(u8, result.matches.items[1].groups.items[0], "do"));

    try expect(eql(u8, result.matches.items[2].full_match, "don't()"));
    try expect(result.matches.items[2].groups.items.len == 1);
    try expect(eql(u8, result.matches.items[2].groups.items[0], "don't"));
}
