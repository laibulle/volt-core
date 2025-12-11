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

        // TODO: Implement actual WaveNet inference
        // For now, pass through with gain/loudness applied

        const model = self.model.?;
        const gain_linear = std.math.pow(f32, 10.0, model.metadata.gain / 20.0);
        const loudness_linear = std.math.pow(f32, 10.0, model.metadata.loudness / 20.0);

        for (input, 0..) |sample, i| {
            if (i < output.len) {
                // Apply gain and loudness
                const processed = sample * gain_linear * loudness_linear;

                // TODO: Pass through WaveNet layers
                // processed = self.processLayer(0, processed, ...);
                // processed = self.processLayer(1, processed, ...);
                // etc.

                output[i] = processed;
            }
        }
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
