const std = @import("std");
const audio = @import("../../audio.zig");
const ports = @import("../../ports/effects.zig");
const ir_loader_module = @import("../../ir_loader.zig");
const wav_loader_module = @import("../../wav_loader.zig");

/// Convolver effect metadata
pub const convolver_descriptor: ports.EffectDescriptor = .{
    .id = "convolver",
    .name = "Convolver (Cabinet/IR)",
    .description = "Impulse response convolution for cabinet emulation",
    .version = "1.0.0",
    .available_parameters = &.{
        .{
            .name = "dry_wet",
            .param_type = ports.ParameterType.float,
            .default_value = 1.0,
            .min_value = 0.0,
            .max_value = 1.0,
            .description = "Dry/Wet mix (0=dry, 1=wet)",
        },
    },
};

/// Convolver effect processor with IR loading
pub const Convolver = struct {
    ir_buffer: [*]const f32,
    ir_length: usize,
    allocator: std.mem.Allocator,
    overlap_buffer: [*]f32,
    overlap_length: usize,
    dry_wet: f32,

    /// Initialize convolver from IR file path
    pub fn initFromFile(allocator: std.mem.Allocator, ir_path: []const u8) !Convolver {
        const ir_loader = ir_loader_module.IRLoader.init(allocator);
        var ir_audio = try ir_loader.loadFile(ir_path);
        defer ir_audio.deinit(allocator);

        const ir_length = ir_audio.samples.len / ir_audio.channel_count;
        const overlap_buffer = try allocator.alloc(f32, ir_length);
        @memset(overlap_buffer, 0.0);

        // Keep IR buffer alive - we need to store the samples permanently
        const ir_samples = try allocator.dupe(f32, ir_audio.samples);

        return Convolver{
            .ir_buffer = ir_samples.ptr,
            .ir_length = ir_length,
            .allocator = allocator,
            .overlap_buffer = overlap_buffer.ptr,
            .overlap_length = ir_length,
            .dry_wet = convolver_descriptor.available_parameters[0].default_value,
        };
    }

    /// Initialize convolver from audio buffer
    pub fn init(allocator: std.mem.Allocator, ir_buffer: audio.AudioBuffer) !Convolver {
        const ir_length = ir_buffer.samples.len / ir_buffer.channel_count;
        const overlap_buffer = try allocator.alloc(f32, ir_length);
        @memset(overlap_buffer, 0.0);

        // Duplicate IR samples to keep them in memory
        const ir_samples = try allocator.dupe(f32, ir_buffer.samples);

        return Convolver{
            .ir_buffer = ir_samples.ptr,
            .ir_length = ir_length,
            .allocator = allocator,
            .overlap_buffer = overlap_buffer.ptr,
            .overlap_length = ir_length,
            .dry_wet = convolver_descriptor.available_parameters[0].default_value,
        };
    }

    pub fn deinit(self: *Convolver) void {
        self.allocator.free(self.overlap_buffer[0..self.overlap_length]);
        self.allocator.free(self.ir_buffer[0..self.ir_length]);
    }

    /// Set a parameter value by name
    pub fn setParameter(self: *Convolver, name: []const u8, value: f32) bool {
        if (std.mem.eql(u8, name, "dry_wet")) {
            self.dry_wet = convolver_descriptor.available_parameters[0].clamp(value);
            return true;
        }
        return false;
    }

    /// Get a parameter value by name
    pub fn getParameter(self: *const Convolver, name: []const u8) ?f32 {
        if (std.mem.eql(u8, name, "dry_wet")) {
            return self.dry_wet;
        }
        return null;
    }

    /// Process a single sample through convolution
    pub fn process(self: *const Convolver, input: f32) f32 {
        // Simple direct convolution for single sample
        var sum: f32 = 0.0;
        for (0..self.ir_length) |i| {
            sum += input * self.ir_buffer[i];
        }
        const normalized = sum / @as(f32, @floatFromInt(self.ir_length));

        // Apply dry/wet mix
        const result = input * (1.0 - self.dry_wet) + normalized * self.dry_wet;
        return result;
    }

    /// Process entire audio buffer with convolution
    pub fn processBuffer(self: *Convolver, buffer: *audio.AudioBuffer) void {

        // Check input signal
        var input_max: f32 = 0.0;
        var input_sum: f32 = 0.0;
        for (buffer.samples) |sample| {
            const abs_sample = if (sample < 0.0) -sample else sample;
            if (abs_sample > input_max) input_max = abs_sample;
            input_sum += sample;
        }

        // Direct convolution (time-domain)
        var output = self.allocator.alloc(f32, buffer.samples.len) catch {
            std.debug.print("[ERROR] Failed to allocate output buffer\n", .{});
            return;
        };
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

        // Check convolution output
        var conv_max: f32 = 0.0;
        var conv_sum: f32 = 0.0;
        for (output) |sample| {
            const abs_sample = if (sample < 0.0) -sample else sample;
            if (abs_sample > conv_max) conv_max = abs_sample;
            conv_sum += sample;
        }

        // Find peak to normalize and prevent clipping
        var max_sample: f32 = 0.0;
        for (output) |sample| {
            const abs_sample = if (sample < 0.0) -sample else sample;
            if (abs_sample > max_sample) max_sample = abs_sample;
        }


        // Always apply the convolution with normalization
        // The scale factor prevents clipping while preserving the convolved signal
        const scale = if (max_sample > 0.95) 0.95 / max_sample else 1.0;


        // Check scaled output before mixing
        var scaled_max: f32 = 0.0;
        for (output) |sample| {
            const scaled = sample * scale;
            const abs_scaled = if (scaled < 0.0) -scaled else scaled;
            if (abs_scaled > scaled_max) scaled_max = abs_scaled;
        }

        // Mix dry and wet

        var mixed_max: f32 = 0.0;
        var mixed_sum: f32 = 0.0;
        for (0..buffer.samples.len) |i| {
            const wet = output[i] * scale;
            const new_sample = buffer.samples[i] * (1.0 - self.dry_wet) + wet * self.dry_wet;
            buffer.samples[i] = new_sample;

            const abs_new = if (new_sample < 0.0) -new_sample else new_sample;
            if (abs_new > mixed_max) mixed_max = abs_new;
            mixed_sum += new_sample;
        }
    }
};
