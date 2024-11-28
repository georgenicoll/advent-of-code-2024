const process = @import("process");

pub fn main() !void {
    try process.process("testing/test_file.txt");
}
