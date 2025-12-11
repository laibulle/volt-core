const std = @import("std");
const audio = @import("../../audio.zig");
const ports = @import("../../ports/effects.zig");
const nam_loader = @import("nam_loader.zig");

/// Neural effect descriptor
pub const neural_descriptor: ports.EffectDescriptor = .{
    .id = "neural",
    .name = "Neural Amp Modeler",
    .description = "Deep learning-based amplifier and audio device modeling using trained neural networks",
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
        .{
            .name = "input_gain",
            .param_type = ports.ParameterType.float,
            .default_value = 0.0,
            .min_value = -24.0,
            .max_value = 24.0,
            .description = "Input gain in dB",
        },
        .{
            .name = "output_gain",
            .param_type = ports.ParameterType.float,
            .default_value = 0.0,
            .min_value = -24.0,
            .max_value = 24.0,
            .description = "Output gain in dB",
        },
    },
};

/// Neural effect processor
/// Loads and processes audio through trained NAM models
pub const NeuralEffect = struct {
    model: ?nam_loader.NAMModel = null,
    allocator: std.mem.Allocator,
    
    // Processing parameters
    dry_wet: f32 = 1.0,
    input_gain: f32 = 0.0, // dB
    output_gain: f32 = 0.0, // dB
    
    // Dry buffer for mixing
    dry_buffer: ?[]f32 = null,
    dry_buffer_size: usize = 0,

    /// Initialize empty neural effect
    pub fn init(allocator: std.mem.Allocator) NeuralEffect {
        return NeuralEffect{
            .allocator = allocator,
        };
    }

    /// Initialize neural effect from NAM model file
    pub fn initFromFile(allocator: std.mem.Allocator, model_path: []const u8) !NeuralEffect {
        var effect = NeuralEffect.init(allocator);
        effect.model = try nam_loader.loadNAMFile(allocator, model_path);
        nam_loader.printModelMetadata(&effect.model.?);
        return effect;
    }

    /// Process audio buffer through the neural effect
    pub fn processBuffer(self: *NeuralEffect, buffer: *audio.AudioBuffer) void {
        if (self.model == null) {
            // No model loaded, pass through
            return;
        }

        const frame_count = buffer.samples.len / buffer.channel_count;
        _ = frame_count;

        // Allocate dry buffer if needed for mixing
        if (self.dry_wet < 1.0) {
            if (self.dry_buffer == null or self.dry_buffer_size < buffer.samples.len) {
                if (self.dry_buffer) |old_buffer| {
                    self.allocator.free(old_buffer);
                }
                self.dry_buffer = self.allocator.alloc(f32, buffer.samples.len) catch |err| {
                    std.debug.print("Error allocating dry buffer: {}\n", .{err});
                    return;
                };
                self.dry_buffer_size = buffer.samples.len;
            }

            // Copy original samples for dry signal
            @memcpy(self.dry_buffer.?, buffer.samples);
        }

        // Apply input gain
        if (self.input_gain != 0.0) {
            const gain_linear = std.math.pow(f32, 10.0, self.input_gain / 20.0);
            for (0..buffer.samples.len) |i| {
                buffer.samples[i] *= gain_linear;
            }
        }

        // Process through neural model
        // For now, we'll implement a placeholder pass-through
        // In Phase 2, this will integrate ONNX Runtime inference
        _ = self.processNeuralModel(buffer);

        // Apply output gain
        if (self.output_gain != 0.0) {
            const gain_linear = std.math.pow(f32, 10.0, self.output_gain / 20.0);
            for (0..buffer.samples.len) |i| {
                buffer.samples[i] *= gain_linear;
            }
        }

        // Dry/Wet mixing
        if (self.dry_wet < 1.0) {
            const wet_factor = self.dry_wet;
            const dry_factor = 1.0 - self.dry_wet;
            
            for (0..buffer.samples.len) |i| {
                buffer.samples[i] = buffer.samples[i] * wet_factor + self.dry_buffer.?[i] * dry_factor;
            }
        }
    }

    /// Process audio through the neural model
    /// This is a placeholder - will be replaced with actual ONNX inference in Phase 2
    fn processNeuralModel(self: *NeuralEffect, buffer: *audio.AudioBuffer) void {
        if (self.model == null) return;

        // Placeholder: Currently just passes audio through
        // In Phase 2, this will:
        // 1. Normalize input based on model training parameters
        // 2. Run ONNX Runtime inference
        // 3. Denormalize output
        
        // TODO: Implement ONNX Runtime integration
        std.debug.print("Neural model processing: {s}\n", .{self.model.?.metadata.name});
        _ = buffer;
    }

    /// Set a parameter value
    pub fn setParameter(self: *NeuralEffect, name: []const u8, value: f32) bool {
        if (std.mem.eql(u8, name, "dry_wet")) {
            self.dry_wet = std.math.clamp(value, 0.0, 1.0);
            return true;
        } else if (std.mem.eql(u8, name, "input_gain")) {
            self.input_gain = std.math.clamp(value, -24.0, 24.0);
            return true;
        } else if (std.mem.eql(u8, name, "output_gain")) {
            self.output_gain = std.math.clamp(value, -24.0, 24.0);
            return true;
        }
        return false;
    }

    /// Get a parameter value
    pub fn getParameter(self: *const NeuralEffect, name: []const u8) ?f32 {
        if (std.mem.eql(u8, name, "dry_wet")) {
            return self.dry_wet;
        } else if (std.mem.eql(u8, name, "input_gain")) {
            return self.input_gain;
        } else if (std.mem.eql(u8, name, "output_gain")) {
            return self.output_gain;
        }
        return null;
    }

    /// Clean up resources
    pub fn deinit(self: *NeuralEffect) void {
        if (self.model) |*model| {
            model.deinit();
        }
        if (self.dry_buffer) |buffer| {
            self.allocator.free(buffer);
        }
    }
};

test "create neural effect" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var effect = NeuralEffect.init(allocator);
    defer effect.deinit();

    try std.testing.expect(effect.model == null);
    try std.testing.expectEqual(effect.dry_wet, 1.0);
}

test "set neural effect parameters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var effect = NeuralEffect.init(allocator);
    defer effect.deinit();

    try std.testing.expect(effect.setParameter("dry_wet", 0.5));
    try std.testing.expectEqual(effect.dry_wet, 0.5);

    try std.testing.expect(effect.setParameter("input_gain", 6.0));
    try std.testing.expectEqual(effect.input_gain, 6.0);

    try std.testing.expect(!effect.setParameter("unknown_param", 0.5));
}
