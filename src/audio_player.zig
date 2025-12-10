const std = @import("std");
const c = @cImport({
    @cInclude("portaudio.h");
});

const PlaybackContext = struct {
    buffer: [*]const f32,
    sample_count: usize,
    channel_count: u32,
    current_position: usize = 0,
};

fn audioCallback(
    input: ?*const anyopaque,
    output: ?*anyopaque,
    frameCount: c_ulong,
    timeInfo: ?*const c.PaStreamCallbackTimeInfo,
    statusFlags: c.PaStreamCallbackFlags,
    userData: ?*anyopaque,
) callconv(.c) c_int {
    _ = input;
    _ = timeInfo;
    _ = statusFlags;

    const context = @as(*PlaybackContext, @ptrCast(@alignCast(userData)));
    const out = @as([*]f32, @ptrCast(@alignCast(output)));

    var i: usize = 0;
    var max_sample: f32 = 0.0;
    while (i < frameCount) : (i += 1) {
        if (context.current_position < context.sample_count * context.channel_count) {
            const sample = context.buffer[context.current_position];
            out[i] = sample;
            if (sample > max_sample) max_sample = sample;
            context.current_position += 1;
        } else {
            out[i] = 0.0;
        }
    }

    if (context.current_position >= context.sample_count * context.channel_count) {
        return c.paComplete;
    }
    return c.paContinue;
}

pub const AudioPlayer = struct {
    allocator: std.mem.Allocator,
    stream: ?*c.PaStream = null,
    is_playing: bool = false,
    context: ?*PlaybackContext = null,

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
        if (self.context != null) {
            self.allocator.destroy(self.context.?);
        }
        _ = c.Pa_Terminate();
    }

    pub fn playBuffer(self: *AudioPlayer, buffer: [*]const f32, sample_count: usize, sample_rate: u32, channel_count: u32) !void {
        // Allocate persistent context
        const ctx = try self.allocator.create(PlaybackContext);
        ctx.* = PlaybackContext{
            .buffer = buffer,
            .sample_count = sample_count,
            .channel_count = channel_count,
        };
        self.context = ctx;

        // Get device info
        const device_id = c.Pa_GetDefaultOutputDevice();
        const device_info = c.Pa_GetDeviceInfo(device_id);
        std.debug.print("[Debug] Output Device ID: {d}\n", .{device_id});
        if (device_info != null) {
            const info = device_info.?;
            std.debug.print("[Debug] Max Output Channels: {d}\n", .{info[0].maxOutputChannels});
        }

        var stream: ?*c.PaStream = null;
        var output_params: c.PaStreamParameters = undefined;
        output_params.device = device_id;
        output_params.channelCount = @as(c_int, @intCast(channel_count));
        output_params.sampleFormat = c.paFloat32;
        output_params.suggestedLatency = 0.1;
        output_params.hostApiSpecificStreamInfo = null;

        std.debug.print("[Debug] Opening stream with {d} channels at {d}Hz, buffer size: {d}\n", .{ channel_count, sample_rate, sample_count });

        const err = c.Pa_OpenStream(
            &stream,
            null,
            &output_params,
            @as(f64, @floatFromInt(sample_rate)),
            256,
            c.paClipOff,
            audioCallback,
            ctx,
        );

        if (err != c.paNoError) {
            std.debug.print("PortAudio open stream error: {d}\n", .{err});
            return error.PortAudioOpenStreamFailed;
        }

        std.debug.print("[Debug] Stream opened successfully\n", .{});
        self.stream = stream;

        const err2 = c.Pa_StartStream(stream);
        if (err2 != c.paNoError) {
            std.debug.print("PortAudio start stream error: {d}\n", .{err2});
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
