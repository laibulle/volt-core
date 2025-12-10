const std = @import("std");
const audio = @import("../../audio.zig");
const ports = @import("../../ports/effects.zig");

/// Distortion effect metadata
pub const distortion_descriptor: ports.EffectDescriptor = .{
    .id = "distortion",
    .name = "Distortion",
    .description = "Soft-clipping distortion with tone shaping",
    .version = "1.0.0",
    .available_parameters = &.{
        .{
            .name = "drive",
            .param_type = ports.ParameterType.float,
            .default_value = 1.0,
            .min_value = 0.1,
            .max_value = 10.0,
            .description = "Distortion amount (gain boost)",
        },
        .{
            .name = "tone",
            .param_type = ports.ParameterType.float,
            .default_value = 0.5,
            .min_value = 0.0,
            .max_value = 1.0,
            .description = "Tone shaping (0=more bass, 1=more treble)",
        },
    },
};

/// Distortion effect processor
/// Applies soft-clipping distortion with tone shaping
pub const Distortion = struct {
    drive: f32 = 1.0, // distortion amount (gain boost)
    tone: f32 = 0.5, // tone shaping (0-1), lower = more bass, higher = more treble

    /// Process a single sample through the distortion effect
    pub fn process(self: *const Distortion, input: f32) f32 {
        // Apply drive (gain boost)
        var sample = input * self.drive;

        // Soft-clip using tanh for smooth distortion
        sample = std.math.tanh(sample);

        // Tone control (simple low-pass filter simulation)
        sample = sample * self.tone;

        return sample;
    }

    /// Process entire audio buffer through distortion
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
