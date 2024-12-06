const std = @import("std");

pub fn Grid(comptime ELEMENT_TYPE: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        rows: std.ArrayList([]ELEMENT_TYPE),
        width: usize = 0,
        height: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .rows = std.ArrayList([]ELEMENT_TYPE).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.rows.items) |row| {
                self.allocator.free(row);
            }
            self.rows.deinit();
        }

        /// Add a new row, the row will be copied and must be freed as usual
        pub fn addRow(self: *Self, row: []const ELEMENT_TYPE) !void {
            if (self.height > 0 and row.len != self.width) {
                return error.InconsistentRowLength;
            }
            const new_row = try self.allocator.dupe(ELEMENT_TYPE, row);
            try self.rows.append(new_row);
            self.width = row.len;
            self.height = self.rows.items.len;
        }

        pub fn itemAt(self: Self, i: isize, j: isize) ?ELEMENT_TYPE {
            if (i < 0 or j < 0 or i >= self.width or j >= self.height) {
                return null;
            }
            const i_u = @as(usize, @intCast(i));
            const j_u = @as(usize, @intCast(j));
            return self.getItemWithinBounds(i_u, j_u);
        }

        pub fn itemAtU(self: Self, i: usize, j: usize) ?ELEMENT_TYPE {
            if (i >= self.width or j >= self.height) {
                return null;
            }
            return self.getItemWithinBounds(i, j);
        }

        fn getItemWithinBounds(self: Self, i: usize, j: usize) ELEMENT_TYPE {
            const row = self.rows.items[j];
            return row[i];
        }

        pub fn setItemAt(self: *Self, i: isize, j: isize, item: ELEMENT_TYPE) !void {
            if (i < 0 or j < 0 or i >= self.width or j >= self.height) {
                return error.OutOfBounds;
            }
            const i_u = @as(usize, @intCast(i));
            const j_u = @as(usize, @intCast(j));
            self.setItemWithinBounds(i_u, j_u, item);
        }

        pub fn setItemAtU(self: *Self, i: usize, j: usize, item: ELEMENT_TYPE) !void {
            if (i >= self.width or j >= self.height) {
                return error.OutOfBounds;
            }
            self.setItemWithinBounds(i, j, item);
        }

        fn setItemWithinBounds(self: *Self, i: usize, j: usize, item: ELEMENT_TYPE) void {
            const row = self.rows.items[j];
            row[i] = item;
        }

        pub fn print(self: Self, writer: anytype, comptime element_format: []const u8) !void {
            for (self.rows.items) |row| {
                for (row) |cell| {
                    try writer.print(element_format, .{cell});
                }
                try writer.writeAll("\n");
            }
            try writer.print("width: {d}, height: {d}\n", .{ self.width, self.height });
        }
    };
}

const expect = std.testing.expect;
const testing_allocator = std.testing.allocator;

test "add rows and retrieve values" {
    var grid = Grid(u8).init(testing_allocator);
    defer grid.deinit();

    //Add array
    try grid.addRow("ABCDE");
    try grid.addRow("12345");

    try expect(grid.width == 5);
    try expect(grid.height == 2);
    try expect(grid.itemAt(0, 0) == 'A');
    try expect(grid.itemAt(4, 1) == '5');
    try expect(grid.itemAtU(2, 0) == 'C');
    try expect(grid.itemAtU(3, 1) == '4');
    try expect(grid.itemAt(-1, 1) == null);
    try expect(grid.itemAt(3, 2) == null);
    try expect(grid.itemAtU(5, 1) == null);
    try expect(grid.itemAtU(3, 2) == null);
}
