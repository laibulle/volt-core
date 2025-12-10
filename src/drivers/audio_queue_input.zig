const std = @import("std");
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
});

const AUDIO_QUEUE_BUFFER_COUNT = 4; // Number of Audio Queue buffers (affects OS latency)
const RING_BUFFER_SIZE_MS = 32; // Ring buffer size in milliseconds (affects stability vs latency)
const DEFAULT_BUFFER_SIZE = 512; // Fallback if we can't query device

// Helper function to get device buffer size (frames per I/O cycle)
fn getDeviceBufferSize(device_id: c.AudioDeviceID) u32 {
    const kAudioDevicePropertyBufferFrameSize: u32 = 0x6673697a; // 'fsiz'
    var buffer_size: u32 = 32; // Default fallback matching typical size 32
    var size: u32 = @sizeOf(u32);

    const err = c.AudioObjectGetPropertyData(
        device_id,
        &c.AudioObjectPropertyAddress{
            .mSelector = kAudioDevicePropertyBufferFrameSize,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        },
        0,
        null,
        &size,
        @ptrCast(&buffer_size),
    );

    if (err != 0) {
        std.debug.print("Warning: Could not get device buffer size, using 32\n", .{});
        return 32;
    }

    // Use the device's actual buffer size
    std.debug.print("🔧 Device buffer size: {d} frames\n", .{buffer_size});
    return buffer_size;
}

// Helper function to get device sample rate
fn getDeviceSampleRate(device_id: c.AudioDeviceID) f64 {
    const kAudioDevicePropertyNominalSampleRate: u32 = 0x6e737274; // 'nsrt'
    var sample_rate: f64 = 48000.0; // Default fallback
    var size: u32 = @sizeOf(f64);

    const err = c.AudioObjectGetPropertyData(
        device_id,
        &c.AudioObjectPropertyAddress{
            .mSelector = kAudioDevicePropertyNominalSampleRate,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        },
        0,
        null,
        &size,
        @ptrCast(&sample_rate),
    );

    if (err != 0) {
        std.debug.print("Warning: Could not get device sample rate, using 48kHz\n", .{});
        return 48000.0;
    }

    return sample_rate;
}

// Helper function to get device UID string (required by Audio Queue)
fn getDeviceUID(device_id: c.AudioDeviceID) !?c.CFStringRef {
    const kAudioDevicePropertyDeviceUID: u32 = 0x75696420; // 'uid '
    var uid: c.CFStringRef = null;
    var size: u32 = @sizeOf(c.CFStringRef);

    const err = c.AudioObjectGetPropertyData(
        device_id,
        &c.AudioObjectPropertyAddress{
            .mSelector = kAudioDevicePropertyDeviceUID,
            .mScope = c.kAudioObjectPropertyScopeGlobal,
            .mElement = c.kAudioObjectPropertyElementMain,
        },
        0,
        null,
        &size,
        @ptrCast(&uid),
    );

    if (err != 0) {
        std.debug.print("Error getting device UID for 0x{x}: {}\n", .{ device_id, err });
        return null;
    }

    return uid;
}
pub const AudioQueueInput = struct {
    queue: c.AudioQueueRef = null,
    allocator: std.mem.Allocator,
    buffer_size: u32, // Device buffer size

    // Input ring buffer - dynamically allocated based on device
    input_buffer: []f32,
    write_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    read_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    samples_captured: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, device_id: c.AudioDeviceID) !Self {
        // Query device configuration
        const device_buffer_size = getDeviceBufferSize(device_id);
        const device_sample_rate = getDeviceSampleRate(device_id);

        // Force 44.1kHz for now (Scarlett actual sample rate)
        const use_sample_rate: f64 = 44100.0;

        std.debug.print("🎵 Audio Queue INPUT: buffer={d} frames, device reports {d:.0} Hz, using {d:.0} Hz (device 0x{x})\n", .{ device_buffer_size, device_sample_rate, use_sample_rate, device_id });

        // Calculate ring buffer size based on desired latency in milliseconds
        const samples_per_ms = @as(u32, @intFromFloat(use_sample_rate / 1000.0));
        const ring_buffer_size = samples_per_ms * RING_BUFFER_SIZE_MS;
        const input_buffer = try allocator.alloc(f32, ring_buffer_size);
        @memset(input_buffer, 0.0);

        std.debug.print("🔧 Ring buffer: {d} samples ({d}ms at {d:.0}Hz)\n", .{ ring_buffer_size, RING_BUFFER_SIZE_MS, use_sample_rate });

        var self = Self{
            .allocator = allocator,
            .buffer_size = device_buffer_size,
            .input_buffer = input_buffer,
        };

        // Create audio format for input (mono, 44.1kHz, float32)
        var format: c.AudioStreamBasicDescription = undefined;
        format.mSampleRate = use_sample_rate;
        format.mFormatID = c.kAudioFormatLinearPCM;
        format.mFormatFlags = c.kAudioFormatFlagIsFloat | c.kAudioFormatFlagIsPacked;
        format.mBytesPerPacket = 4; // 32-bit float
        format.mFramesPerPacket = 1;
        format.mBytesPerFrame = 4;
        format.mChannelsPerFrame = 1;
        format.mBitsPerChannel = 32;
        format.mReserved = 0;

        // Create a global context that points to self
        // We need to use a static/global to pass data to the C callback
        g_input_instance = &self;

        var err = c.AudioQueueNewInput(
            &format,
            audioQueueInputCallback,
            null, // We'll use global instance instead
            null, // Use default run loop
            null, // Use default run loop mode
            0, // Flags
            &self.queue,
        );

        if (err != 0) {
            std.debug.print("Error creating audio queue: {}\n", .{err});
            allocator.free(input_buffer);
            return error.AudioQueueCreationFailed;
        }

        // Verify the actual format Audio Queue is using
        var actual_format: c.AudioStreamBasicDescription = undefined;
        var format_size: u32 = @sizeOf(c.AudioStreamBasicDescription);
        const kAudioQueueProperty_StreamDescription: u32 = 0x61717364; // 'aqsd'
        err = c.AudioQueueGetProperty(
            self.queue,
            kAudioQueueProperty_StreamDescription,
            &actual_format,
            &format_size,
        );
        if (err == 0) {
            std.debug.print("🔍 Audio Queue ACTUAL sample rate: {d} Hz (after creation)\n", .{actual_format.mSampleRate});
            if (actual_format.mSampleRate != use_sample_rate) {
                std.debug.print("⚠️  WARNING: Sample rate mismatch! Requested {d}, got {d}\n", .{ use_sample_rate, actual_format.mSampleRate });
            }
        }

        // Set the specific input device (Scarlett instead of default Mac mic)
        const kAudioQueueProperty_CurrentDevice: u32 = 0x61716364; // 'aqcd'
        const device_uid = try getDeviceUID(device_id);
        defer if (device_uid) |uid| c.CFRelease(uid);

        if (device_uid) |uid| {
            err = c.AudioQueueSetProperty(
                self.queue,
                kAudioQueueProperty_CurrentDevice,
                @ptrCast(&uid),
                @sizeOf(@TypeOf(uid)),
            );
            if (err != 0) {
                std.debug.print("Warning: Could not set Audio Queue device to 0x{x}: error {}\n", .{ device_id, err });
            } else {
                std.debug.print("✓ Audio Queue using device 0x{x}\n", .{device_id});
            }
        }

        // Allocate and enqueue Audio Queue buffers (independent of ring buffer size)
        for (0..AUDIO_QUEUE_BUFFER_COUNT) |_| {
            var buffer: c.AudioQueueBufferRef = null;
            err = c.AudioQueueAllocateBuffer(self.queue, device_buffer_size * @sizeOf(f32), &buffer);
            if (err != 0) {
                std.debug.print("Error allocating audio queue buffer: {}\n", .{err});
                return error.BufferAllocationFailed;
            }

            err = c.AudioQueueEnqueueBuffer(self.queue, buffer, 0, null);
            if (err != 0) {
                std.debug.print("Error enqueuing audio queue buffer: {}\n", .{err});
                return error.EnqueueFailed;
            }
        }

        // Start the queue
        err = c.AudioQueueStart(self.queue, null);
        if (err != 0) {
            std.debug.print("Error starting audio queue: {}\n", .{err});
            return error.StartFailed;
        }

        std.debug.print("✓ Audio input queue initialized\n", .{});
        return self;
    }

    pub fn getSample(self: *Self) ?f32 {
        const read_idx = self.read_pos.load(.seq_cst);
        const write_idx = self.write_pos.load(.seq_cst);

        if (read_idx == write_idx) {
            return null; // No data available
        }

        const idx = read_idx % self.input_buffer.len;
        const sample = self.input_buffer[idx];
        self.read_pos.store(read_idx + 1, .seq_cst);
        return sample;
    }
    var debug_write_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

    pub fn writeSample(self: *Self, sample: f32) void {
        const write_idx = self.write_pos.load(.seq_cst);
        const idx = write_idx % self.input_buffer.len;
        self.input_buffer[idx] = sample;
        self.write_pos.store(write_idx + 1, .seq_cst);

        const call_count = debug_write_count.fetchAdd(1, .monotonic);
        if (call_count % 50000 == 0) {
            const read_idx = self.read_pos.load(.seq_cst);
            std.debug.print("📝 writeSample #{}: write={}, read={}, self={*}\n", .{ call_count, write_idx + 1, read_idx, self });
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.queue != null) {
            _ = c.AudioQueueStop(self.queue, @as(c.Boolean, 1));
            _ = c.AudioQueueDispose(self.queue, @as(c.Boolean, 1));
        }
        g_input_instance = null;
    }

    /// Update the global instance pointer to point to this instance
    /// MUST be called after copying AudioQueueInput to a new location (e.g., heap allocation)
    pub fn updateGlobalInstance(self: *Self) void {
        g_input_instance = self;
    }
};

var g_input_instance: ?*AudioQueueInput = null;

fn audioQueueInputCallback(
    _: ?*anyopaque,
    _: c.AudioQueueRef,
    buffer: c.AudioQueueBufferRef,
    _: [*c]const c.AudioTimeStamp,
    inNumberPackets: u32,
    _: [*c]const c.AudioStreamPacketDescription,
) callconv(.c) void {
    if (g_input_instance) |self| {
        // Debug: Print when callback is first invoked
        const current_count = self.samples_captured.load(.monotonic);
        if (current_count == 0) {
            std.debug.print("✓ Audio Queue input callback started (receiving {} packets)\n", .{inNumberPackets});
        }

        // Extract samples from the buffer
        if (buffer.*.mAudioData) |data| {
            const samples = @as([*]f32, @ptrCast(@alignCast(data)))[0..inNumberPackets];
            var non_zero_count: usize = 0;
            for (samples) |sample| {
                self.writeSample(sample);
                self.samples_captured.store(current_count + 1, .monotonic);
                if (sample != 0.0 and (sample > 0.01 or sample < -0.01)) {
                    non_zero_count += 1;
                }
            }

            // Debug: Show if we're getting actual audio signal
            if (current_count < 50000 and non_zero_count > 100) {
                std.debug.print("✓ DETECTED AUDIO INPUT! {}/{} samples non-zero\n", .{ non_zero_count, inNumberPackets });
            }
        }

        // Re-enqueue the buffer for more input
        const queue = self.queue;
        _ = c.AudioQueueEnqueueBuffer(queue, buffer, 0, null);
    }
}
