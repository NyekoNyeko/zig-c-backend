const std = @import("std");

pub fn main() !void {
    const a: usize = 1;
    const b: usize = 2;
    std.debug.assert(a == b);
}
