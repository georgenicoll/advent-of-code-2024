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

pub fn is_digit(c: u8) bool {
    return c <= '9' and c >= '0';
}

test "concat_strings" {
    const result = try concat_strings(std.testing.allocator, &.{ "bob", "is", "your", "uncle" });
    defer std.testing.allocator.free(result);

    try expect(eql(u8, result, "bobisyouruncle"));
}

test "is_digit" {
    try expect(is_digit('0'));
    try expect(is_digit('1'));
    try expect(is_digit('2'));
    try expect(is_digit('3'));
    try expect(is_digit('4'));
    try expect(is_digit('5'));
    try expect(is_digit('6'));
    try expect(is_digit('7'));
    try expect(is_digit('8'));
    try expect(is_digit('9'));
    try expect(!is_digit('a'));
    try expect(!is_digit('A'));
    try expect(!is_digit('z'));
    try expect(!is_digit('Z'));
}
