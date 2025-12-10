const std = @import("std");

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
