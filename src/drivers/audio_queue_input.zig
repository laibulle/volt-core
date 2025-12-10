const std = @import("std");
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("AudioToolbox/AudioToolbox.h");
});

const BUFFER_COUNT = 3;
const BUFFER_SIZE = 4096; // Samples per buffer

pub const AudioQueueInput = struct {
    queue: c.AudioQueueRef = null,
    allocator: std.mem.Allocator,

    // Input ring buffer - thread-safe storage for captured samples
    input_buffer: [BUFFER_SIZE * BUFFER_COUNT]f32 = undefined,
    write_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    read_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    samples_captured: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, device_id: c.AudioDeviceID) !Self {
        var self = Self{
            .allocator = allocator,
        };
        _ = device_id; // Note: Cannot set device on null-runloop audio queues

        // Create audio format for input (mono, 48kHz, float32)
        var format: c.AudioStreamBasicDescription = undefined;
        format.mSampleRate = 48000.0;
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
            return error.AudioQueueCreationFailed;
        }

        // Allocate and enqueue buffers
        for (0..BUFFER_COUNT) |_| {
            var buffer: c.AudioQueueBufferRef = null;
            err = c.AudioQueueAllocateBuffer(self.queue, BUFFER_SIZE * 4, &buffer);
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

    var debug_get_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

    pub fn getSample(self: *Self) ?f32 {
        const read_idx = self.read_pos.load(.seq_cst);
        const write_idx = self.write_pos.load(.seq_cst);

        const call_count = debug_get_count.fetchAdd(1, .monotonic);
        if (call_count % 50000 == 0) {
            std.debug.print("📖 getSample #{}: read={}, write={}, available={}, self={*}\n", .{ call_count, read_idx, write_idx, if (write_idx > read_idx) write_idx - read_idx else 0, self });
        }

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
