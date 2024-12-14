const std = @import("std");

pub fn Zip(
    comptime A: type,
    comptime B: type,
    comptime C: type,
) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        /// zip 2 slices, applying the combiner function to produce the value in the
        /// returned slice
        pub fn zip(
            self: Self,
            items1: []const A,
            items2: []const B,
            combiner: fn (std.mem.Allocator, A, B) anyerror!C,
        ) ![]C {
            var output = std.ArrayList(C).init(self.allocator);

            var i: usize = 0;
            while (i < items1.len and i < items2.len) : (i += 1) {
                const a = items1[i];
                const b = items2[i];
                const c = try combiner(self.allocator, a, b);
                try output.append(c);
            }

            return try output.toOwnedSlice();
        }
    };
}

/// Create a 'Folder'.  Types are:
/// - T the type of the slice
/// - R the initial value and result type for the fold
pub fn Fold(
    comptime T: type,
    comptime R: type,
) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        pub fn fold(
            self: Self,
            initial_value: R,
            items: []const T,
            combiner: fn (std.mem.Allocator, R, T) anyerror!R,
        ) !R {
            var current_value = initial_value;

            for (items) |item| {
                current_value = try combiner(self.allocator, current_value, item);
            }

            return current_value;
        }
    };
}

pub fn Map(
    comptime T: type,
    comptime R: type,
) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn map(
            self: Self,
            items: []const T,
            mapping_fn: fn (std.mem.Allocator, T) anyerror!R,
        ) ![]R {
            var result = std.ArrayList(R).init(self.allocator);
            for (items) |item| {
                const mapped = try mapping_fn(self.allocator, item);
                try result.append(mapped);
            }
            return result.toOwnedSlice();
        }
    };
}

const expect = std.testing.expect;
const eql = std.meta.eql;

const Vals = struct {
    v1: u8,
    v2: i32,
};

test "zip 2 array lists" {
    const allocator = std.testing.allocator;

    var list1 = std.ArrayList(u8).init(allocator);
    defer list1.deinit();
    try list1.appendSlice("hello");

    var list2 = std.ArrayList(i32).init(allocator);
    defer list2.deinit();
    try list2.appendSlice(&[_]i32{ 1, 2, 3, 4, 5 });

    const zipper = Zip(u8, i32, Vals).init(allocator);
    const combiner = struct {
        fn combiner(alloc: std.mem.Allocator, v1: u8, v2: i32) !Vals {
            _ = alloc;
            return .{ .v1 = v1, .v2 = v2 };
        }
    }.combiner;

    const res = try zipper.zip(list1.items, list2.items, combiner);
    defer allocator.free(res);

    try expect(res.len == 5);
    try expect(eql(res[0], Vals{ .v1 = 'h', .v2 = 1 }));
    try expect(eql(res[1], Vals{ .v1 = 'e', .v2 = 2 }));
    try expect(eql(res[2], Vals{ .v1 = 'l', .v2 = 3 }));
    try expect(eql(res[3], Vals{ .v1 = 'l', .v2 = 4 }));
    try expect(eql(res[4], Vals{ .v1 = 'o', .v2 = 5 }));
}

test "zip 2 array lists, first shorter" {
    const allocator = std.testing.allocator;

    var list1 = std.ArrayList(i32).init(allocator);
    defer list1.deinit();
    try list1.appendSlice(&[_]i32{ 3, 4, 6 });

    var list2 = std.ArrayList(i32).init(allocator);
    defer list2.deinit();
    try list2.appendSlice(&[_]i32{ -1, 2, 3, 4 });

    const zipper = Zip(i32, i32, i32).init(allocator);
    const combiner = struct {
        fn combiner(alloc: std.mem.Allocator, v1: i32, v2: i32) !i32 {
            _ = alloc;
            return v1 + v2;
        }
    }.combiner;

    const res = try zipper.zip(list1.items, list2.items, combiner);
    defer allocator.free(res);

    try expect(res.len == 3);
    try expect(res[0] == 2);
    try expect(res[1] == 6);
    try expect(res[2] == 9);
}

test "zip 2 array lists, second shorter" {
    const allocator = std.testing.allocator;

    var list1 = std.ArrayList(i32).init(allocator);
    defer list1.deinit();
    try list1.appendSlice(&[_]i32{ 3, 4, 6 });

    var list2 = std.ArrayList(i32).init(allocator);
    defer list2.deinit();
    try list2.appendSlice(&[_]i32{ -1, 2 });

    const zipper = Zip(i32, i32, i32).init(allocator);
    const combiner = struct {
        fn combiner(alloc: std.mem.Allocator, v1: i32, v2: i32) !i32 {
            _ = alloc;
            return v1 + v2;
        }
    }.combiner;

    const res = try zipper.zip(list1.items, list2.items, combiner);
    defer allocator.free(res);

    try expect(res.len == 2);
    try expect(res[0] == 2);
    try expect(res[1] == 6);
}

const Vals2 = struct {
    v1: usize,
    v2: i32,
};

test "fold into an array list" {
    const allocator = std.testing.allocator;

    const items = [_]i32{ 2, 5, 8 };

    const combiner = struct {
        fn combiner(
            alloc: std.mem.Allocator,
            list: *std.ArrayList(Vals2),
            item: i32,
        ) anyerror!*std.ArrayList(Vals2) {
            _ = alloc;
            const vals = Vals2{ .v1 = list.items.len, .v2 = item };
            try list.append(vals);
            return list;
        }
    }.combiner;

    const folder = Fold(i32, *std.ArrayList(Vals2)).init(allocator);
    var initial_value = std.ArrayList(Vals2).init(allocator);
    const res = try folder.fold(
        &initial_value,
        &items,
        combiner,
    );
    defer res.deinit();

    try expect(res.items.len == 3);
    try expect(eql(res.items[0], .{ .v1 = 0, .v2 = 2 }));
    try expect(eql(res.items[1], .{ .v1 = 1, .v2 = 5 }));
    try expect(eql(res.items[2], .{ .v1 = 2, .v2 = 8 }));
}

test "fold into a sum" {
    const allocator = std.testing.allocator;

    const items = [_]i32{ 2, 5, 8 };

    const combiner = struct {
        fn combiner(
            alloc: std.mem.Allocator,
            acc: i32,
            item: i32,
        ) !i32 {
            _ = alloc;
            return acc + item;
        }
    }.combiner;

    const folder = Fold(i32, i32).init(allocator);
    const res = try folder.fold(0, &items, combiner);

    try expect(res == 15);
}

test "map" {
    const allocator = std.testing.allocator;

    const items = [_]u32{ 2, 5, 8 };

    const mapper = struct {
        fn mapper(alloc: std.mem.Allocator, value: u32) !i64 {
            _ = alloc;
            return -@as(i64, value);
        }
    }.mapper;

    const map = Map(u32, i64).init(allocator);
    const res = try map.map(&items, mapper);
    defer allocator.free(res);

    try expect(res.len == 3);
    try expect(res[0] == -2);
    try expect(res[1] == -5);
    try expect(res[2] == -8);
}
