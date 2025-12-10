const std = @import("std");
const c = @cImport({
    @cInclude("portaudio.h");
});
const effects = @import("../effects.zig");
const AudioDriver = @import("../audio_driver.zig").AudioDriver;

pub const PortAudioDriver = struct {
    allocator: std.mem.Allocator,
    stream: ?*c.PaStream = null,
    is_running: bool = false,
    distortion: ?*effects.Distortion = null,
    convolver: ?*effects.Convolver = null,
    conv_state: [*]f32 = undefined,
    conv_state_len: usize = 0,
    conv_state_pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !AudioDriver {
        const driver = try allocator.create(PortAudioDriver);
        driver.* = PortAudioDriver{ .allocator = allocator };

        // Initialize PortAudio
        const err = c.Pa_Initialize();
        if (err != c.paNoError) {
            return error.PortAudioInitFailed;
        }

        return AudioDriver{
            .vtable = &vtable,
            .context = @ptrCast(driver),
        };
    }

    pub fn listDevices(self: *AudioDriver) void {
        const driver: *PortAudioDriver = @ptrCast(@alignCast(self.context));
        _ = driver;

        const device_count = c.Pa_GetDeviceCount();

        std.debug.print("\nAvailable Audio Devices:\n", .{});
        std.debug.print("========================\n\n", .{});

        for (0..@as(usize, @intCast(device_count))) |i| {
            const device_info = c.Pa_GetDeviceInfo(@as(c.PaDeviceIndex, @intCast(i)));
            if (device_info == null) continue;

            const info = device_info.?;
            const name_ptr: [*:0]const u8 = @ptrCast(info.*.name);
            std.debug.print("[{d}] {s}\n", .{ i, std.mem.span(name_ptr) });
            std.debug.print("    Input Channels: {d}\n", .{info.*.maxInputChannels});
            std.debug.print("    Output Channels: {d}\n", .{info.*.maxOutputChannels});
            std.debug.print("    Default Sample Rate: {d} Hz\n", .{@as(i32, @intFromFloat(info.*.defaultSampleRate))});
            std.debug.print("    Host API: {d}\n\n", .{info.*.hostApi});
        }
    }

    pub fn startProcessing(
        self: *AudioDriver,
        input_device: i32,
        output_device: i32,
        buffer_size: usize,
        duration: f64,
        distortion: *anyopaque,
        convolver: *anyopaque,
    ) !void {
        const driver: *PortAudioDriver = @ptrCast(@alignCast(self.context));

        driver.distortion = @ptrCast(@alignCast(distortion));
        driver.convolver = @ptrCast(@alignCast(convolver));

        const sample_rate = 44100;

        // Allocate convolution state buffer
        const conv_state_len = driver.convolver.?.ir_length;
        const conv_state = try driver.allocator.alloc(f32, conv_state_len);
        @memset(conv_state, 0.0);

        driver.conv_state = conv_state.ptr;
        driver.conv_state_len = conv_state_len;
        driver.conv_state_pos = 0;

        // Setup input parameters
        var input_params: c.PaStreamParameters = undefined;
        input_params.device = @as(c.PaDeviceIndex, @intCast(input_device));
        input_params.channelCount = 1;
        input_params.sampleFormat = c.paFloat32;
        input_params.suggestedLatency = 0.001; // 1ms
        input_params.hostApiSpecificStreamInfo = null;

        // Setup output parameters
        var output_params: c.PaStreamParameters = undefined;
        output_params.device = @as(c.PaDeviceIndex, @intCast(output_device));
        output_params.channelCount = 1;
        output_params.sampleFormat = c.paFloat32;
        output_params.suggestedLatency = 0.001; // 1ms
        output_params.hostApiSpecificStreamInfo = null;

        // Open stream
        var stream: ?*c.PaStream = null;
        const err = c.Pa_OpenStream(
            &stream,
            &input_params,
            &output_params,
            @as(f64, @floatFromInt(sample_rate)),
            @as(c_ulong, buffer_size),
            c.paClipOff,
            portaudioCallback,
            @ptrCast(driver),
        );

        if (err != c.paNoError) {
            return error.PortAudioOpenStreamFailed;
        }

        driver.stream = stream;

        // Start stream
        const err2 = c.Pa_StartStream(stream);
        if (err2 != c.paNoError) {
            return error.PortAudioStartStreamFailed;
        }

        driver.is_running = true;

        std.debug.print("✓ Real-time processing started via PortAudio\n", .{});
        std.debug.print("Press Ctrl+C to stop...\n\n", .{});

        // Run until duration expires or Ctrl+C
        if (duration < 0) {
            // Run indefinitely - PortAudio stream is blocking, so we just wait
            var counter: u32 = 0;
            while (driver.is_running and counter < 4_294_967_295) {
                counter +|= 1; // Avoid infinite loop, let PortAudio handle I/O
            }
        } else {
            // Wait for duration (PortAudio stream blocks during playback)
            var remaining_seconds = duration;
            while (remaining_seconds > 0 and driver.is_running) {
                remaining_seconds -= 0.1; // Check every 100ms
            }
            driver.is_running = false;
            if (driver.stream) |s| {
                _ = c.Pa_StopStream(s);
            }
        }

        // Cleanup
        const err3 = c.Pa_CloseStream(stream);
        if (err3 != c.paNoError) {
            return error.PortAudioCloseStreamFailed;
        }

        driver.stream = null;
        driver.allocator.free(conv_state);
    }

    pub fn stopProcessing(self: *AudioDriver) void {
        const driver: *PortAudioDriver = @ptrCast(@alignCast(self.context));
        driver.is_running = false;
        if (driver.stream) |stream| {
            _ = c.Pa_StopStream(stream);
        }
    }

    pub fn deinit(self: *AudioDriver) void {
        const driver: *PortAudioDriver = @ptrCast(@alignCast(self.context));
        if (driver.is_running) {
            driver.stopProcessing();
        }
        _ = c.Pa_Terminate();
        driver.allocator.destroy(driver);
    }

    fn portaudioCallback(
        input: ?*const anyopaque,
        output: ?*anyopaque,
        frameCount: c_ulong,
        timeInfo: ?*const c.PaStreamCallbackTimeInfo,
        statusFlags: c.PaStreamCallbackFlags,
        userData: ?*anyopaque,
    ) callconv(.c) c_int {
        _ = timeInfo;
        _ = statusFlags;

        const driver: *PortAudioDriver = @ptrCast(@alignCast(userData));

        if (driver.distortion == null or driver.convolver == null) {
            return c.paContinue;
        }

        const in = @as([*]const f32, @ptrCast(@alignCast(input)));
        const out = @as([*]f32, @ptrCast(@alignCast(output)));

        for (0..frameCount) |i| {
            var sample = in[i];

            // Apply distortion
            const driven = sample * driver.distortion.?.drive;
            const soft_clipped = std.math.tanh(driven);
            sample = soft_clipped * driver.distortion.?.tone;

            // Apply convolution (10-tap FIR)
            var conv_out: f32 = 0.0;
            const ir_ptr = driver.convolver.?.ir_buffer;
            const max_taps = @min(10, driver.convolver.?.ir_length);
            for (0..max_taps) |tap| {
                const idx = (driver.conv_state_pos + tap) % driver.conv_state_len;
                conv_out += driver.conv_state[idx] * ir_ptr[tap];
            }

            driver.conv_state[driver.conv_state_pos] = sample;
            driver.conv_state_pos = (driver.conv_state_pos + 1) % driver.conv_state_len;

            // 100% wet output
            out[i] = std.math.clamp(conv_out, -1.0, 1.0);
        }

        return c.paContinue;
    }

    const vtable: AudioDriver.VTable = .{
        .init = initVTable,
        .list_devices = listDevicesVTable,
        .start_processing = startProcessingVTable,
        .stop_processing = stopProcessingVTable,
        .deinit = deinitVTable,
    };

    fn initVTable(allocator: std.mem.Allocator) !*AudioDriver {
        const driver = try allocator.create(AudioDriver);
        driver.* = try PortAudioDriver.init(allocator);
        return driver;
    }

    fn listDevicesVTable(driver: *AudioDriver) void {
        PortAudioDriver.listDevices(driver);
    }

    fn startProcessingVTable(
        driver: *AudioDriver,
        input_device: i32,
        output_device: i32,
        buffer_size: usize,
        duration: f64,
        distortion: *anyopaque,
        convolver: *anyopaque,
    ) !void {
        try PortAudioDriver.startProcessing(driver, input_device, output_device, buffer_size, duration, distortion, convolver);
    }

    fn stopProcessingVTable(driver: *AudioDriver) void {
        PortAudioDriver.stopProcessing(driver);
    }

    fn deinitVTable(driver: *AudioDriver) void {
        const actual_driver: *PortAudioDriver = @ptrCast(@alignCast(driver.context));
        if (actual_driver.is_running) {
            actual_driver.is_running = false;
            if (actual_driver.stream) |stream| {
                _ = c.Pa_StopStream(stream);
            }
        }
        _ = c.Pa_Terminate();
        actual_driver.allocator.destroy(actual_driver);
    }
};
