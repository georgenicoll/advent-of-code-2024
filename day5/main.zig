const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Page = u32;

const Ordering = struct {
    before_page: Page,
    after_page: Page,

    fn print(self: Ordering, writer: anytype) !void {
        try writer.print("{d}|{d}", .{ self.before_page, self.after_page });
    }
};

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
    page_ordering_rules: std.ArrayList(Ordering),
    updates: std.ArrayList([]const Page),
    finished_ordering_rules: bool = false,

    fn print(self: Context, writer: anytype) !void {
        for (self.page_ordering_rules.items) |rule| {
            try rule.print(writer);
            try writer.writeAll("\n");
        }
        try writer.writeAll("\n");
        for (self.updates.items) |update| {
            for (update) |page| {
                try writer.print("{d},", .{page});
            }
            try writer.writeAll("\n");
        }
    }
};

const Line = struct {};

pub fn main() !void {
    //const file_name = "day5/test_file.txt";
    //const file_name = "day5/test_cases.txt";
    const file_name = "day5/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put('|', true);
    try delimiters.put(',', true);

    var page_ordering_rules = std.ArrayList(Ordering).init(arena_allocator.allocator());
    defer page_ordering_rules.deinit();

    var updates = std.ArrayList([]const Page).init(arena_allocator.allocator());
    defer updates.deinit();

    var context = Context{
        .delimiters = delimiters,
        .page_ordering_rules = page_ordering_rules,
        .updates = updates,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parseLine).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    // const stdout = std.io.getStdOut();
    // try context.print(stdout.writer());

    try calculate_both(arena_allocator.allocator(), context);
}

fn parseLine(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    var parser = process.LineParser().init(allocator, context.delimiters, line);

    if (context.finished_ordering_rules) {
        var pages = std.ArrayList(Page).init(allocator);
        defer pages.deinit();

        var next: ?Page = parser.read_int(Page, 10) catch null;
        while (next != null) {
            try pages.append(next.?);
            next = parser.read_int(Page, 10) catch null;
        }

        try context.updates.append(try pages.toOwnedSlice());
    } else {
        if (line.len == 0) {
            context.finished_ordering_rules = true;
        } else {
            const before_page = try parser.read_int(Page, 10);
            const after_page = try parser.read_int(Page, 10);
            const ordering = .{
                .before_page = before_page,
                .after_page = after_page,
            };
            try context.page_ordering_rules.append(ordering);
        }
    }
    return .{};
}

const Pages = struct {
    const Self = @This();

    page: Page,
    pages: *std.AutoHashMap(Page, void),

    fn init(allocator: std.mem.Allocator, page: Page) !Self {
        const map: *std.AutoHashMap(Page, void) = try allocator.create(std.AutoHashMap(Page, void));
        map.* = std.AutoHashMap(Page, void).init(allocator);
        return .{
            .page = page,
            .pages = map,
        };
    }

    fn deinit(self: *Pages) void {
        self.pages.deinit();
    }
};

fn isGoodUpdate(must_be_after: *std.AutoHashMap(Page, Pages), update: []const Page) bool {
    //Check through each item in the list making sure that it doesn't have items that it should be after after it
    if (update.len < 2) {
        return true;
    }
    for (0..update.len - 1) |index_to_check| {
        const page_to_check = update[index_to_check];
        const maybe_must_be_after_pages: ?Pages = must_be_after.get(page_to_check);
        if (maybe_must_be_after_pages) |must_be_after_pages| {
            for (index_to_check + 1..update.len) |following_page_index| {
                const following_page = update[following_page_index];
                //If the following page is in the must_be_after_pages then this is not a good row
                const should_be_after = must_be_after_pages.pages.contains(following_page);
                if (should_be_after) {
                    return false;
                }
            }
        }
    }
    //Get here, it's good
    return true;
}

fn getMiddlePage(update: []const Page) Page {
    if (update.len % 2 == 0) {
        std.io.getStdOut().writer().print("Found even length: {any}\n", .{update}) catch {};
    }
    const index = update.len / 2;
    return update[index];
}

fn calculate_both(allocator: std.mem.Allocator, context: Context) !void {
    //map of page to pages they must be after
    var must_be_after = std.AutoHashMap(Page, Pages).init(allocator);
    defer {
        var it = must_be_after.valueIterator();
        while (it.next()) |pages| {
            pages.*.deinit();
        }
        must_be_after.deinit();
    }

    //populate must be after
    for (context.page_ordering_rules.items) |rule| {
        if (!must_be_after.contains(rule.after_page)) { //TODO is there a create if not there?
            const pages = try Pages.init(allocator, rule.after_page);
            try must_be_after.put(rule.after_page, pages);
        }
        var pages: Pages = must_be_after.get(rule.after_page).?;
        try pages.pages.put(rule.before_page, {});
        // const contains = pages.pages.contains(rule.before_page);
        // const count = pages.pages.count();
        // try std.io.getStdOut().writer().print("{d} must be after {d}: {d}/{any}\n", .{ rule.after_page, rule.before_page, count, contains });
    }

    // const stdout = std.io.getStdOut();

    // var it = must_be_after.iterator();
    // while (it.next()) |entry| {
    //     const key = entry.key_ptr.*;
    //     const pages: Pages = entry.value_ptr.*;
    //     try stdout.writer().print("{d} => [{d}] ", .{ key, pages.page });
    //     var key_it = pages.pages.keyIterator();
    //     while (key_it.next()) |after| {
    //         try stdout.writer().print("{d},", .{after.*});
    //     }
    //     try stdout.writer().writeAll("\n");
    // }

    try calculate1(context, &must_be_after);
    try calculate2(allocator, context, &must_be_after);
}

fn calculate1(context: Context, must_be_after: *std.AutoHashMap(Page, Pages)) !void {
    var sum: usize = 0;

    //loop through all updates
    for (context.updates.items) |update| {
        if (isGoodUpdate(must_be_after, update)) {
            sum += getMiddlePage(update);
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Sum {d}\n", .{sum});
}

const SortContext = struct {
    must_be_after: *std.AutoHashMap(Page, Pages),
};

fn correctOrder(must_be_after: *std.AutoHashMap(Page, Pages), update: []Page) void {
    const lessThanFn = struct {
        fn lessThanFn(context: SortContext, lhs: Page, rhs: Page) bool {
            const l_mba = context.must_be_after.get(lhs);
            if (l_mba) |mba| {
                if (mba.pages.contains(rhs)) {
                    return false;
                }
            }
            const r_mba = context.must_be_after.get(rhs);
            if (r_mba) |mba| {
                if (mba.pages.contains(lhs)) {
                    return true;
                }
            }
            return lhs < rhs;
        }
    }.lessThanFn;

    const context = SortContext{ .must_be_after = must_be_after };
    while (!isGoodUpdate(must_be_after, update)) {
        std.mem.sort(u32, update, context, lessThanFn);
    }
}

fn calculate2(allocator: std.mem.Allocator, context: Context, must_be_after: *std.AutoHashMap(Page, Pages)) !void {
    var sum: usize = 0;

    //loop through all updates
    for (context.updates.items) |update| {
        if (!isGoodUpdate(must_be_after, update)) {
            const copied = try allocator.dupe(Page, update);
            correctOrder(must_be_after, copied);
            sum += getMiddlePage(copied);
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Sum {d}\n", .{sum});
}

const expect = std.testing.expect;

test "getMiddlePage" {
    try expect(getMiddlePage(&[_]u32{ 75, 47, 61, 53, 29 }) == 61);
    try expect(getMiddlePage(&[_]u32{ 1, 2, 3, 4, 5, 6, 7 }) == 4);
    try expect(getMiddlePage(&[_]u32{ 1, 2, 3, 4 }) == 3);
}
