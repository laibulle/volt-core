const std = @import("std");
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
    @cInclude("unistd.h");
});
const effects = @import("../effects.zig");
const AudioDriver = @import("../audio_driver.zig").AudioDriver;

var g_driver_instance: ?*CoreAudioGraphDriver = null;

pub const CoreAudioGraphDriver = struct {
    allocator: std.mem.Allocator,
    audio_graph: c.AUGraph = null,
    input_unit: c.AudioUnit = null,
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

    pub fn startProcessing(
        self: *AudioDriver,
        input_device: i32,
        output_device: i32,
        buffer_size: usize,
        duration: f64,
        distortion: *anyopaque,
        convolver: *anyopaque,
    ) !void {
        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(self.context));
        _ = buffer_size; // Buffer size is managed by CoreAudio

        driver.distortion = @ptrCast(@alignCast(distortion));
        driver.convolver = @ptrCast(@alignCast(convolver));

        // Allocate convolution state buffer
        const conv_state_len = driver.convolver.?.ir_length;
        const conv_state = try driver.allocator.alloc(f32, conv_state_len);
        @memset(conv_state, 0.0);

        driver.conv_state = conv_state.ptr;
        driver.conv_state_len = conv_state_len;
        driver.conv_state_pos = 0;

        // Store device IDs (convert from i32)
        driver.input_device_id = @as(u32, @intCast(input_device));
        driver.output_device_id = @as(u32, @intCast(output_device));
        driver.sample_rate = 44100.0;

        // Create the Audio Unit Graph
        var err = c.NewAUGraph(&driver.audio_graph);
        if (err != 0) {
            std.debug.print("Error creating AUGraph: {d}\n", .{err});
            return error.AUGraphCreationFailed;
        }

        // Create Audio Component descriptions
        var input_desc: c.AudioComponentDescription = undefined;
        input_desc.componentType = c.kAudioUnitType_Output;
        input_desc.componentSubType = c.kAudioUnitSubType_HALOutput;
        input_desc.componentManufacturer = c.kAudioUnitManufacturer_Apple;
        input_desc.componentFlags = 0;
        input_desc.componentFlagsMask = 0;

        var output_desc: c.AudioComponentDescription = undefined;
        output_desc.componentType = c.kAudioUnitType_Output;
        output_desc.componentSubType = c.kAudioUnitSubType_DefaultOutput;
        output_desc.componentManufacturer = c.kAudioUnitManufacturer_Apple;
        output_desc.componentFlags = 0;
        output_desc.componentFlagsMask = 0;

        // Add nodes to graph
        var input_node: c.AUNode = 0;
        var output_node: c.AUNode = 0;

        err = c.AUGraphAddNode(driver.audio_graph, &input_desc, &input_node);
        if (err != 0) {
            std.debug.print("Error adding input node: {d}\n", .{err});
            return error.AUGraphNodeAddFailed;
        }

        err = c.AUGraphAddNode(driver.audio_graph, &output_desc, &output_node);
        if (err != 0) {
            std.debug.print("Error adding output node: {d}\n", .{err});
            return error.AUGraphNodeAddFailed;
        }

        // Open the graph
        err = c.AUGraphOpen(driver.audio_graph);
        if (err != 0) {
            std.debug.print("Error opening AUGraph: {d}\n", .{err});
            return error.AUGraphOpenFailed;
        }

        // Get the Audio Units from the nodes
        err = c.AUGraphNodeInfo(driver.audio_graph, input_node, null, &driver.input_unit);
        if (err != 0) {
            std.debug.print("Error getting input AU: {d}\n", .{err});
            return error.AUGraphNodeInfoFailed;
        }

        err = c.AUGraphNodeInfo(driver.audio_graph, output_node, null, &driver.output_unit);
        if (err != 0) {
            std.debug.print("Error getting output AU: {d}\n", .{err});
            return error.AUGraphNodeInfoFailed;
        }

        // Set the input device for the input AU
        err = c.AudioUnitSetProperty(
            driver.input_unit,
            c.kAudioOutputUnitProperty_CurrentDevice,
            c.kAudioUnitScope_Output,
            0,
            &driver.input_device_id,
            @sizeOf(c.AudioDeviceID),
        );
        if (err != 0) {
            std.debug.print("Error setting input device: {d}\n", .{err});
        }

        // Set the output device for the output AU
        err = c.AudioUnitSetProperty(
            driver.output_unit,
            c.kAudioOutputUnitProperty_CurrentDevice,
            c.kAudioUnitScope_Output,
            0,
            &driver.output_device_id,
            @sizeOf(c.AudioDeviceID),
        );
        if (err != 0) {
            std.debug.print("Error setting output device: {d}\n", .{err});
        }

        // Set stream format for both units
        var stream_format: c.AudioStreamBasicDescription = undefined;
        stream_format.mSampleRate = driver.sample_rate;
        stream_format.mFormatID = c.kAudioFormatLinearPCM;
        stream_format.mFormatFlags = c.kAudioFormatFlagIsFloat | c.kAudioFormatFlagIsPacked;
        stream_format.mFramesPerPacket = 1;
        stream_format.mChannelsPerFrame = 1;
        stream_format.mBitsPerChannel = 32;
        stream_format.mBytesPerFrame = 4;
        stream_format.mBytesPerPacket = 4;

        err = c.AudioUnitSetProperty(
            driver.input_unit,
            c.kAudioUnitProperty_StreamFormat,
            c.kAudioUnitScope_Output,
            0,
            &stream_format,
            @sizeOf(c.AudioStreamBasicDescription),
        );
        if (err != 0) {
            std.debug.print("Error setting input format: {d}\n", .{err});
        }

        err = c.AudioUnitSetProperty(
            driver.output_unit,
            c.kAudioUnitProperty_StreamFormat,
            c.kAudioUnitScope_Input,
            0,
            &stream_format,
            @sizeOf(c.AudioStreamBasicDescription),
        );
        if (err != 0) {
            std.debug.print("Error setting output format: {d}\n", .{err});
        }

        // Connect input unit output to output unit input
        err = c.AUGraphConnectNodeInput(driver.audio_graph, input_node, 0, output_node, 0);
        if (err != 0) {
            std.debug.print("Error connecting nodes: {d}\n", .{err});
            return error.AUGraphConnectionFailed;
        }

        // Set the render callback on the output unit to apply effects
        var callback: c.AURenderCallbackStruct = undefined;
        callback.inputProc = coreAudioGraphCallback;
        callback.inputProcRefCon = driver;

        err = c.AudioUnitSetProperty(
            driver.output_unit,
            c.kAudioUnitProperty_SetRenderCallback,
            c.kAudioUnitScope_Input,
            0,
            &callback,
            @sizeOf(c.AURenderCallbackStruct),
        );
        if (err != 0) {
            std.debug.print("Error setting output callback: {d}\n", .{err});
            return error.AudioUnitCallbackSetFailed;
        }

        // Initialize the graph
        err = c.AUGraphInitialize(driver.audio_graph);
        if (err != 0) {
            std.debug.print("Error initializing AUGraph: {d}\n", .{err});
            return error.AUGraphInitializeFailed;
        }

        // Start the graph
        err = c.AUGraphStart(driver.audio_graph);
        if (err != 0) {
            std.debug.print("Error starting AUGraph: {d}\n", .{err});
            return error.AUGraphStartFailed;
        }

        driver.is_running = true;

        std.debug.print("✓ Real-time processing started via CoreAudio (Audio Unit Graph)\n", .{});
        std.debug.print("Press Ctrl+C to stop...\n\n", .{});

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
            _ = c.AUGraphStop(driver.audio_graph);
        }
    }

    pub fn stopProcessing(self: *AudioDriver) void {
        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(self.context));
        driver.is_running = false;
        if (driver.audio_graph != null) {
            _ = c.AUGraphStop(driver.audio_graph);
            _ = c.AUGraphUninitialize(driver.audio_graph);
            _ = c.DisposeAUGraph(driver.audio_graph);
            driver.audio_graph = null;
        }
    }

    pub fn deinit(self: *AudioDriver) void {
        const driver: *CoreAudioGraphDriver = @ptrCast(@alignCast(self.context));

        // Stop and dispose audio graph if still running
        if (driver.audio_graph != null) {
            _ = c.AUGraphStop(driver.audio_graph);
            _ = c.AUGraphUninitialize(driver.audio_graph);
            _ = c.DisposeAUGraph(driver.audio_graph);
            driver.audio_graph = null;
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

fn startProcessingVTable(self: *AudioDriver, input_device: i32, output_device: i32, buffer_size: usize, duration: f64, distortion: *anyopaque, convolver: *anyopaque) !void {
    try CoreAudioGraphDriver.startProcessing(self, input_device, output_device, buffer_size, duration, distortion, convolver);
}

const vtable = listDevicesVTable;
