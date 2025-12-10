const std = @import("std");
const volt_core = @import("volt_core");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Volt Core - Guitar Distortion POC\n", .{});
    std.debug.print("==================================\n\n", .{});

    // Create audio buffer for guitar signal
    const sample_rate = 44100;
    const duration_seconds = 2;
    const sample_count = sample_rate * duration_seconds;
    const channel_count = 2; // stereo

    var audio_buffer = try volt_core.audio.AudioBuffer.init(
        allocator,
        sample_count,
        channel_count,
        sample_rate,
    );
    defer audio_buffer.deinit(allocator);

    // Generate test guitar signal (440 Hz - A note)
    std.debug.print("Generating guitar signal (440 Hz)...\n", .{});
    audio_buffer.generateTestSignal(440.0);

    // Create distortion effect with high drive
    var distortion = volt_core.effects.Distortion{
        .drive = 3.0, // High distortion
        .tone = 0.7,  // Warm tone
    };

    std.debug.print("Applying distortion effect (drive: {d:.1}, tone: {d:.1})...\n", .{ distortion.drive, distortion.tone });
    distortion.processBuffer(&audio_buffer);

    // Write output to WAV file
    const wav_writer = volt_core.wav.WAVWriter.init(allocator);
    const output_file = "guitar_distorted.wav";
    try wav_writer.writeBuffer(output_file, &audio_buffer);

    std.debug.print("✓ Output written to: {s}\n", .{output_file});
    std.debug.print("✓ Sample rate: {d} Hz\n", .{sample_rate});
    std.debug.print("✓ Duration: {d} seconds\n", .{duration_seconds});
    std.debug.print("✓ Channels: {d}\n", .{channel_count});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
