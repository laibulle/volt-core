const std = @import("std");

pub const AudioBuffer = struct {
    samples: []f32,
    sample_rate: u32,
    channel_count: u32,

    pub fn init(allocator: std.mem.Allocator, sample_count: usize, channel_count: u32, sample_rate: u32) !AudioBuffer {
        const samples = try allocator.alloc(f32, sample_count * channel_count);
        return AudioBuffer{
            .samples = samples,
            .sample_rate = sample_rate,
            .channel_count = channel_count,
        };
    }

    pub fn deinit(self: *AudioBuffer, allocator: std.mem.Allocator) void {
        allocator.free(self.samples);
    }

    pub fn getSample(self: *const AudioBuffer, sample_idx: usize, channel: u32) f32 {
        if (channel < self.channel_count and sample_idx < self.samples.len / self.channel_count) {
            return self.samples[sample_idx * self.channel_count + channel];
        }
        return 0.0;
    }

    pub fn setSample(self: *AudioBuffer, sample_idx: usize, channel: u32, value: f32) void {
        if (channel < self.channel_count and sample_idx < self.samples.len / self.channel_count) {
            self.samples[sample_idx * self.channel_count + channel] = value;
        }
    }

    pub fn generateTestSignal(self: *AudioBuffer, frequency: f32) void {
        const sample_count = self.samples.len / self.channel_count;
        for (0..sample_count) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.sample_rate));
            const phase = 2.0 * std.math.pi * frequency * t;
            const value = std.math.sin(phase) * 0.5; // 0.5 amplitude to avoid clipping

            for (0..self.channel_count) |ch| {
                self.setSample(i, @as(u32, @intCast(ch)), value);
            }
        }
    }
};
