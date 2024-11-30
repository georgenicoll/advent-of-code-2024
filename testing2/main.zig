const std = @import("std");
const process = @import("shared").process;

pub fn main() !void {
    try process.process("testing/test_file.txt");
}
