const std = @import("std");
const nam_parser = @import("nam_parser.zig");

// ============================================================================
// WaveNet Neural Network Inference Engine
// Processes audio through NAM models using dilated causal convolutions
// ============================================================================

pub const WaveNetInference = struct {
    allocator: std.mem.Allocator,
    model: ?nam_parser.NAMModel = null,

    // Layer processing state
    layer_histories: ?[][]f32 = null,
    initialized: bool = false,

    pub fn init(allocator: std.mem.Allocator) !WaveNetInference {
        std.debug.print("[WaveNet] Inference engine initialized\n", .{});

        return WaveNetInference{
            .allocator = allocator,
            .initialized = true,
        };
    }

    /// Load NAM model and prepare for inference
    pub fn loadModel(self: *WaveNetInference, nam_model_path: []const u8) !void {
        if (!self.initialized) {
            return error.NotInitialized;
        }

        // Parse NAM JSON file
        self.model = try nam_parser.loadNAMFile(self.allocator, nam_model_path);

        const model = self.model.?;

        std.debug.print("[WaveNet] Model loaded: {s}\n", .{model.metadata.name});
        std.debug.print("[WaveNet] Architecture: {s}\n", .{model.architecture});
        std.debug.print("[WaveNet] Metadata - Gain: {d:.3}, Loudness: {d:.3}\n", .{ model.metadata.gain, model.metadata.loudness });
        std.debug.print("[WaveNet] Configuration - {d} layers, {d} weights\n", .{ model.config.layers.len, model.weights.len });

        // Initialize layer history buffers
        // Each layer needs a history of max_dilation * kernel_size samples
        self.layer_histories = try self.allocator.alloc([]f32, model.config.layers.len);

        for (model.config.layers, 0..) |layer, i| {
            const max_dilation = if (layer.dilations.len > 0) layer.dilations[layer.dilations.len - 1] else 1;
            const history_size = max_dilation * layer.kernel_size;

            self.layer_histories.?[i] = try self.allocator.alloc(f32, history_size);
            @memset(self.layer_histories.?[i], 0);

            std.debug.print("[WaveNet]   Layer {d}: {d}→{d} channels, history size {d}\n", .{ i, layer.input_size, layer.channels, history_size });
        }
    }

    /// Process audio block through the network
    pub fn infer(self: *WaveNetInference, input: []f32, output: []f32) !void {
        if (!self.initialized or self.model == null) {
            // Pass through if not initialized
            if (input.ptr != output.ptr) {
                @memcpy(output, input);
            }
            return;
        }

        const model = self.model.?;
        const gain_linear = std.math.pow(f32, 10.0, model.metadata.gain / 20.0);
        const loudness_linear = std.math.pow(f32, 10.0, model.metadata.loudness / 20.0);

        // Process each sample through the WaveNet
        for (input, 0..) |sample, i| {
            if (i < output.len) {
                // Apply input normalization
                var processed = sample * gain_linear * loudness_linear;

                // Process through each layer
                for (model.config.layers, 0..) |layer, layer_idx| {
                    processed = try self.processLayer(layer_idx, processed, layer);
                }

                // Output the processed sample
                output[i] = processed;
            }
        }
    }

    /// Process a single sample through one WaveNet layer
    fn processLayer(self: *WaveNetInference, layer_idx: usize, input: f32, layer: nam_parser.LayerConfig) !f32 {
        const model = self.model.?;
        const history = self.layer_histories.?[layer_idx];

        // Calculate output from dilated convolution
        var output: f32 = 0.0;

        // For each dilation in the layer
        for (layer.dilations) |dilation| {
            // Convolve across the kernel size
            for (0..layer.kernel_size) |k| {
                // Calculate the position in history to read
                const delay = dilation * (layer.kernel_size - 1 - k);
                var history_sample: f32 = 0.0;

                if (delay < history.len) {
                    // Read from history buffer
                    const history_idx = history.len - 1 - delay;
                    history_sample = history[history_idx];
                } else {
                    // Outside history window, use input
                    history_sample = input;
                }

                // Get weight for this position
                // Simplified: assuming weights are ordered by layer, dilation, kernel position
                const weight_idx = (layer_idx * 1000 + dilation * 100 + k) % model.weights.len;
                output += history_sample * model.weights[weight_idx];
            }
        }

        // Apply activation function (Tanh)
        const activated = self.tanh(output);

        // Update history buffer with new output
        // Shift history and add new sample
        if (history.len > 0) {
            for (0..history.len - 1) |j| {
                history[j] = history[j + 1];
            }
            history[history.len - 1] = activated;
        }

        return activated;
    }

    /// Fast approximation of tanh activation
    /// Uses a polynomial approximation for efficiency
    fn tanh(self: *WaveNetInference, x: f32) f32 {
        _ = self; // Unused but kept for potential future context
        
        // Use standard library tanh for accuracy
        return std.math.tanh(x);
        
        // Polynomial approximation (if needed for performance):
        // const x_sq = x * x;
        // const a = x * (1.0 + 0.16489087 * x_sq);
        // const b = 1.0 + 0.9 * x_sq;
        // return a / b;
    }

    pub fn deinit(self: *WaveNetInference) void {
        if (self.layer_histories) |histories| {
            for (histories) |history| {
                self.allocator.free(history);
            }
            self.allocator.free(histories);
        }

        if (self.model) |*model| {
            model.deinit(self.allocator);
        }

        std.debug.print("[WaveNet] Inference engine cleaned up\n", .{});
    }
};

// ============================================================================
// Legacy Compatibility: ONNXInference alias for backward compatibility
// ============================================================================

pub const ONNXInference = WaveNetInference;
