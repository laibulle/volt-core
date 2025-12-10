const std = @import("std");
const c = @cImport({
    @cInclude("portaudio.h");
});

pub const AudioPlayer = struct {
    allocator: std.mem.Allocator,
    stream: ?*c.PaStream = null,
    is_playing: bool = false,

    pub fn init(allocator: std.mem.Allocator) !AudioPlayer {
        const err = c.Pa_Initialize();
        if (err != c.paNoError) {
            std.debug.print("PortAudio init error: {}\n", .{err});
            return error.PortAudioInitFailed;
        }
        return AudioPlayer{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AudioPlayer) void {
        if (self.stream != null) {
            _ = c.Pa_CloseStream(self.stream);
        }
        _ = c.Pa_Terminate();
    }

    pub fn playBuffer(self: *AudioPlayer, buffer: *const anyopaque, sample_count: usize, sample_rate: u32, channel_count: u32) !void {
        const sample_format = c.paFloat32;

        var stream: ?*c.PaStream = null;
        var output_params: c.PaStreamParameters = undefined;
        output_params.device = c.Pa_GetDefaultOutputDevice();
        output_params.channelCount = @as(c_int, @intCast(channel_count));
        output_params.sampleFormat = sample_format;
        output_params.suggestedLatency = 0.1;
        output_params.hostApiSpecificStreamInfo = null;

        const err = c.Pa_OpenStream(
            &stream,
            null,
            &output_params,
            @as(f64, @floatFromInt(sample_rate)),
            @as(c_ulong, @intCast(sample_count)),
            c.paClipOff,
            null,
            null,
        );

        if (err != c.paNoError) {
            std.debug.print("PortAudio open stream error: {}\n", .{err});
            return error.PortAudioOpenStreamFailed;
        }

        self.stream = stream;

        const err2 = c.Pa_WriteStream(stream, buffer, @as(c_ulong, @intCast(sample_count)));
        if (err2 != c.paNoError) {
            std.debug.print("PortAudio write stream error: {}\n", .{err2});
            return error.PortAudioWriteStreamFailed;
        }

        const err3 = c.Pa_StartStream(stream);
        if (err3 != c.paNoError) {
            std.debug.print("PortAudio start stream error: {}\n", .{err3});
            return error.PortAudioStartStreamFailed;
        }

        self.is_playing = true;
        std.debug.print("Playing audio...\n", .{});

        while (c.Pa_IsStreamActive(stream) > 0) {
            std.Thread.sleep(100_000_000); // 100ms
        }

        self.is_playing = false;
    }
};
