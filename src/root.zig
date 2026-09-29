//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const fenster_audio = @import("fenster_audio.zig");
pub const fenster = @import("fenster.zig");
pub const microui = @import("microui.zig");
pub const atlas = @import("atlas.zig");
pub const renderer = @import("renderer.zig");

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

// Zig does not pull in test blocks from imported files automatically -- only the
// test root's own. Reference each module here so `zig build test` actually runs
// them. Without this, a module's tests silently never execute.
test {
    _ = @import("atlas.zig");
    _ = @import("fenster.zig");
    _ = @import("microui.zig");
    _ = @import("renderer.zig");
}
