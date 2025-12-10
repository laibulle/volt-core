const std = @import("std");
const audio = @import("audio.zig");

pub const Distortion = struct {
    drive: f32 = 1.0, // distortion amount
    tone: f32 = 0.5,  // tone shaping (0-1)    

    pub fn process(self: *const Distortion, input: f32) f32 {
        // Apply drive (gain boost)
        var sample = input * self.drive;

        // Soft-clip using tanh for smooth distortion
        sample = std.math.tanh(sample);

        // Tone control (simple low-pass filter simulation)
        // Lower values = more bass, higher values = more treble
        sample = sample * self.tone;

        return sample;
    }

    pub fn processBuffer(self: *const Distortion, buffer: *audio.AudioBuffer) void {
        const sample_count = buffer.samples.len / buffer.channel_count;
        for (0..sample_count) |i| {
            for (0..buffer.channel_count) |ch| {
                const input = buffer.getSample(i, @as(u32, @intCast(ch)));
                const output = self.process(input);
                buffer.setSample(i, @as(u32, @intCast(ch)), output);
            }
        }
    }
};

pub const EffectChain = struct {
    effects: std.ArrayList(*const anyopaque),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EffectChain {
        return EffectChain{
            .effects = std.ArrayList(*const anyopaque).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EffectChain) void {
        self.effects.deinit();
    }

    pub fn addDistortion(self: *EffectChain, distortion: *const Distortion) !void {
        try self.effects.append(@ptrCast(distortion));
    }
};
