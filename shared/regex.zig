//Adapted from https://cookbook.ziglang.cc/15-01-regex.html
const std = @import("std");
const print = std.debug.print;
const c = @cImport({
    @cInclude("regex.h");
    @cInclude("regex_slim.h");
});

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
    /// Returns an array list containing array lists for each match
    fn exec(self: Regex, allocator: std.mem.Allocator, input: [:0]const u8) !std.ArrayList(std.ArrayList(u8)) {
        const match_size = 1;
        var pmatch: [match_size]c.regmatch_t = undefined;

        var re_matches = std.ArrayList(std.ArrayList(u8)).init(allocator);
        var string = input;

        while (true) {
            if (0 != c.regexec(self.inner, string, match_size, &pmatch, 0)) {
                break;
            }

            const slice = string[@as(usize, @intCast(pmatch[0].rm_so))..@as(usize, @intCast(pmatch[0].rm_eo))];
            const string_list = std.ArrayList(u8).fromOwnedSlice(allocator, std.allocator.dupe([]const u8, slice));
            try re_matches.append(string_list);

            string = string[@intCast(pmatch[0].rm_eo)..];
        }

        return re_matches;
    }
};

const expect = std.testing.expect;

test "matches" {
    const regex1 = try Regex.init(".*mul(\\d,\\d).*");
    defer regex1.deinit();

    try expect(regex1.matches("do()something((mul(123,456)))))()"));
    try expect(!regex1.matches("do()something((mu(123,456)))))()"));
}
