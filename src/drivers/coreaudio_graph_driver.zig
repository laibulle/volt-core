const std = @import("std");
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("unistd.h");
});
const effects = @import("../effects.zig");
const AudioDriver = @import("../audio_driver.zig").AudioDriver;
const AudioQueueInput = @import("audio_queue_input.zig").AudioQueueInput;

var g_driver_instance: ?*CoreAudioGraphDriver = null;

pub const CoreAudioGraphDriver = struct {
    allocator: std.mem.Allocator,
    audio_graph: c.AUGraph = null,
    input_unit: c.AudioUnit = null,
    mixer_unit: c.AudioUnit = null,
    output_unit: c.AudioUnit = null,
    is_running: bool = false,
    distortion: ?*effects.Distortion = null,
    convolver: ?*effects.Convolver = null,
    conv_state: [*]f32 = undefined,
    conv_state_len: usize = 0,
    conv_state_pos: usize = 0,
    sample_rate: f64 = 44100.0,
    input_device_id: c.AudioDeviceID = 0,
    output_device_id: c.AudioDeviceID = 0,
    input_queue: ?*AudioQueueInput = null,

    pub fn init(allocator: std.mem.Allocator) !AudioDriver {
        const driver = try allocator.create(CoreAudioGraphDriver);
        driver.* = CoreAudioGraphDriver{ .allocator = allocator };
        g_driver_instance = driver;

        return AudioDriver{
            .vtable = &vtable,
            .context = @ptrCast(driver),
        };
    }

    pub fn listDevices(self: *AudioDriver) void {
        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(self.context));
        _ = driver;

        std.debug.print("\nAvailable Audio Devices (CoreAudio - Native macOS):\n", .{});
        std.debug.print("==================================================\n\n", .{});

        // Get system object
        var property_address: c.AudioObjectPropertyAddress = undefined;
        property_address.mSelector = c.kAudioHardwarePropertyDevices;
        property_address.mScope = c.kAudioObjectPropertyScopeGlobal;
        property_address.mElement = 0;

        var devices_size: u32 = 0;
        var err = c.AudioObjectGetPropertyDataSize(
            c.kAudioObjectSystemObject,
            &property_address,
            0,
            null,
            &devices_size,
        );

        if (err != 0) {
            std.debug.print("Error getting device list size\n", .{});
            return;
        }

        const device_count = devices_size / @sizeOf(c.AudioDeviceID);

        // Allocate space for device list
        const devices = std.heap.page_allocator.alloc(c.AudioDeviceID, device_count) catch {
            std.debug.print("Error allocating device list\n", .{});
            return;
        };
        defer std.heap.page_allocator.free(devices);

        // Get the device list
        err = c.AudioObjectGetPropertyData(
            c.kAudioObjectSystemObject,
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

            // Get sample rate
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

    fn getDeviceIdByIndex(index: i32) !c.AudioDeviceID {
        if (index < 0) {
            return 0; // Default device
        }

        // Get system object
        var property_address: c.AudioObjectPropertyAddress = undefined;
        property_address.mSelector = c.kAudioHardwarePropertyDevices;
        property_address.mScope = c.kAudioObjectPropertyScopeGlobal;
        property_address.mElement = 0;

        var devices_size: u32 = 0;
        var err = c.AudioObjectGetPropertyDataSize(
            c.kAudioObjectSystemObject,
            &property_address,
            0,
            null,
            &devices_size,
        );

        if (err != 0) {
            return error.DeviceListFailed;
        }

        const device_count = devices_size / @sizeOf(c.AudioDeviceID);

        if (index >= device_count) {
            return error.InvalidDeviceIndex;
        }

        // Allocate space for device list
        const devices = std.heap.page_allocator.alloc(c.AudioDeviceID, device_count) catch {
            return error.AllocationFailed;
        };
        defer std.heap.page_allocator.free(devices);

        // Get the device list
        err = c.AudioObjectGetPropertyData(
            c.kAudioObjectSystemObject,
            &property_address,
            0,
            null,
            &devices_size,
            devices.ptr,
        );

        if (err != 0) {
            return error.DeviceListFailed;
        }

        return devices[@intCast(index)];
    }

    pub fn startProcessing(
        self: *AudioDriver,
        input_device: i32,
        output_device: i32,
        buffer_size: usize,
        sample_rate: u32,
        duration: f64,
        distortion: *anyopaque,
        convolver: *anyopaque,
    ) !void {
        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(self.context));
        _ = buffer_size; // Buffer size is managed by CoreAudio

        // Store sample rate for use in callbacks
        driver.sample_rate = @floatFromInt(sample_rate);

        driver.distortion = @ptrCast(@alignCast(distortion));
        driver.convolver = @ptrCast(@alignCast(convolver));

        // Convert device indices to actual device IDs
        driver.input_device_id = try getDeviceIdByIndex(input_device);
        driver.output_device_id = try getDeviceIdByIndex(output_device);

        std.debug.print("Using input device ID: 0x{x}\n", .{driver.input_device_id});
        std.debug.print("Using output device ID: 0x{x}\n", .{driver.output_device_id});

        // Allocate convolution state buffer
        const conv_state_len = driver.convolver.?.ir_length;
        const conv_state = try driver.allocator.alloc(f32, conv_state_len);
        @memset(conv_state, 0.0);
        driver.conv_state = conv_state.ptr;
        driver.conv_state_len = conv_state_len;
        driver.conv_state_pos = 0;

        var err: c.OSStatus = 0;

        // Create a simple HAL Output unit with callback (no graph)
        var hal_output_desc: c.AudioComponentDescription = undefined;
        hal_output_desc.componentType = c.kAudioUnitType_Output;
        hal_output_desc.componentSubType = c.kAudioUnitSubType_HALOutput;
        hal_output_desc.componentManufacturer = c.kAudioUnitManufacturer_Apple;
        hal_output_desc.componentFlags = 0;
        hal_output_desc.componentFlagsMask = 0;

        const hal_component = c.AudioComponentFindNext(null, &hal_output_desc);
        if (hal_component == null) {
            std.debug.print("Error: HAL Output component not found\n", .{});
            return error.AudioComponentNotFound;
        }

        err = c.AudioComponentInstanceNew(hal_component, &driver.input_unit);
        if (err != 0) {
            std.debug.print("Error creating HAL Output unit: {d}\n", .{err});
            return error.AudioUnitCreationFailed;
        }

        driver.output_unit = driver.input_unit;

        // Disable input scope passthrough (we don't want dry signal)
        var enable: u32 = 0;
        err = c.AudioUnitSetProperty(
            driver.input_unit,
            c.kAudioOutputUnitProperty_EnableIO,
            c.kAudioUnitScope_Input,
            1, // input bus
            &enable,
            @sizeOf(u32),
        );
        if (err != 0) {
            std.debug.print("Warning: disabling input IO returned: {d}\n", .{err});
        }

        // Set input device (not needed since we disabled input passthrough, but kept for reference)
        // We're using Audio Queue for input capture instead
        if (false and driver.input_device_id != 0) {
            _ = c.AudioUnitSetProperty(
                driver.input_unit,
                c.kAudioOutputUnitProperty_CurrentDevice,
                c.kAudioUnitScope_Input,
                1,
                &driver.input_device_id,
                @sizeOf(c.AudioDeviceID),
            );
        }

        // Set stream format
        // Set stream format to match device capabilities
        // First get the device's native sample rate
        var device_sample_rate: f64 = 44100.0;
        var prop_address: c.AudioObjectPropertyAddress = undefined;
        prop_address.mSelector = c.kAudioDevicePropertyNominalSampleRate;
        prop_address.mScope = c.kAudioObjectPropertyScopeGlobal;
        prop_address.mElement = 0;

        var sample_rate_size: u32 = @sizeOf(f64);
        if (driver.output_device_id != 0) {
            _ = c.AudioObjectGetPropertyData(
                driver.output_device_id,
                &prop_address,
                0,
                null,
                &sample_rate_size,
                &device_sample_rate,
            );
        }

        std.debug.print("🎵 Output device sample rate: {d:.0} Hz (device 0x{x})\n", .{ device_sample_rate, driver.output_device_id });

        // Use the requested sample rate from CLI
        const target_sample_rate: f64 = @floatFromInt(sample_rate);
        if (driver.output_device_id != 0 and device_sample_rate != target_sample_rate) {
            prop_address.mSelector = c.kAudioDevicePropertyNominalSampleRate;
            err = c.AudioObjectSetPropertyData(
                driver.output_device_id,
                &prop_address,
                0,
                null,
                @sizeOf(f64),
                @ptrCast(&target_sample_rate),
            );
            if (err != 0) {
                std.debug.print("⚠️  Warning: Could not set output sample rate to {d}: error {d}\n", .{ target_sample_rate, err });
            } else {
                std.debug.print("✓ Set output device sample rate to {d:.0} Hz\n", .{target_sample_rate});
                device_sample_rate = target_sample_rate;
            }
        }

        // Set device buffer size to 32 frames for low latency
        const kAudioDevicePropertyBufferFrameSize: u32 = 0x6673697a; // 'fsiz'
        var desired_buffer_size: u32 = 32;
        if (driver.output_device_id != 0) {
            prop_address.mSelector = kAudioDevicePropertyBufferFrameSize;
            prop_address.mScope = c.kAudioObjectPropertyScopeGlobal;
            prop_address.mElement = 0;

            err = c.AudioObjectSetPropertyData(
                driver.output_device_id,
                &prop_address,
                0,
                null,
                @sizeOf(u32),
                &desired_buffer_size,
            );
            if (err != 0) {
                std.debug.print("⚠️  Warning: Could not set output device buffer size to {d}: error {d}\n", .{ desired_buffer_size, err });
            } else {
                std.debug.print("✓ Set output device buffer size to {d} frames\n", .{desired_buffer_size});
            }
        }

        // Also set input device buffer size
        if (driver.input_device_id != 0) {
            // Force input device sample rate to 44.1kHz FIRST
            var input_sample_rate: f64 = 0.0;
            _ = c.AudioObjectGetPropertyData(
                driver.input_device_id,
                &prop_address,
                0,
                null,
                &sample_rate_size,
                &input_sample_rate,
            );

            if (input_sample_rate != target_sample_rate) {
                prop_address.mSelector = c.kAudioDevicePropertyNominalSampleRate;
                err = c.AudioObjectSetPropertyData(
                    driver.input_device_id,
                    &prop_address,
                    0,
                    null,
                    @sizeOf(f64),
                    @ptrCast(&target_sample_rate),
                );
                if (err != 0) {
                    std.debug.print("⚠️  Warning: Could not set input sample rate to {d}: error {d}\n", .{ target_sample_rate, err });
                } else {
                    std.debug.print("✓ Set input device sample rate to {d:.0} Hz\n", .{target_sample_rate});
                }
            }

            // Now set buffer size
            prop_address.mSelector = kAudioDevicePropertyBufferFrameSize;
            err = c.AudioObjectSetPropertyData(
                driver.input_device_id,
                &prop_address,
                0,
                null,
                @sizeOf(u32),
                &desired_buffer_size,
            );
            if (err != 0) {
                std.debug.print("⚠️  Warning: Could not set input device buffer size to {d}: error {d}\n", .{ desired_buffer_size, err });
            } else {
                std.debug.print("✓ Set input device buffer size to {d} frames\n", .{desired_buffer_size});
            }
        }

        // Note: Format setting often fails on HALOutput units during active I/O.
        // CoreAudio will negotiate format automatically, so we just proceed.

        // Set the render callback on the OUTPUT bus to capture and process audio
        var callback: c.AURenderCallbackStruct = undefined;
        callback.inputProc = coreAudioSimpleCallback;
        callback.inputProcRefCon = driver;

        err = c.AudioUnitSetProperty(
            driver.input_unit,
            c.kAudioUnitProperty_SetRenderCallback,
            c.kAudioUnitScope_Output,
            0,
            &callback,
            @sizeOf(c.AURenderCallbackStruct),
        );
        if (err != 0) {
            std.debug.print("Error setting callback: {d}\n", .{err});
            return error.AudioUnitCallbackSetFailed;
        }

        // Initialize the unit
        err = c.AudioUnitInitialize(driver.input_unit);
        if (err != 0) {
            std.debug.print("Error initializing audio unit: {d}\n", .{err});
            return error.AudioUnitInitializeFailed;
        }

        // Start rendering
        err = c.AudioOutputUnitStart(driver.input_unit);
        if (err != 0) {
            std.debug.print("Error starting audio unit: {d}\n", .{err});
            return error.AudioUnitStartFailed;
        }

        driver.is_running = true;

        // Initialize input capture queue
        driver.input_queue = null;
        if (AudioQueueInput.init(driver.allocator, driver.input_device_id)) |input_queue| {
            const queue_ptr = try driver.allocator.create(AudioQueueInput);
            queue_ptr.* = input_queue;
            driver.input_queue = queue_ptr;

            // CRITICAL: Update global instance to point to heap-allocated copy
            // The Audio Queue callback uses g_input_instance which was set in init()
            // to point to the stack-allocated self, but we need it to point to the heap copy
            queue_ptr.updateGlobalInstance();
        } else |init_err| {
            std.debug.print("Warning: Could not initialize input queue: {}\n", .{init_err});
        }

        std.debug.print("✓ Real-time processing started via CoreAudio (HAL Output Unit)\n", .{});
        std.debug.print("Press Ctrl+C to stop...\n", .{});
        std.debug.print("\nDEBUG: Test tone output enabled at 0.7 amplitude\n", .{});
        std.debug.print("If no audio is heard:\n", .{});
        std.debug.print("  1. Check Scarlett 18i8 output knob (should NOT be all the way down)\n", .{});
        std.debug.print("  2. Check that monitor speakers are powered ON\n", .{});
        std.debug.print("  3. Run 'make run-list-devices' to verify Scarlett is device 0x74\n", .{});
        std.debug.print("  4. Try 'osascript -e \"set volume output volume 50\"' to set macOS volume\n\n", .{});

        // Run until duration expires or Ctrl+C
        if (duration < 0) {
            // Run indefinitely - use short sleeps for responsiveness to signals
            while (driver.is_running) {
                _ = c.usleep(100_000); // 100ms sleep
            }
        } else {
            // Wait for duration
            var remaining_seconds = duration;
            while (remaining_seconds > 0 and driver.is_running) {
                _ = c.usleep(100_000); // 100ms sleep
                remaining_seconds -= 0.1;
            }
            driver.is_running = false;
            _ = c.AudioOutputUnitStop(driver.input_unit);
        }
    }

    pub fn stopProcessing(self: *AudioDriver) void {
        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(self.context));
        driver.is_running = false;
        if (driver.input_unit != null) {
            _ = c.AudioOutputUnitStop(driver.input_unit);
        }
    }

    pub fn deinit(self: *AudioDriver) void {
        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(self.context));

        // Stop and cleanup input queue
        if (driver.input_queue) |queue| {
            queue.deinit();
            driver.input_queue = null;
        }

        // Stop and dispose audio unit
        if (driver.input_unit != null) {
            _ = c.AudioOutputUnitStop(driver.input_unit);
            _ = c.AudioUnitUninitialize(driver.input_unit);
            _ = c.AudioComponentInstanceDispose(driver.input_unit);
            driver.input_unit = null;
        }

        // Free convolution state buffer
        if (driver.conv_state_len > 0) {
            const conv_state_slice = driver.conv_state[0..driver.conv_state_len];
            driver.allocator.free(conv_state_slice);
        }

        driver.allocator.destroy(driver);
        g_driver_instance = null;
    }

    fn coreAudioGraphCallback(
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

        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(in_ref_con));

        if (driver.distortion == null or driver.convolver == null or io_data == null) {
            return 0;
        }

        const buffer_list = io_data;
        if (buffer_list.*.mNumberBuffers == 0) {
            return 0;
        }

        const audio_buffer = &buffer_list.*.mBuffers[0];
        const audio = @as([*]f32, @ptrCast(@alignCast(audio_buffer.mData)));

        // Process each sample - input is already in the buffer from the input unit
        for (0..in_number_frames) |i| {
            var sample: f64 = @as(f64, audio[i]);

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
            audio[i] = std.math.clamp(conv_out, -1.0, 1.0);
        }

        return 0;
    }

    fn coreAudioSimpleCallback(
        in_ref_con: ?*anyopaque,
        io_action_flags: [*c]c.AudioUnitRenderActionFlags,
        in_time_stamp: [*c]const c.AudioTimeStamp,
        in_bus_number: u32,
        in_number_frames: u32,
        io_data: [*c]c.AudioBufferList,
    ) callconv(.c) c.OSStatus {
        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(in_ref_con));

        // Debug: Count callbacks
        driver.conv_state_pos += 1;
        if (driver.conv_state_pos % 1500 == 0) { // ~31ms at 48kHz with 32-frame buffer
            std.debug.print("Render callback called (count={}), frames: {}, bus: {}\n", .{ driver.conv_state_pos, in_number_frames, in_bus_number });
        }

        // Only process the output bus
        if (in_bus_number != 0 or io_data == null or io_data.*.mNumberBuffers == 0) {
            return 0;
        }

        // Get the output buffer to fill
        const buffer_ptr = io_data.*.mBuffers[0].mData;
        if (buffer_ptr == null) {
            return 0;
        }

        const audio_ptr: [*]f32 = @ptrCast(@alignCast(buffer_ptr));
        const audio_out = audio_ptr[0..in_number_frames];

        // Check if the pre-render action indicates we should process input
        const preRenderFlag: c.AudioUnitRenderActionFlags = 0x04; // kAudioUnitRenderAction_PreRender
        if ((io_action_flags.* & preRenderFlag) != 0) {
            // Pre-render pass - just return 0 to allow the unit to process
            return 0;
        }

        // Pull input samples from the input bus using AudioUnitRender
        var input_buflist: c.AudioBufferList = undefined;
        input_buflist.mNumberBuffers = 1;
        input_buflist.mBuffers[0].mNumberChannels = 1;
        input_buflist.mBuffers[0].mDataByteSize = @as(u32, @intCast(in_number_frames * 4));

        var input_buffer: [4096]f32 = undefined;
        if (in_number_frames > input_buffer.len) {
            // Buffer too small, output silence
            @memset(audio_out, 0.0);
            return 0;
        }

        input_buflist.mBuffers[0].mData = @ptrCast(&input_buffer);

        // Render from input bus (bus 1 on HALOutput)
        var flags: c.AudioUnitRenderActionFlags = 0;
        const render_err = c.AudioUnitRender(
            driver.input_unit,
            &flags,
            in_time_stamp,
            1, // input bus
            in_number_frames,
            &input_buflist,
        );

        if (render_err != 0) {
            // AudioUnitRender cannot be used to pull input on output callback
            // Use input from Audio Queue instead
            const frequency = 220.0;
            const sample_rate = driver.sample_rate; // Use actual configured sample rate

            var input_sample_count: u32 = 0;
            var test_tone_count: u32 = 0;

            for (0..in_number_frames) |i| {
                if (driver.input_queue) |queue| {
                    if (queue.getSample()) |sample| {
                        input_buffer[i] = sample;
                        input_sample_count += 1;
                    } else {
                        // No input available - generate test tone
                        const t = @as(f64, @floatFromInt(driver.conv_state_pos + i));
                        const phase = @mod(t * frequency / sample_rate, 1.0);
                        const sample_test = if (phase < 0.5) @as(f32, 0.7) else @as(f32, -0.7);
                        input_buffer[i] = sample_test;
                        test_tone_count += 1;
                    }
                } else {
                    // No input queue - generate test tone
                    const t = @as(f64, @floatFromInt(driver.conv_state_pos + i));
                    const phase = @mod(t * frequency / sample_rate, 1.0);
                    const sample_test = if (phase < 0.5) @as(f32, 0.7) else @as(f32, -0.7);
                    input_buffer[i] = sample_test;
                    test_tone_count += 1;
                }
            }

            // Debug: Show if we're getting real input
            if ((driver.conv_state_pos / in_number_frames) % 1000 == 0) {
                if (input_sample_count > 0) {
                    std.debug.print("✓ Callback #{}: {}/{} guitar samples\n", .{ driver.conv_state_pos / in_number_frames, input_sample_count, in_number_frames });
                } else if (test_tone_count > 0) {
                    std.debug.print("⚠ Callback #{}: test tone ({} samples)\n", .{ driver.conv_state_pos / in_number_frames, test_tone_count });
                }
            }

            driver.conv_state_pos += in_number_frames;
        }

        // We have input samples - apply effects and output them
        const input_samples = input_buffer[0..in_number_frames];
        var max_input: f32 = 0.0;
        var max_output: f32 = 0.0;
        var non_zero_count: u32 = 0;

        for (input_samples, 0..) |sample, i| {
            // Track input level
            max_input = @max(max_input, @abs(sample));
            if (@abs(sample) > 0.001) non_zero_count += 1;

            // Apply distortion if available
            var processed = sample;
            if (driver.distortion) |dist| {
                processed = dist.process(sample);
            }

            // Clamp and output
            audio_out[i] = std.math.clamp(processed, -1.0, 1.0);
            max_output = @max(max_output, @abs(audio_out[i]));
        }

        return 0;
    }
};

const listDevicesVTable = AudioDriver.VTable{
    .init = initVTable,
    .list_devices = CoreAudioGraphDriver.listDevices,
    .start_processing = startProcessingVTable,
    .stop_processing = CoreAudioGraphDriver.stopProcessing,
    .deinit = CoreAudioGraphDriver.deinit,
};

fn initVTable(allocator: std.mem.Allocator) !*AudioDriver {
    const driver_on_heap = try std.heap.page_allocator.create(AudioDriver);
    driver_on_heap.* = try CoreAudioGraphDriver.init(allocator);
    return driver_on_heap;
}

fn startProcessingVTable(self: *AudioDriver, input_device: i32, output_device: i32, buffer_size: usize, sample_rate: u32, duration: f64, distortion: *anyopaque, convolver: *anyopaque) !void {
    try CoreAudioGraphDriver.startProcessing(self, input_device, output_device, buffer_size, sample_rate, duration, distortion, convolver);
}

const vtable = listDevicesVTable;
