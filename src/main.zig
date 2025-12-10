const std = @import("std");
const volt_core = @import("volt_core");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Volt Core - Real-time Guitar Effects Player\n", .{});
    std.debug.print("============================================\n\n", .{});

    // Load guitar sample
    const loader = volt_core.wav_loader.WAVLoader.init(allocator);
    std.debug.print("Loading guitar sample: Electric Guitar 1 - Raw_105.wav\n", .{});

    var audio_buffer = loader.loadFile("Electric Guitar 1 - Raw_105.wav") catch |err| {
        std.debug.print("Error loading file: {}\n", .{err});
        return err;
    };
    defer audio_buffer.deinit(allocator);

    std.debug.print("✓ Loaded: {d} samples at {d}Hz ({d} channels)\n", .{
        audio_buffer.samples.len / audio_buffer.channel_count,
        audio_buffer.sample_rate,
        audio_buffer.channel_count,
    });

    // Apply distortion effect
    var distortion = volt_core.effects.Distortion{
        .drive = 2.5, // Moderate-high distortion
        .tone = 0.8, // Warm tone
    };

    std.debug.print("\nApplying distortion (drive: {d:.1}, tone: {d:.1})...\n", .{ distortion.drive, distortion.tone });
    distortion.processBuffer(&audio_buffer);

    // Play the processed audio
    var player = try volt_core.audio_player.AudioPlayer.init(allocator);
    defer player.deinit();

    std.debug.print("Starting playback...\n\n", .{});
    try player.playBuffer(
        audio_buffer.samples.ptr,
        audio_buffer.samples.len / audio_buffer.channel_count,
        audio_buffer.sample_rate,
        audio_buffer.channel_count,
    );

    std.debug.print("\n✓ Playback complete!\n", .{});
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
