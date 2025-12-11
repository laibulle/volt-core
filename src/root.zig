//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const audio = @import("audio.zig");
pub const effects = @import("effects.zig");
pub const wav_loader = @import("wav_loader.zig");
pub const ir_loader = @import("ir_loader.zig");
pub const audio_player = @import("audio_player.zig");
pub const realtime_processor = @import("realtime_processor.zig");
pub const audio_driver = @import("audio_driver.zig");
pub const ports = @import("ports/effects.zig");
pub const core = @import("core/effect_chain.zig");
pub const chain_config = @import("chain_config.zig");
pub const cli = @import("cli.zig");
pub const analog = @import("effects/analog/analog.zig");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
