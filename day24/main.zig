const std = @import("std");
const shared = @import("shared");
const process = shared.process;
const iteration = shared.iteration;
const utils = shared.utils;
const eql = std.mem.eql;

const Input = struct {
    wire_id: []const u8,
    value: u8,
    bit: usize,
};

const Wire = struct {
    const Self = @This();

    id: []const u8,
    outputs: *std.ArrayList(*Gate),
    value: ?u8 = null,

    fn init(allocator: std.mem.Allocator, id: []const u8) !Self {
        const outputs: *std.ArrayList(*Gate) = try allocator.create(std.ArrayList(*Gate));
        outputs.* = try std.ArrayList(*Gate).initCapacity(allocator, 4);
        return Self{
            .id = id,
            .outputs = outputs,
        };
    }
};

const GateType = enum { AND, OR, XOR };

const Gate = struct {
    input1: []const u8,
    input2: []const u8,
    output: []const u8,
    gate_type: GateType,
};

const Context = struct {
    delimiters: std.AutoHashMap(u8, bool),
    loading_inputs: bool = true,
    inputs: *std.ArrayList(Input),
    gates: *std.ArrayList(*Gate),
    wires_by_id: *std.StringHashMap(*Wire),
};

const Line = struct {};

pub fn main() !void {
    const day = "day24";
    //const file_name = day ++ "/test_file.txt";
    //const file_name = day ++ "/test_cases.txt";
    const file_name = day ++ "/input.txt";

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_allocator.deinit();

    var delimiters = std.AutoHashMap(u8, bool).init(arena_allocator.allocator());
    try delimiters.put(':', true);
    try delimiters.put(' ', true);
    try delimiters.put('-', true);
    try delimiters.put('>', true);

    var inputs = try std.ArrayList(Input).initCapacity(arena_allocator.allocator(), 100);
    defer inputs.deinit();

    var gates = try std.ArrayList(*Gate).initCapacity(arena_allocator.allocator(), 300);
    defer gates.deinit();

    var wires_by_id = std.StringHashMap(*Wire).init(arena_allocator.allocator());
    defer wires_by_id.deinit();

    var context = Context{
        .delimiters = delimiters,
        .inputs = &inputs,
        .gates = &gates,
        .wires_by_id = &wires_by_id,
    };

    const parsed_lines = try process.FileParser(*Context, Line, parse_line).parse(
        arena_allocator.allocator(),
        &context,
        file_name,
    );
    defer parsed_lines.deinit();

    try calculate(arena_allocator.allocator(), &context);
    try calculate_2(arena_allocator.allocator(), &context);
}

fn parse_line(allocator: std.mem.Allocator, context: *Context, line: []const u8) !Line {
    if (line.len == 0) {
        context.loading_inputs = false;
        return .{};
    }

    var parser = process.LineParser().init(allocator, context.delimiters, line);
    defer parser.deinit();

    if (context.loading_inputs) {
        const wire_id = try parser.read_string();
        const value = try parser.read_int(u8, 10);
        try context.inputs.append(Input{
            .wire_id = wire_id,
            .value = value,
            .bit = 0,
        });
        return .{};
    }

    const input1 = try parser.read_string();
    const gate_type = std.meta.stringToEnum(GateType, try parser.read_string()).?;
    const input2 = try parser.read_string();
    const output = try parser.read_string();

    //Create the gate
    const gate: *Gate = try allocator.create(Gate);
    gate.* = Gate{
        .input1 = input1,
        .input2 = input2,
        .gate_type = gate_type,
        .output = output,
    };
    try context.gates.append(gate);

    //Create wires for everything....
    const in1 = try context.wires_by_id.getOrPut(input1);
    if (!in1.found_existing) {
        const w: *Wire = try allocator.create(Wire);
        w.* = try Wire.init(allocator, input1);
        in1.value_ptr.* = w;
    }
    try in1.value_ptr.*.outputs.append(gate);
    const in2 = try context.wires_by_id.getOrPut(input2);
    if (!in2.found_existing) {
        const w: *Wire = try allocator.create(Wire);
        w.* = try Wire.init(allocator, input2);
        in2.value_ptr.* = w;
    }
    try in2.value_ptr.*.outputs.append(gate);
    const out = try context.wires_by_id.getOrPut(output);
    if (!out.found_existing) {
        const w: *Wire = try allocator.create(Wire);
        w.* = try Wire.init(allocator, output);
        out.value_ptr.* = w;
    }

    return .{};
}

fn clearWires(context: *const Context) void {
    var it = context.wires_by_id.valueIterator();
    while (it.next()) |wire| {
        wire.*.value = null;
    }
}

const ValueChange = struct {
    wire_id: []const u8,
    new_value: u8,
};

fn gateValue(gate_type: GateType, value1: ?u8, value2: ?u8) ?u8 {
    if (value1 == null or value2 == null) {
        return null;
    }
    const output_on = switch (gate_type) {
        GateType.AND => value1.? == 1 and value2.? == 1,
        GateType.OR => value1.? == 1 or value2.? == 1,
        GateType.XOR => value1 != value2,
    };
    return if (output_on) 1 else 0;
}

fn run(
    context: *const Context,
    inputs: *std.ArrayList(Input),
    current_changes: *std.ArrayList(ValueChange),
    next_changes: *std.ArrayList(ValueChange),
) !void {
    clearWires(context);
    //Start by pushing in the input values....
    current_changes.clearRetainingCapacity();
    for (inputs.items) |input| {
        try current_changes.append(ValueChange{ .wire_id = input.wire_id, .new_value = input.value });
    }

    //Process the next set of value changes - then swap over the current and next for the next round
    while (current_changes.items.len > 0) {
        next_changes.clearRetainingCapacity();

        for (current_changes.items) |change| {
            //find the wire
            const wire = context.wires_by_id.get(change.wire_id).?;
            //bomb out if we already set it
            if (wire.value != null) {
                return error.CircularChange;
            }
            wire.value = change.new_value;
            //check any associated gates and propagate if both inputs are now set
            for (wire.outputs.items) |gate| {
                const input1 = context.wires_by_id.get(gate.input1).?;
                const input2 = context.wires_by_id.get(gate.input2).?;
                if (gateValue(gate.gate_type, input1.value, input2.value)) |output_value| {
                    try next_changes.append(ValueChange{ .wire_id = gate.output, .new_value = output_value });
                }
            }
        }

        std.mem.swap(std.ArrayList(ValueChange), current_changes, next_changes);
    }
}

/// We want the highest first
fn sortByWireId(_: void, lhs: *Wire, rhs: *Wire) bool {
    return std.mem.order(u8, lhs.id, rhs.id) == .gt;
}

fn calculate(allocator: std.mem.Allocator, context: *const Context) !void {
    var next_changes = try std.ArrayList(ValueChange).initCapacity(allocator, 100);
    defer next_changes.deinit();
    var current_changes = try std.ArrayList(ValueChange).initCapacity(allocator, 100);
    defer current_changes.deinit();

    //Run the logic gates...
    try run(
        context,
        context.inputs,
        &current_changes,
        &next_changes,
    );

    //find all of the zs
    var z_wires = try std.ArrayList(*Wire).initCapacity(allocator, 64);
    defer z_wires.deinit();

    var it = context.wires_by_id.valueIterator();
    while (it.next()) |wire| {
        if (wire.*.id[0] == 'z') {
            try z_wires.append(wire.*);
        }
    }
    std.mem.sort(*Wire, z_wires.items, {}, sortByWireId);

    //now 'add it all up' starting with the highest bit
    var z_result: usize = 0;
    for (z_wires.items) |wire| {
        z_result <<= 1;
        z_result += wire.value.?;
    }

    try std.io.getStdOut().writer().print("Part 1 z {d}\n", .{z_result});
}

fn populateWithBit(input_name: *std.ArrayList(u8), prefix: u8, bit: usize) !void {
    input_name.clearRetainingCapacity();
    try input_name.writer().print("{c}{d:0>2}", .{ prefix, bit });
}

fn setUpInputsForCarry(inputs: *std.ArrayList(Input), to_bit: usize) void {
    for (inputs.items) |*input| {
        if (input.bit <= to_bit) {
            input.value = 1;
        } else {
            input.value = 0;
        }
    }
}

fn checkOutputsCarried(
    context: *const Context,
    input_name: *std.ArrayList(u8),
    num_bits: usize,
    to_bit: usize,
) !bool {
    for (0..num_bits) |bit| {
        try populateWithBit(input_name, 'z', bit);
        const wire = context.wires_by_id.get(input_name.items).?;
        if (bit == 0 or bit > to_bit) {
            if (wire.value != 0) {
                return false;
            }
            continue;
        }
        if (wire.value != 1) {
            return false;
        }
    }
    return true;
}

fn setUpInputsForNoCarry(inputs: *std.ArrayList(Input), bit: usize, prefix: u8) void {
    for (inputs.items) |*input| {
        if (input.bit == bit and input.wire_id[0] == prefix) {
            input.value = 1;
        } else {
            input.value = 0;
        }
    }
}

fn checkOutputsNoCarry(
    context: *const Context,
    input_name: *std.ArrayList(u8),
    num_bits: usize,
    on_bit: usize,
) !bool {
    for (0..num_bits) |bit| {
        try populateWithBit(input_name, 'z', bit);
        const wire = context.wires_by_id.get(input_name.items).?;
        if (bit == on_bit) {
            if (wire.value != 1) {
                return false;
            }
            continue;
        }
        if (wire.value != 0) {
            return false;
        }
    }
    return true;
}

fn testBit(
    context: *const Context,
    inputs: *std.ArrayList(Input),
    current_changes: *std.ArrayList(ValueChange),
    next_changes: *std.ArrayList(ValueChange),
    input_name: *std.ArrayList(u8),
    num_bits: usize,
    bit: usize,
) !bool {
    setUpInputsForCarry(inputs, bit);
    try run(context, inputs, current_changes, next_changes);
    if (!try checkOutputsCarried(context, input_name, num_bits, bit + 1)) {
        return false;
    }

    setUpInputsForNoCarry(inputs, bit, 'x');
    try run(context, inputs, current_changes, next_changes);
    if (!try checkOutputsNoCarry(context, input_name, num_bits, bit)) {
        return false;
    }

    setUpInputsForNoCarry(inputs, bit, 'y');
    try run(context, inputs, current_changes, next_changes);
    if (!try checkOutputsNoCarry(context, input_name, num_bits, bit)) {
        return false;
    }

    return true; //all ok
}

fn testAllBits(
    context: *const Context,
    inputs: *std.ArrayList(Input),
    current_changes: *std.ArrayList(ValueChange),
    next_changes: *std.ArrayList(ValueChange),
    input_name: *std.ArrayList(u8),
    num_bits: usize,
) !bool {
    for (0..num_bits) |bit| {
        if (!try testBit(
            context,
            &inputs,
            &current_changes,
            &next_changes,
            &input_name,
            num_bits,
            bit,
        )) {
            return false;
        }
    }
    return true;
}

fn swapOutputs(gate1: *Gate, gate2: *Gate) void {
    const temp_output = gate1.output;
    gate1.output = gate2.output;
    gate2.output = temp_output;
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn setUpSwap(swaps: *std.AutoHashMap(usize, void), context: *const Context, index1: usize, index2: usize) !void {
    try swaps.put(index1, {});
    try swaps.put(index2, {});
    const gate1 = context.gates.items[index1];
    const gate2 = context.gates.items[index2];
    swapOutputs(gate1, gate2);
}

fn calculate_2(allocator: std.mem.Allocator, context: *const Context) !void {
    var next_changes = try std.ArrayList(ValueChange).initCapacity(allocator, 100);
    defer next_changes.deinit();
    var current_changes = try std.ArrayList(ValueChange).initCapacity(allocator, 100);
    defer current_changes.deinit();

    //work out how many bits in the input
    var max_bit: u8 = 0;
    var it = context.wires_by_id.keyIterator();
    while (it.next()) |id| {
        if (id.*[0] == 'x') {
            const bit_num = try std.fmt.parseInt(u8, id.*[1..], 10);
            max_bit = @max(max_bit, bit_num);
        }
    }
    const num_bits = max_bit + 1;
    try std.io.getStdOut().writer().print("Found {d} bits\n", .{num_bits});

    //used repeatedly to construct input names
    var input_name = try std.ArrayList(u8).initCapacity(allocator, 3);
    defer input_name.deinit();

    //Set up the inputs... initially all at 0
    var inputs = try std.ArrayList(Input).initCapacity(allocator, num_bits * 2);
    for (0..num_bits) |bit| {
        try populateWithBit(&input_name, 'x', bit);
        try inputs.append(Input{ .wire_id = try allocator.dupe(u8, input_name.items), .value = 0, .bit = bit });
        try populateWithBit(&input_name, 'y', bit);
        try inputs.append(Input{ .wire_id = try allocator.dupe(u8, input_name.items), .value = 0, .bit = bit });
    }

    var swaps = std.AutoHashMap(usize, void).init(allocator);
    defer swaps.deinit();

    // try setUpSwap(&swaps, context, 81, 136);
    // try setUpSwap(&swaps, context, 157, 173);
    // try setUpSwap(&swaps, context, 87, 109);
    // try setUpSwap(&swaps, context, 30, 94);

    //now find where there are failures and see if we can fix
    var has_error = true;
    outer: while (has_error) {
        has_error = false;
        for (0..num_bits) |bit| {
            if (!try testBit(context, &inputs, &current_changes, &next_changes, &input_name, num_bits, bit)) {
                has_error = true;
                try std.io.getStdOut().writer().print("Failed at bit {d}\n", .{bit});
                //try to fix...
                for (0..context.gates.items.len) |gate1_index| {
                    if (swaps.contains(gate1_index)) {
                        continue;
                    }
                    for (0..context.gates.items.len) |gate2_index| {
                        // if (gate1_index == 30 and gate2_index == 94) {
                        //     continue;
                        // }
                        // if (gate1_index == 94 and gate2_index == 30) {
                        //     continue;
                        // }
                        if (gate1_index == gate2_index) {
                            continue;
                        }
                        if (swaps.contains(gate2_index)) {
                            continue;
                        }
                        //swap over the outputs...
                        const gate1 = context.gates.items[gate1_index];
                        const gate2 = context.gates.items[gate2_index];
                        swapOutputs(gate1, gate2);
                        var good_to_bit = true;
                        for (0..bit + 2) |the_bit| {
                            if (!try testBit(
                                context,
                                &inputs,
                                &current_changes,
                                &next_changes,
                                &input_name,
                                num_bits,
                                the_bit,
                            )) {
                                good_to_bit = false;
                            }
                        }
                        //was this good - did it reduce the failures?
                        if (good_to_bit) {
                            //keep it - record that we already swapped these mofos
                            try swaps.put(gate1_index, {});
                            try swaps.put(gate2_index, {});
                            try std.io.getStdOut().writer().print("Swapping {d} and {d} seems to be good to {d}\n", .{
                                gate1_index,
                                gate2_index,
                                bit,
                            });
                            //swapOutputs(gate1, gate2);
                            continue :outer;
                        } else {
                            //put back, let's try something else
                            swapOutputs(gate1, gate2);
                        }
                    }
                }
                try std.io.getStdOut().writer().writeAll("!!! Failed to find fix !!!\n");
                break :outer;
            }
        }
        break :outer;
    }

    var ids = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    var swap_it = swaps.keyIterator();
    while (swap_it.next()) |index| {
        const gate = context.gates.items[index.*];
        try ids.append(gate.output);
    }
    std.mem.sort([]const u8, ids.items, {}, stringLessThan);

    try std.io.getStdOut().writeAll("Part 2: ");
    for (ids.items) |id| {
        try std.io.getStdOut().writeAll(id);
        try std.io.getStdOut().writeAll(",");
    }
    try std.io.getStdOut().writeAll("\n");
}
