const std = @import("std");

const expect = std.testing.expect;
const eql = std.mem.eql;

pub fn concat_strings(allocator: std.mem.Allocator, strings: []const []const u8) ![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    for (strings) |string| {
        _ = try list.appendSlice(string);
    }
    return list.toOwnedSlice();
}

test "concat_strings" {
    const result = try concat_strings(std.testing.allocator, &.{ "bob", "is", "your", "uncle" });
    defer std.testing.allocator.free(result);

    try expect(eql(u8, result, "bobisyouruncle"));
}
