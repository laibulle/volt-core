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
    drive: f32,
    tone: f32,

    /// Initialize distortion with default parameters
    pub fn init() Distortion {
        return .{
            .drive = distortion_descriptor.available_parameters[0].default_value,
            .tone = distortion_descriptor.available_parameters[1].default_value,
        };
    }

    /// Initialize distortion with custom parameters
    pub fn initWithParams(params: []const ports.Parameter) Distortion {
        var self = Distortion{
            .drive = distortion_descriptor.available_parameters[0].default_value,
            .tone = distortion_descriptor.available_parameters[1].default_value,
        };

        for (params) |param| {
            _ = self.setParameter(param.name, param.value);
        }

        return self;
    }

    /// Set a parameter value by name
    pub fn setParameter(self: *Distortion, name: []const u8, value: f32) bool {
        if (std.mem.eql(u8, name, "drive")) {
            self.drive = distortion_descriptor.available_parameters[0].clamp(value);
            return true;
        } else if (std.mem.eql(u8, name, "tone")) {
            self.tone = distortion_descriptor.available_parameters[1].clamp(value);
            return true;
        }
        return false;
    }

    /// Get a parameter value by name
    pub fn getParameter(self: *const Distortion, name: []const u8) ?f32 {
        if (std.mem.eql(u8, name, "drive")) {
            return self.drive;
        } else if (std.mem.eql(u8, name, "tone")) {
            return self.tone;
        }
        return null;
    }

    /// Process entire audio buffer through distortion
    pub fn processBuffer(self: *const Distortion, buffer: *audio.AudioBuffer) void {
        const sample_count = buffer.samples.len / buffer.channel_count;
        for (0..sample_count) |i| {
            for (0..buffer.channel_count) |ch| {
                var sample = buffer.getSample(i, @as(u32, @intCast(ch)));

                // Apply drive (gain boost)
                sample = sample * self.drive;

                // Soft-clip using tanh for smooth distortion
                sample = std.math.tanh(sample);

                // Tone control (simple low-pass filter simulation)
                sample = sample * self.tone;

                buffer.setSample(i, @as(u32, @intCast(ch)), sample);
            }
        }
    }
};
