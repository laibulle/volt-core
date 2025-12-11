const std = @import("std");

// ============================================================================
// NAM Model Parser - Extracts WaveNet configuration from JSON files
// ============================================================================

pub const LayerConfig = struct {
    input_size: usize,
    condition_size: usize,
    head_size: usize,
    channels: usize,
    kernel_size: usize,
    dilations: []usize,
    activation: []const u8,
    gated: bool,
    head_bias: bool,

    pub fn deinit(self: *LayerConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.dilations);
        allocator.free(self.activation);
    }
};

pub const WaveNetConfig = struct {
    layers: []LayerConfig,
    head: ?[]const u8 = null,
    head_scale: f32 = 0.02,

    pub fn deinit(self: *WaveNetConfig, allocator: std.mem.Allocator) void {
        for (self.layers) |*layer| {
            layer.deinit(allocator);
        }
        allocator.free(self.layers);
        if (self.head) |h| {
            allocator.free(h);
        }
    }
};

pub const NAMMetadata = struct {
    name: []u8,
    modeled_by: []u8,
    gear_type: []u8,
    gear_make: []u8,
    gear_model: []u8,
    tone_type: []u8,
    loudness: f32,
    gain: f32,
    validation_esr: f32,

    pub fn deinit(self: *NAMMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.modeled_by);
        allocator.free(self.gear_type);
        allocator.free(self.gear_make);
        allocator.free(self.gear_model);
        allocator.free(self.tone_type);
    }
};

pub const NAMModel = struct {
    version: []u8,
    metadata: NAMMetadata,
    architecture: []u8,
    config: WaveNetConfig,
    weights: []f32,

    pub fn deinit(self: *NAMModel, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        allocator.free(self.architecture);
        self.metadata.deinit(allocator);
        self.config.deinit(allocator);
        allocator.free(self.weights);
    }
};

// ============================================================================
// NAM Model Loader
// ============================================================================

pub fn loadNAMFile(allocator: std.mem.Allocator, file_path: []const u8) !NAMModel {
    // Load file
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const file_data = try allocator.alloc(u8, file_size);
    defer allocator.free(file_data);

    const bytes_read = try file.readAll(file_data);
    if (bytes_read != file_size) {
        return error.IncompleteRead;
    }

    // Parse JSON
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        file_data,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;

    // Extract metadata
    var model = NAMModel{
        .version = try allocator.dupe(u8, root.get("version").?.string),
        .metadata = try parseMetadata(allocator, root),
        .architecture = try allocator.dupe(u8, root.get("architecture").?.string),
        .config = try parseConfig(allocator, root),
        .weights = try parseWeights(allocator, root),
    };

    return model;
}

fn parseMetadata(allocator: std.mem.Allocator, root: std.json.ObjectMap) !NAMMetadata {
    const meta_obj = root.get("metadata").?.object;

    return NAMMetadata{
        .name = try allocator.dupe(u8, meta_obj.get("name").?.string),
        .modeled_by = try allocator.dupe(u8, meta_obj.get("modeled_by").?.string),
        .gear_type = try allocator.dupe(u8, meta_obj.get("gear_type").?.string),
        .gear_make = try allocator.dupe(u8, meta_obj.get("gear_make").?.string),
        .gear_model = try allocator.dupe(u8, meta_obj.get("gear_model").?.string),
        .tone_type = try allocator.dupe(u8, meta_obj.get("tone_type").?.string),
        .loudness = @floatCast(meta_obj.get("loudness").?.number),
        .gain = @floatCast(meta_obj.get("gain").?.number),
        .validation_esr = @floatCast(meta_obj.get("validation_esr").?.number),
    };
}

fn parseConfig(allocator: std.mem.Allocator, root: std.json.ObjectMap) !WaveNetConfig {
    const config_obj = root.get("config").?.object;
    const layers_array = config_obj.get("layers").?.array;

    var layers = try allocator.alloc(LayerConfig, layers_array.items.len);
    for (layers_array.items, 0..) |layer_json, i| {
        const layer_obj = layer_json.object;
        const dilations_array = layer_obj.get("dilations").?.array;

        var dilations = try allocator.alloc(usize, dilations_array.items.len);
        for (dilations_array.items, 0..) |dil_json, j| {
            dilations[j] = @intCast(dil_json.integer);
        }

        layers[i] = LayerConfig{
            .input_size = @intCast(layer_obj.get("input_size").?.integer),
            .condition_size = @intCast(layer_obj.get("condition_size").?.integer),
            .head_size = @intCast(layer_obj.get("head_size").?.integer),
            .channels = @intCast(layer_obj.get("channels").?.integer),
            .kernel_size = @intCast(layer_obj.get("kernel_size").?.integer),
            .dilations = dilations,
            .activation = try allocator.dupe(u8, layer_obj.get("activation").?.string),
            .gated = layer_obj.get("gated").?.bool,
            .head_bias = layer_obj.get("head_bias").?.bool,
        };
    }

    return WaveNetConfig{
        .layers = layers,
        .head = null,
        .head_scale = @floatCast(config_obj.get("head_scale").?.number),
    };
}

fn parseWeights(allocator: std.mem.Allocator, root: std.json.ObjectMap) ![]f32 {
    const weights_array = root.get("weights").?.array;
    var weights = try allocator.alloc(f32, weights_array.items.len);

    for (weights_array.items, 0..) |weight_json, i| {
        weights[i] = @floatCast(weight_json.number);
    }

    return weights;
}
