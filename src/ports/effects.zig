const std = @import("std");

/// Parameter type definitions
pub const ParameterType = enum {
    float,
    integer,
    boolean,
    enum_type,
};

/// Generic parameter with name and value
pub const Parameter = struct {
    name: []const u8,
    value: f32,
};

/// Available parameter descriptor
pub const ParameterDescriptor = struct {
    name: []const u8,
    param_type: ParameterType,
    default_value: f32,
    min_value: f32 = 0.0,
    max_value: f32 = 1.0,
    description: []const u8 = "",

    /// Check if a value is within the valid range
    pub fn isValid(self: *const ParameterDescriptor, value: f32) bool {
        return value >= self.min_value and value <= self.max_value;
    }

    /// Clamp a value to the valid range
    pub fn clamp(self: *const ParameterDescriptor, value: f32) f32 {
        if (value < self.min_value) return self.min_value;
        if (value > self.max_value) return self.max_value;
        return value;
    }
};

/// Effect metadata descriptor
pub const EffectDescriptor = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8 = "",
    version: []const u8 = "1.0.0",
    available_parameters: []const ParameterDescriptor,
};

/// Port: Effect Processor Interface
/// This defines the contract for audio effect processors.
/// Effect implementations should be placed in src/effects/ folder.
pub const EffectProcessor = struct {
    /// Process a single audio sample
    /// @param self - Pointer to the effect instance
    /// @param input - Input sample value (typically -1.0 to 1.0)
    /// @return Processed output sample
    process_fn: *const fn (self: *anyopaque, input: f32) f32,

    /// Effect instance data
    instance: *anyopaque,

    /// Effect descriptor (metadata)
    descriptor: *const EffectDescriptor,

    /// Current parameter values
    parameter_values: std.StringHashMap(f32),

    /// Process a single sample through this effect
    pub fn process(self: *const EffectProcessor, input: f32) f32 {
        return self.process_fn(self.instance, input);
    }
};

/// Port: Audio Buffer Interface
/// Represents a multi-channel audio buffer for batch processing
pub const AudioBuffer = struct {
    samples: []f32,
    channel_count: u32,
    sample_rate: u32,

    /// Get sample at specific frame and channel
    pub fn getSample(self: *const AudioBuffer, frame: usize, channel: u32) f32 {
        const index = frame * self.channel_count + channel;
        if (index < self.samples.len) {
            return self.samples[index];
        }
        return 0.0;
    }

    /// Set sample at specific frame and channel
    pub fn setSample(self: *AudioBuffer, frame: usize, channel: u32, value: f32) void {
        const index = frame * self.channel_count + channel;
        if (index < self.samples.len) {
            self.samples[index] = value;
        }
    }

    /// Get number of frames in buffer
    pub fn frameCount(self: *const AudioBuffer) usize {
        return self.samples.len / self.channel_count;
    }
};
