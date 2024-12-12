const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Context = struct {
    grid: shared.aoc.Grid(u8),
};

const Line = struct {};

pub fn main() !void {
    const day = "day12";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var grid = shared.aoc.Grid(u8).init(arena_allocator.allocator());
    defer grid.deinit();

    var context = Context{
        .grid = grid,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    const stdout = std.io.getStdOut();
    try context.grid.print(stdout.writer(), "{c}");

    try calculate(arena_allocator.allocator(), &context);
    try calculate_2(arena_allocator.allocator(), &context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    _ = allocator;

    try context.grid.addRow(line);

    return .{};
}

const Plant = u8;

const Plot = struct {
    i: isize,
    j: isize,

    fn move(self: Plot, direction: Plot) Plot {
        return Plot{
            .i = self.i + direction.i,
            .j = self.j + direction.j,
        };
    }
};

const UP = Plot{ .i = 0, .j = -1 };
const DOWN = Plot{ .i = 0, .j = 1 };
const LEFT = Plot{ .i = -1, .j = 0 };
const RIGHT = Plot{ .i = 1, .j = 0 };

const DIRECTIONS = [4]Plot{ UP, DOWN, LEFT, RIGHT };

const Region = struct {
    const Self = @This();

    plant: Plant,
    plots: *std.AutoHashMap(Plot, usize), // plot to fence required for it

    fn init(allocator: std.mem.Allocator, plant: u8) !Region {
        const plots: *std.AutoHashMap(Plot, usize) = try allocator.create(std.AutoHashMap(Plot, usize));
        plots.* = std.AutoHashMap(Plot, usize).init(allocator);
        return Region{
            .plant = plant,
            .plots = plots,
        };
    }

    fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.plots.deinit();
        allocator.destroy(self.plots);
    }
};

fn populateRegion(
    context: *Context,
    stack: *std.ArrayList(Plot),
    region: *Region,
    start_plot: Plot,
) !void {
    stack.clearRetainingCapacity();

    // first one
    try stack.append(start_plot);

    while (stack.items.len > 0) {
        const plot = stack.pop();
        //already visited?
        if (region.plots.contains(plot)) {
            continue;
        }
        var fence_needed: usize = 0;
        //calculate where to visit next - keeping a track of how much fence is needed
        for (DIRECTIONS) |direction| {
            const next_plot = plot.move(direction);
            const next_plant = context.grid.itemAt(next_plot.i, next_plot.j);
            if (next_plant) |plant| {
                if (plant == region.plant) {
                    try stack.append(next_plot); //Visit that one
                } else {
                    fence_needed += 1;
                }
            } else {
                fence_needed += 1;
            }
        }
        //record the plot and fence needed
        try region.plots.put(plot, fence_needed);
    }
}

fn generateRegions(
    allocator: std.mem.Allocator,
    context: *Context,
    stack: *std.ArrayList(Plot),
    regions_by_plant: *std.AutoHashMap(Plant, *std.ArrayList(*Region)),
) !void {
    // calculate all of the regions
    for (0..context.grid.height) |j_u| {
        const j: isize = @as(isize, @intCast(j_u));
        inner: for (0..context.grid.width) |i_u| {
            const i: isize = @as(isize, @intCast(i_u));
            const plant = context.grid.itemAt(i, j).?;
            // is this already in a region?
            const regions_result = try regions_by_plant.getOrPut(plant);
            if (!regions_result.found_existing) {
                const new_regions: *std.ArrayList(*Region) = try allocator.create(std.ArrayList(*Region));
                new_regions.* = try std.ArrayList(*Region).initCapacity(allocator, 4);
                regions_result.value_ptr.* = new_regions;
            }
            const regions: *std.ArrayList(*Region) = regions_result.value_ptr.*;
            const plot = Plot{ .i = i, .j = j };
            for (regions.items) |region| {
                if (region.plots.contains(plot)) {
                    continue :inner; // already processed it, go to the next one
                }
            }
            // got here need a new region, work out all of the plots in it from here
            const new_region: *Region = try allocator.create(Region);
            new_region.* = try Region.init(allocator, plant);
            try populateRegion(context, stack, new_region, plot);
            try regions.append(new_region);
        }
    }
}

fn calculate(allocator: std.mem.Allocator, context: *Context) !void {
    var stack: std.ArrayList(Plot) = try std.ArrayList(Plot).initCapacity(allocator, 1000);
    defer stack.deinit();

    var regions_by_plant = std.AutoHashMap(Plant, *std.ArrayList(*Region)).init(allocator);
    defer {
        var it = regions_by_plant.valueIterator();
        while (it.next()) |regions| {
            for (regions.*.items) |region| {
                region.deinit(allocator);
            }
        }
        regions_by_plant.deinit();
    }

    try generateRegions(allocator, context, &stack, &regions_by_plant);

    var total_cost: usize = 0;
    var regions_it = regions_by_plant.valueIterator();
    while (regions_it.next()) |regions| {
        for (regions.*.items) |region| {
            //add up all the fence required
            var total_fence_required: usize = 0;
            var plot_it = region.plots.valueIterator();
            while (plot_it.next()) |fence_required| {
                total_fence_required += fence_required.*;
            }
            //cost is fence_required * area
            const cost = total_fence_required * region.plots.count();
            total_cost += cost;
        }
    }

    try std.io.getStdOut().writer().print("Part 1 Cost {d}\n", .{total_cost});
}

// Order by i and then j
fn iThenj(ctx: void, lhs: Plot, rhs: Plot) bool {
    _ = ctx;
    if (lhs.i == rhs.i) {
        return lhs.j < rhs.j;
    }
    return lhs.i < rhs.i;
}

// Order by i and then j
fn jTheni(ctx: void, lhs: Plot, rhs: Plot) bool {
    _ = ctx;
    if (lhs.j == rhs.j) {
        return lhs.i < rhs.i;
    }
    return lhs.j < rhs.j;
}

//New fence if there is a greater than 1 jump in j, or a change in i
fn verticalNewFence(plotA: Plot, plotB: Plot) bool {
    return (@abs(plotB.j - plotA.j) > 1) or (plotB.i != plotA.i);
}

//New fence if there is a greater than 1 jump in i, or a change in j
fn horizontalNewFence(plotA: Plot, plotB: Plot) bool {
    return (@abs(plotB.i - plotA.i) > 1) or (plotB.j != plotA.j);
}

fn calculateSides(
    context: *Context,
    plots: *std.ArrayList(Plot),
    region: *Region,
    side: Plot,
    lessThanFn: fn (void, Plot, Plot) bool,
    newFenceFn: fn (Plot, Plot) bool,
) !usize {
    //Left hand sides
    //all plots with nothing to their left
    plots.clearRetainingCapacity();
    var plot_it = region.plots.keyIterator();
    while (plot_it.next()) |plot| {
        const other_plot = plot.move(side);
        const other_plant = context.grid.itemAt(other_plot.i, other_plot.j);
        if (other_plant != region.plant) {
            try plots.append(plot.*);
        }
    }
    // If only 1 then we have 1 fences
    if (plots.items.len == 1) {
        return 1;
    }
    std.mem.sort(Plot, plots.items, {}, lessThanFn);
    // Loop through.  We have a new fence if we have a >1 jump in j, or a any change in i
    var num_fences: usize = 1;
    for (0..plots.items.len - 1) |p| {
        const plotA = plots.items[p];
        const plotB = plots.items[p + 1];
        if (newFenceFn(plotA, plotB)) {
            num_fences += 1;
        }
    }
    return num_fences;
}

fn calculateTotalSides(context: *Context, plots: *std.ArrayList(Plot), region: *Region) !usize {
    var total: usize = try calculateSides(context, plots, region, LEFT, iThenj, verticalNewFence);
    total += try calculateSides(context, plots, region, RIGHT, iThenj, verticalNewFence);
    total += try calculateSides(context, plots, region, UP, jTheni, horizontalNewFence);
    total += try calculateSides(context, plots, region, DOWN, jTheni, horizontalNewFence);
    return total;
}

fn calculate_2(allocator: std.mem.Allocator, context: *Context) !void {
    var stack: std.ArrayList(Plot) = try std.ArrayList(Plot).initCapacity(allocator, 1000);
    defer stack.deinit();

    var regions_by_plant = std.AutoHashMap(Plant, *std.ArrayList(*Region)).init(allocator);
    defer {
        var it = regions_by_plant.valueIterator();
        while (it.next()) |regions| {
            for (regions.*.items) |region| {
                region.deinit(allocator);
            }
        }
        regions_by_plant.deinit();
    }

    try generateRegions(allocator, context, &stack, &regions_by_plant);

    var plots = try std.ArrayList(Plot).initCapacity(allocator, 1000);

    var total_cost: usize = 0;
    var regions_it = regions_by_plant.valueIterator();
    while (regions_it.next()) |regions| {
        for (regions.*.items) |region| {
            const sides = try calculateTotalSides(context, &plots, region);
            //cost is fence_required * area
            const cost = sides * region.plots.count();
            total_cost += cost;
        }
    }

    try std.io.getStdOut().writer().print("Part 2 Cost {d}\n", .{total_cost});
}
