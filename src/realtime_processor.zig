const std = @import("std");
const c = @cImport({
    @cInclude("portaudio.h");
});

const effects = @import("effects.zig");
const audio = @import("audio.zig");

pub const RealtimeContext = struct {
    // Effect chain
    distortion: *effects.Distortion,
    convolver: *effects.Convolver,

    // Circular buffer for IR convolution state
    conv_state: [*]f32,
    conv_state_len: usize,
    conv_state_pos: usize = 0,

    // For debug logging
    current_position: usize = 0,

    allocator: std.mem.Allocator,
};

/// Real-time audio processing callback for live input
fn realtimeCallback(
    input: ?*const anyopaque,
    output: ?*anyopaque,
    frameCount: c_ulong,
    timeInfo: ?*const c.PaStreamCallbackTimeInfo,
    statusFlags: c.PaStreamCallbackFlags,
    userData: ?*anyopaque,
) callconv(.c) c_int {
    _ = timeInfo;
    _ = statusFlags;

    const context = @as(*RealtimeContext, @ptrCast(@alignCast(userData)));
    const in = @as([*]const f32, @ptrCast(@alignCast(input)));
    const out = @as([*]f32, @ptrCast(@alignCast(output)));

    var max_input: f32 = 0.0;
    var max_output: f32 = 0.0;

    // Process each sample in real-time
    for (0..frameCount) |i| {
        var sample = in[i];

        if (sample > max_input) max_input = sample;
        if (sample < -max_input) max_input = -sample;

        // Apply distortion
        const drive = context.distortion.drive;
        const tone = context.distortion.tone;
        const driven = sample * drive;
        const soft_clipped = std.math.tanh(driven);
        sample = soft_clipped * tone;

        // Apply simple convolution (single-sample)
        // For real-time, we use a simplified convolver with ring buffer
        var conv_out: f32 = 0.0;
        if (context.convolver.ir_length > 0) {
            // Simple FIR filter approach
            const ir_ptr = context.convolver.ir_buffer;
            const max_taps = @min(10, context.convolver.ir_length); // Limit to 10 taps for real-time
            for (0..max_taps) |tap| {
                if (tap < context.conv_state_len) {
                    const idx = (context.conv_state_pos + tap) % context.conv_state_len;
                    conv_out += context.conv_state[idx] * ir_ptr[tap];
                }
            }
        }

        // Update state buffer
        context.conv_state[context.conv_state_pos] = sample;
        context.conv_state_pos = (context.conv_state_pos + 1) % context.conv_state_len;

        // Use only the convolved (wet) output - 100% cabinet simulation
        const final = std.math.clamp(conv_out, -1.0, 1.0);
        out[i] = final;

        if (final > max_output) max_output = final;
        if (final < -max_output) max_output = -final;
    }

    // Log periodically (every 44100 samples = 1 second at 44.1kHz)
    if (context.current_position % 44100 < frameCount) {
        std.debug.print("[Audio] Input Max: {d:.4}, Output Max: {d:.4}, Drive: {d:.1}\n", .{ max_input, max_output, context.distortion.drive });
    }
    context.current_position += frameCount;

    return c.paContinue;
}

pub const RealtimeProcessor = struct {
    allocator: std.mem.Allocator,
    stream: ?*c.PaStream = null,
    context: ?*RealtimeContext = null,

    pub fn init(allocator: std.mem.Allocator) !RealtimeProcessor {
        const err = c.Pa_Initialize();
        if (err != c.paNoError) {
            return error.PortAudioInitFailed;
        }
        return RealtimeProcessor{
            .allocator = allocator,
        };
    }

    pub fn listDevices(self: *RealtimeProcessor) void {
        _ = self;
        const device_count = c.Pa_GetDeviceCount();
        std.debug.print("\nAvailable Audio Devices:\n", .{});
        std.debug.print("========================\n\n", .{});

        for (0..@as(usize, @intCast(device_count))) |i| {
            const device_info = c.Pa_GetDeviceInfo(@as(c.PaDeviceIndex, @intCast(i)));
            if (device_info != null) {
                const info = device_info.?;
                std.debug.print("[{d}] {s}\n", .{ i, info[0].name });
                std.debug.print("    Input Channels: {d}\n", .{info[0].maxInputChannels});
                std.debug.print("    Output Channels: {d}\n", .{info[0].maxOutputChannels});
                std.debug.print("    Default Sample Rate: {d} Hz\n", .{@as(u32, @intFromFloat(info[0].defaultSampleRate))});
                std.debug.print("    Host API: {d}\n\n", .{info[0].hostApi});
            }
        }
    }

    pub fn promptDeviceSelection(self: *RealtimeProcessor) !struct { input_device: c.PaDeviceIndex, output_device: c.PaDeviceIndex } {
        _ = self;

        // For now, use default devices
        // In a real application, this would prompt interactively
        const input_device = c.Pa_GetDefaultInputDevice();
        const output_device = c.Pa_GetDefaultOutputDevice();

        std.debug.print("Using Input Device: {d}\n", .{input_device});
        std.debug.print("Using Output Device: {d}\n\n", .{output_device});

        return .{ .input_device = input_device, .output_device = output_device };
    }

    pub fn deinit(self: *RealtimeProcessor) void {
        if (self.stream != null) {
            _ = c.Pa_StopStream(self.stream);
            _ = c.Pa_CloseStream(self.stream);
        }
        if (self.context != null) {
            if (self.context.?.conv_state_len > 0) {
                self.allocator.free(self.context.?.conv_state[0..self.context.?.conv_state_len]);
            }
            self.allocator.destroy(self.context.?);
        }
        _ = c.Pa_Terminate();
    }

    pub fn startProcessing(
        self: *RealtimeProcessor,
        distortion: *effects.Distortion,
        convolver: *effects.Convolver,
        sample_rate: u32,
        duration_seconds: f32,
        input_device: c.PaDeviceIndex,
        output_device: c.PaDeviceIndex,
    ) !void {
        // Allocate convolver state buffer
        const conv_state_len = @max(64, convolver.ir_length / 10); // Smaller buffer for real-time
        const conv_state = try self.allocator.alloc(f32, conv_state_len);
        @memset(conv_state, 0.0);

        // Create processing context
        const ctx = try self.allocator.create(RealtimeContext);
        ctx.* = RealtimeContext{
            .distortion = distortion,
            .convolver = convolver,
            .conv_state = conv_state.ptr,
            .conv_state_len = conv_state_len,
            .allocator = self.allocator,
        };
        self.context = ctx;

        // Setup input parameters for selected device
        var input_params: c.PaStreamParameters = undefined;
        input_params.device = input_device;
        input_params.channelCount = 1; // Mono input
        input_params.sampleFormat = c.paFloat32;
        input_params.suggestedLatency = 0.01; // 10ms for low latency
        input_params.hostApiSpecificStreamInfo = null;

        // Setup output parameters for selected device
        var output_params: c.PaStreamParameters = undefined;
        output_params.device = output_device;
        output_params.channelCount = 1; // Mono output
        output_params.sampleFormat = c.paFloat32;
        output_params.suggestedLatency = 0.01; // 10ms for low latency
        output_params.hostApiSpecificStreamInfo = null;

        // Open stream with both input and output
        var stream: ?*c.PaStream = null;
        const err = c.Pa_OpenStream(
            &stream,
            &input_params,
            &output_params,
            @as(f64, @floatFromInt(sample_rate)),
            256, // frames per buffer
            c.paClipOff,
            realtimeCallback,
            ctx,
        );

        if (err != c.paNoError) {
            return error.PortAudioOpenStreamFailed;
        }

        self.stream = stream;

        // Start stream
        const err2 = c.Pa_StartStream(stream);
        if (err2 != c.paNoError) {
            return error.PortAudioStartStreamFailed;
        }

        std.debug.print("✓ Real-time processing started (input → distortion → cabinet → output)\n", .{});
        std.debug.print("Press Ctrl+C to stop...\n\n", .{});

        // Run for specified duration (or indefinitely if duration <= 0)
        if (duration_seconds > 0) {
            const sleep_duration: u64 = @as(u64, @intFromFloat(duration_seconds * 1_000_000_000));
            std.Thread.sleep(sleep_duration);
        } else {
            // Run indefinitely - sleep in 1 second intervals
            while (true) {
                std.Thread.sleep(1_000_000_000); // 1 second
            }
        }

        // Stop stream
        _ = c.Pa_StopStream(stream);
        std.debug.print("\n✓ Real-time processing stopped!\n", .{});
    }
};
