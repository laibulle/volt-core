const std = @import("std");
const audio = @import("../../audio.zig");

/// Simple convolver using overlap-add FFT-free convolution (time-domain)
/// For real-time performance with short IR, we use direct convolution
pub const Convolver = struct {
    ir_buffer: [*]const f32,
    ir_length: usize,
    allocator: std.mem.Allocator,
    overlap_buffer: [*]f32,
    overlap_length: usize,

    pub fn init(allocator: std.mem.Allocator, ir_buffer: audio.AudioBuffer) !Convolver {
        // Allocate overlap buffer for overlap-add (typically IR length)
        const ir_length = ir_buffer.samples.len / ir_buffer.channel_count;
        const overlap_buffer = try allocator.alloc(f32, ir_length);
        @memset(overlap_buffer, 0.0);

        return Convolver{
            .ir_buffer = ir_buffer.samples.ptr,
            .ir_length = ir_length,
            .allocator = allocator,
            .overlap_buffer = overlap_buffer.ptr,
            .overlap_length = ir_length,
        };
    }

    pub fn deinit(self: *Convolver) void {
        self.allocator.free(self.overlap_buffer[0..self.overlap_length]);
    }

    /// Process audio buffer with convolution
    pub fn processBuffer(self: *Convolver, buffer: *audio.AudioBuffer) void {
        // Simple direct convolution (time-domain)
        // For each output sample, convolve with the IR
        var output = self.allocator.alloc(f32, buffer.samples.len) catch return;
        defer self.allocator.free(output);

        @memset(output, 0.0);

        // Direct convolution: y[n] = sum(x[m] * h[n-m]) for m=0 to n
        for (0..buffer.samples.len) |n| {
            var sum: f32 = 0.0;
            const start = if (n < self.ir_length) 0 else n - self.ir_length + 1;
            const end = n + 1;

            for (start..end) |m| {
                if (m < buffer.samples.len and (n - m) < self.ir_length) {
                    sum += buffer.samples[m] * self.ir_buffer[n - m];
                }
            }

            output[n] = sum;
        }

        // Copy output back and normalize to prevent clipping
        var max_sample: f32 = 0.0;
        for (output) |sample| {
            if (sample > max_sample) max_sample = sample;
        }

        if (max_sample > 1.0) {
            const scale = 0.95 / max_sample;
            for (0..buffer.samples.len) |i| {
                buffer.samples[i] = output[i] * scale;
            }
        } else {
            @memcpy(buffer.samples, output);
        }
    }
};
