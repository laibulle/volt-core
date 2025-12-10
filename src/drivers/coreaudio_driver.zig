const std = @import("std");
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
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
    phase: f64 = 0.0,
    sample_rate: f64 = 44100.0,

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

        // Get system object
        const system_object = c.kAudioObjectSystemObject;

        // Get the size of the device list
        var property_address: c.AudioObjectPropertyAddress = undefined;
        property_address.mSelector = c.kAudioHardwarePropertyDevices;
        property_address.mScope = c.kAudioObjectPropertyScopeGlobal;
        property_address.mElement = c.kAudioObjectPropertyElementMaster;

        var devices_size: u32 = 0;
        var err = c.AudioObjectGetPropertyDataSize(
            system_object,
            &property_address,
            0,
            null,
            &devices_size,
        );

        if (err != 0) {
            std.debug.print("Error getting device list size: {d}\n", .{err});
            return;
        }

        const device_count = devices_size / @sizeOf(c.AudioDeviceID);
        if (device_count == 0) {
            std.debug.print("No audio devices found\n\n", .{});
            return;
        }

        // Allocate space for device list
        const devices = std.heap.page_allocator.alloc(c.AudioDeviceID, device_count) catch {
            std.debug.print("Error allocating device list\n", .{});
            return;
        };
        defer std.heap.page_allocator.free(devices);

        // Get the device list
        err = c.AudioObjectGetPropertyData(
            system_object,
            &property_address,
            0,
            null,
            &devices_size,
            devices.ptr,
        );

        if (err != 0) {
            std.debug.print("Error getting device list: {d}\n", .{err});
            return;
        }

        // Enumerate each device
        for (devices, 0..) |device_id, i| {
            // Get device name
            property_address.mSelector = c.kAudioObjectPropertyName;
            var name_cfstring: ?*anyopaque = null;
            var name_cfstring_size: u32 = @sizeOf(?*anyopaque);

            err = c.AudioObjectGetPropertyData(
                device_id,
                &property_address,
                0,
                null,
                &name_cfstring_size,
                @ptrCast(&name_cfstring),
            );

            var device_name: [256]u8 = undefined;
            @memset(&device_name, 0);

            if (err == 0 and name_cfstring != null) {
                // Convert CFStringRef to C string
                const cfstring_ref: c.CFStringRef = @ptrCast(@alignCast(name_cfstring));
                const got_string = c.CFStringGetCString(cfstring_ref, @ptrCast(&device_name), device_name.len, c.kCFStringEncodingUTF8);
                if (got_string == 0) {
                    _ = std.fmt.bufPrint(&device_name, "Device 0x{x}", .{device_id}) catch {};
                }
            } else {
                _ = std.fmt.bufPrint(&device_name, "Device 0x{x}", .{device_id}) catch {};
            }

            // Get input channels
            property_address.mSelector = c.kAudioDevicePropertyStreamConfiguration;
            property_address.mScope = c.kAudioDevicePropertyScopeInput;
            var input_buflist_size: u32 = 0;

            _ = c.AudioObjectGetPropertyDataSize(
                device_id,
                &property_address,
                0,
                null,
                &input_buflist_size,
            );

            var input_channels: u32 = 0;
            if (input_buflist_size > 0) {
                input_channels = input_buflist_size / @sizeOf(c.AudioBuffer);
            }

            // Get output channels
            property_address.mScope = c.kAudioDevicePropertyScopeOutput;
            var output_buflist_size: u32 = 0;

            _ = c.AudioObjectGetPropertyDataSize(
                device_id,
                &property_address,
                0,
                null,
                &output_buflist_size,
            );

            var output_channels: u32 = 0;
            if (output_buflist_size > 0) {
                output_channels = output_buflist_size / @sizeOf(c.AudioBuffer);
            }

            // Get nominal sample rate
            property_address.mSelector = c.kAudioDevicePropertyNominalSampleRate;
            property_address.mScope = c.kAudioObjectPropertyScopeGlobal;
            var sample_rate: f64 = 0.0;
            var sample_rate_size: u32 = @sizeOf(f64);

            err = c.AudioObjectGetPropertyData(
                device_id,
                &property_address,
                0,
                null,
                &sample_rate_size,
                &sample_rate,
            );

            std.debug.print("[{d}] {s}\n", .{ i, std.mem.sliceTo(&device_name, 0) });
            std.debug.print("    Input Channels: {d}\n", .{input_channels});
            std.debug.print("    Output Channels: {d}\n", .{output_channels});
            if (err == 0) {
                std.debug.print("    Sample Rate: {d:.0} Hz\n", .{sample_rate});
            }
            std.debug.print("    Device ID: 0x{x}\n\n", .{device_id});
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

        // Enable input on the input bus (element 1)
        // Note: These may fail on default output unit - that's okay
        var enable_input: u32 = 1;
        _ = c.AudioUnitSetProperty(
            driver.audio_unit,
            c.kAudioOutputUnitProperty_EnableIO,
            c.kAudioUnitScope_Input,
            1,
            &enable_input,
            @sizeOf(u32),
        );

        // Enable output on the output bus (element 0)
        var enable_output: u32 = 1;
        _ = c.AudioUnitSetProperty(
            driver.audio_unit,
            c.kAudioOutputUnitProperty_EnableIO,
            c.kAudioUnitScope_Output,
            0,
            &enable_output,
            @sizeOf(u32),
        );

        // Set sample rate
        const sample_rate: f64 = 44100.0;
        driver.sample_rate = sample_rate;
        var stream_format: c.AudioStreamBasicDescription = undefined;
        stream_format.mSampleRate = sample_rate;
        stream_format.mFormatID = c.kAudioFormatLinearPCM;
        stream_format.mFormatFlags = c.kAudioFormatFlagIsFloat | c.kAudioFormatFlagIsPacked;
        stream_format.mFramesPerPacket = 1;
        stream_format.mChannelsPerFrame = 1;
        stream_format.mBitsPerChannel = 32;
        stream_format.mBytesPerFrame = 4;
        stream_format.mBytesPerPacket = 4;

        // For DefaultOutput unit, set format on Input scope (this is where we process audio)
        err = c.AudioUnitSetProperty(
            driver.audio_unit,
            c.kAudioUnitProperty_StreamFormat,
            c.kAudioUnitScope_Input,
            0,
            &stream_format,
            @sizeOf(c.AudioStreamBasicDescription),
        );

        if (err != 0) {
            std.debug.print("Error setting stream format for input: {d}\n", .{err});
            return error.AudioUnitStreamFormatFailed;
        }

        // Set the render callback on the input bus
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
            // Run indefinitely - just yield to the OS
            while (driver.is_running) {
                // Small delay to avoid busy loop
                var i: u64 = 0;
                while (i < 10_000_000) : (i += 1) {}
            }
        } else {
            // Wait for duration
            var remaining_seconds = duration;
            while (remaining_seconds > 0 and driver.is_running) {
                var i: u64 = 0;
                while (i < 10_000_000) : (i += 1) {}
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

        // Free convolution state buffer
        if (driver.conv_state != null and driver.conv_state_len > 0) {
            const conv_state_slice = driver.conv_state[0..driver.conv_state_len];
            driver.allocator.free(conv_state_slice);
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

        // Generate a test tone at 440 Hz to verify audio output is working
        const frequency: f64 = 440.0;
        const two_pi = 2.0 * std.math.pi;
        const phase_increment = frequency / driver.sample_rate;

        // Process each sample
        for (0..in_number_frames) |i| {
            // Generate test tone
            var sample: f64 = @sin(driver.phase * two_pi) * 0.2;
            driver.phase += phase_increment;
            if (driver.phase >= 1.0) {
                driver.phase -= 1.0;
            }

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

            driver.conv_state[driver.conv_state_pos] = @as(f32, @floatCast(sample));
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
