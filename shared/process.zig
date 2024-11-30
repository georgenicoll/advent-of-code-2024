const std = @import("std");
const fs = std.fs;

pub fn process(file_name: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    //load the file, line by line
    const file = try fs.cwd().openFile(file_name, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();

    const stdout = std.io.getStdOut();
    const writer = line.writer();
    var line_no: usize = 0;
    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        line_no += 1;
        _ = try stdout.write(line.items);
        _ = try stdout.write("\n");
    } else |err| switch (err) {
        error.EndOfStream => {
            _ = try stdout.write(line.items);
            _ = try stdout.write("\n");
        },
        else => return err, //propagate it
    }

    _ = try stdout.write("Done");
    _ = try stdout.write("\n");
}
