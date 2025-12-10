const std = @import("std");
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
});
const effects = @import("../effects.zig");
const AudioDriver = @import("../audio_driver.zig").AudioDriver;

var g_driver_instance: ?*CoreAudioDriver = null;

pub const CoreAudioDriver = struct {
    allocator: std.mem.Allocator,
    audio_unit: c.AudioUnit = undefined,
    is_running: bool = false,
    distortion: ?*effects.Distortion = null,
    convolver: ?*effects.Convolver = null,
    conv_state: [*]f32 = undefined,
    conv_state_len: usize = 0,
    conv_state_pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !AudioDriver {
        const driver = try allocator.create(CoreAudioDriver);
        driver.* = CoreAudioDriver{ .allocator = allocator };
        g_driver_instance = driver;

        return AudioDriver{
            .vtable = &vtable,
            .context = @ptrCast(driver),
        };
    }

    pub fn listDevices(self: *AudioDriver) void {
        const driver: *CoreAudioDriver = @ptrCast(@alignCast(self.context));
        _ = driver;

        std.debug.print("\nAvailable Audio Devices (CoreAudio - Native macOS):\n", .{});
        std.debug.print("==================================================\n\n", .{});
        std.debug.print("[0] Default Input\n", .{});
        std.debug.print("    Input Channels: 1\n", .{});
        std.debug.print("    Output Channels: 0\n\n", .{});
        std.debug.print("[1] Default Output\n", .{});
        std.debug.print("    Input Channels: 0\n", .{});
        std.debug.print("    Output Channels: 2\n\n", .{});
        std.debug.print("[Note: Using default system audio I/O devices]\n\n", .{});
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
        const driver: *CoreAudioDriver = @ptrCast(@alignCast(self.context));
        _ = input_device;
        _ = output_device;
        _ = buffer_size;

        driver.distortion = @ptrCast(@alignCast(distortion));
        driver.convolver = @ptrCast(@alignCast(convolver));

        // Allocate convolution state buffer
        const conv_state_len = driver.convolver.?.ir_length;
        const conv_state = try driver.allocator.alloc(f32, conv_state_len);
        @memset(conv_state, 0.0);

        driver.conv_state = conv_state.ptr;
        driver.conv_state_len = conv_state_len;
        driver.conv_state_pos = 0;

        // Create an Audio Unit for input/output
        var au_desc: c.AudioComponentDescription = undefined;
        au_desc.componentType = c.kAudioUnitType_Output;
        au_desc.componentSubType = c.kAudioUnitSubType_DefaultOutput;
        au_desc.componentManufacturer = c.kAudioUnitManufacturer_Apple;
        au_desc.componentFlags = 0;
        au_desc.componentFlagsMask = 0;

        const au_component = c.AudioComponentFindNext(null, &au_desc);
        if (au_component == null) {
            std.debug.print("Error: Could not find Audio Unit component\n", .{});
            return error.AudioUnitNotFound;
        }

        var err = c.AudioComponentInstanceNew(au_component, &driver.audio_unit);
        if (err != 0) {
            std.debug.print("Error creating Audio Unit instance: {d}\n", .{err});
            return error.AudioUnitInstanceCreationFailed;
        }

        // Enable input
        var enable_input: u32 = 1;
        err = c.AudioUnitSetProperty(
            driver.audio_unit,
            c.kAudioOutputUnitProperty_EnableIO,
            c.kAudioUnitScope_Input,
            1,
            &enable_input,
            @sizeOf(u32),
        );

        if (err != 0) {
            std.debug.print("Error enabling input: {d}\n", .{err});
            // Continue anyway - not all AU configurations need explicit input enable
        }

        // Set sample rate
        const sample_rate: f64 = 44100.0;
        var stream_format: c.AudioStreamBasicDescription = undefined;
        stream_format.mSampleRate = sample_rate;
        stream_format.mFormatID = c.kAudioFormatLinearPCM;
        stream_format.mFormatFlags = c.kAudioFormatFlagIsFloat | c.kAudioFormatFlagIsPacked;
        stream_format.mFramesPerPacket = 1;
        stream_format.mChannelsPerFrame = 1;
        stream_format.mBitsPerChannel = 32;
        stream_format.mBytesPerFrame = 4;
        stream_format.mBytesPerPacket = 4;

        err = c.AudioUnitSetProperty(
            driver.audio_unit,
            c.kAudioUnitProperty_StreamFormat,
            c.kAudioUnitScope_Output,
            0,
            &stream_format,
            @sizeOf(c.AudioStreamBasicDescription),
        );

        if (err != 0) {
            std.debug.print("Error setting stream format for output: {d}\n", .{err});
            return error.AudioUnitStreamFormatFailed;
        }

        // Set the render callback
        var callback: c.AURenderCallbackStruct = undefined;
        callback.inputProc = coreAudioCallback;
        callback.inputProcRefCon = driver;

        err = c.AudioUnitSetProperty(
            driver.audio_unit,
            c.kAudioUnitProperty_SetRenderCallback,
            c.kAudioUnitScope_Input,
            0,
            &callback,
            @sizeOf(c.AURenderCallbackStruct),
        );

        if (err != 0) {
            std.debug.print("Error setting render callback: {d}\n", .{err});
            return error.AudioUnitCallbackSetFailed;
        }

        // Initialize the Audio Unit
        err = c.AudioUnitInitialize(driver.audio_unit);
        if (err != 0) {
            std.debug.print("Error initializing Audio Unit: {d}\n", .{err});
            return error.AudioUnitInitializationFailed;
        }

        // Start the Audio Unit
        err = c.AudioOutputUnitStart(driver.audio_unit);
        if (err != 0) {
            std.debug.print("Error starting Audio Unit: {d}\n", .{err});
            return error.AudioUnitStartFailed;
        }

        driver.is_running = true;

        std.debug.print("✓ Real-time processing started via CoreAudio\n", .{});
        std.debug.print("Press Ctrl+C to stop...\n\n", .{});

        // Run until duration expires or Ctrl+C
        if (duration < 0) {
            // Run indefinitely
            var counter: u32 = 0;
            while (driver.is_running and counter < 4_294_967_295) {
                counter +|= 1;
            }
        } else {
            // Wait for duration
            var remaining_seconds = duration;
            while (remaining_seconds > 0 and driver.is_running) {
                remaining_seconds -= 0.1;
            }
            driver.is_running = false;
            _ = c.AudioOutputUnitStop(driver.audio_unit);
        }
    }

    pub fn stopProcessing(self: *AudioDriver) void {
        const driver: *CoreAudioDriver = @ptrCast(@alignCast(self.context));
        driver.is_running = false;
        if (driver.audio_unit != null) {
            _ = c.AudioOutputUnitStop(driver.audio_unit);
        }
    }

    pub fn deinit(self: *AudioDriver) void {
        const driver: *CoreAudioDriver = @ptrCast(@alignCast(self.context));
        if (driver.is_running) {
            if (driver.audio_unit != null) {
                _ = c.AudioOutputUnitStop(driver.audio_unit);
                _ = c.AudioComponentInstanceDispose(driver.audio_unit);
            }
        }
        driver.allocator.destroy(driver);
        g_driver_instance = null;
    }

    fn coreAudioCallback(
        in_ref_con: ?*anyopaque,
        io_action_flags: [*c]c.AudioUnitRenderActionFlags,
        in_time_stamp: [*c]const c.AudioTimeStamp,
        in_bus_number: u32,
        in_number_frames: u32,
        io_data: [*c]c.AudioBufferList,
    ) callconv(.c) c.OSStatus {
        _ = io_action_flags;
        _ = in_time_stamp;
        _ = in_bus_number;

        const driver: *CoreAudioDriver = @ptrCast(@alignCast(in_ref_con));

        if (driver.distortion == null or driver.convolver == null or io_data == null) {
            return 0;
        }

        const buffer_list = io_data;
        if (buffer_list.*.mNumberBuffers == 0) {
            return 0;
        }

        const audio_buffer = &buffer_list.*.mBuffers[0];
        const out = @as([*]f32, @ptrCast(@alignCast(audio_buffer.mData)));

        // Process each sample
        for (0..in_number_frames) |i| {
            var sample = out[i];

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

        return 0;
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
        driver.* = try CoreAudioDriver.init(allocator);
        return driver;
    }

    fn listDevicesVTable(driver: *AudioDriver) void {
        CoreAudioDriver.listDevices(driver);
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
        try CoreAudioDriver.startProcessing(driver, input_device, output_device, buffer_size, duration, distortion, convolver);
    }

    fn stopProcessingVTable(driver: *AudioDriver) void {
        CoreAudioDriver.stopProcessing(driver);
    }

    fn deinitVTable(driver: *AudioDriver) void {
        const actual_driver: *CoreAudioDriver = @ptrCast(@alignCast(driver.context));
        if (actual_driver.is_running) {
            if (actual_driver.audio_unit != null) {
                _ = c.AudioOutputUnitStop(actual_driver.audio_unit);
                _ = c.AudioComponentInstanceDispose(actual_driver.audio_unit);
            }
        }
        actual_driver.allocator.destroy(actual_driver);
    }
};
