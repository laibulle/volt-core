const std = @import("std");

/// NAM file format parser
/// Neural Amp Modeler files contain serialized neural network models
/// in a binary format with metadata and quantized weights
pub const NAMMetadata = struct {
    name: []const u8,
    description: []const u8 = "",
    date: []const u8 = "",
    creator: []const u8 = "",
    sample_rate: u32,
    latency_ms: f32 = 0.0,
};

pub const NAMModel = struct {
    metadata: NAMMetadata,
    allocator: std.mem.Allocator,

    /// File path for reference
    file_path: []const u8,

    /// Raw model data
    model_data: []u8,

    pub fn deinit(self: *NAMModel) void {
        self.allocator.free(self.metadata.name);
        if (self.metadata.description.len > 0) {
            self.allocator.free(self.metadata.description);
        }
        if (self.metadata.date.len > 0) {
            self.allocator.free(self.metadata.date);
        }
        if (self.metadata.creator.len > 0) {
            self.allocator.free(self.metadata.creator);
        }
        self.allocator.free(self.file_path);
        self.allocator.free(self.model_data);
    }
};

/// Load a NAM model file
/// NAM files are binary archives - we'll read the full file and parse metadata
pub fn loadNAMFile(allocator: std.mem.Allocator, file_path: []const u8) !NAMModel {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const file_data = try allocator.alloc(u8, file_size);

    const bytes_read = try file.readAll(file_data);
    if (bytes_read != file_size) {
        allocator.free(file_data);
        return error.IncompleteFileRead;
    }

    // Parse metadata from the file
    const metadata = try parseNAMMetadata(allocator, file_data);

    return NAMModel{
        .metadata = metadata,
        .allocator = allocator,
        .file_path = try allocator.dupe(u8, file_path),
        .model_data = file_data,
    };
}

/// Extract metadata from NAM file
/// NAM files typically start with a header containing metadata
fn parseNAMMetadata(allocator: std.mem.Allocator, file_data: []const u8) !NAMMetadata {
    // NAM files are binary, but we can extract basic info from the filename and format
    // For now, we'll return a basic metadata structure with sensible defaults

    var metadata = NAMMetadata{
        .name = try allocator.dupe(u8, "NAM Model"),
        .description = try allocator.dupe(u8, "Neural Amp Model"),
        .date = try allocator.dupe(u8, ""),
        .creator = try allocator.dupe(u8, ""),
        .sample_rate = 48000, // Default, can be adjusted
        .latency_ms = 0.0,
    };

    // Try to extract metadata from file if it contains JSON header
    // NAM files may have metadata in JSON format at the beginning
    if (std.mem.startsWith(u8, file_data, "{")) {
        // Attempt to parse JSON metadata
        if (parseNAMJsonHeader(allocator, file_data)) |parsed_metadata| {
            // Free previously allocated metadata strings
            allocator.free(metadata.name);
            allocator.free(metadata.description);
            allocator.free(metadata.date);
            allocator.free(metadata.creator);

            metadata = parsed_metadata;
        } else |_| {
            // If JSON parsing fails, just use defaults
        }
    }

    return metadata;
}

/// Try to parse JSON metadata header from NAM file
fn parseNAMJsonHeader(allocator: std.mem.Allocator, file_data: []const u8) !NAMMetadata {
    // Find the end of the JSON object (likely ends with })
    var json_end: usize = 0;
    var brace_count: i32 = 0;

    for (0..file_data.len) |i| {
        if (file_data[i] == '{') {
            brace_count += 1;
        } else if (file_data[i] == '}') {
            brace_count -= 1;
            if (brace_count == 0) {
                json_end = i + 1;
                break;
            }
        }
    }

    if (json_end == 0 or json_end > 10000) {
        // JSON header seems too large or not found
        return error.NoValidJsonHeader;
    }

    const json_str = file_data[0..json_end];

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{ .allocate = .alloc_if_needed },
    );
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) {
        return error.InvalidJsonFormat;
    }

    var name: []const u8 = "NAM Model";
    var description: []const u8 = "";
    var date: []const u8 = "";
    var creator: []const u8 = "";
    var sample_rate: u32 = 48000;
    var latency_ms: f32 = 0.0;

    if (root.object.get("model")) |model_obj| {
        if (model_obj == .object) {
            if (model_obj.object.get("name")) |name_val| {
                if (name_val == .string) {
                    name = name_val.string;
                }
            }
            if (model_obj.object.get("description")) |desc_val| {
                if (desc_val == .string) {
                    description = desc_val.string;
                }
            }
            if (model_obj.object.get("date")) |date_val| {
                if (date_val == .string) {
                    date = date_val.string;
                }
            }
            if (model_obj.object.get("creator")) |creator_val| {
                if (creator_val == .string) {
                    creator = creator_val.string;
                }
            }
            if (model_obj.object.get("sample_rate")) |sr_val| {
                if (sr_val == .integer) {
                    sample_rate = @intCast(sr_val.integer);
                }
            }
            if (model_obj.object.get("latency_ms")) |lat_val| {
                if (lat_val == .float) {
                    latency_ms = @floatCast(lat_val.float);
                } else if (lat_val == .integer) {
                    latency_ms = @floatFromInt(lat_val.integer);
                }
            }
        }
    }

    return NAMMetadata{
        .name = try allocator.dupe(u8, name),
        .description = try allocator.dupe(u8, description),
        .date = try allocator.dupe(u8, date),
        .creator = try allocator.dupe(u8, creator),
        .sample_rate = sample_rate,
        .latency_ms = latency_ms,
    };
}

/// Print NAM model metadata
pub fn printModelMetadata(model: *const NAMModel) void {
    std.debug.print("\n╔════════════════════════════════════════╗\n", .{});
    std.debug.print("║       Neural Amp Model Information      ║\n", .{});
    std.debug.print("╚════════════════════════════════════════╝\n\n", .{});

    std.debug.print("Name:        {s}\n", .{model.metadata.name});
    std.debug.print("Description: {s}\n", .{model.metadata.description});
    std.debug.print("Creator:     {s}\n", .{model.metadata.creator});
    std.debug.print("Date:        {s}\n", .{model.metadata.date});
    std.debug.print("Sample Rate: {d} Hz\n", .{model.metadata.sample_rate});
    std.debug.print("Latency:     {d:.2} ms\n", .{model.metadata.latency_ms});
    std.debug.print("File Size:   {d} bytes\n", .{model.model_data.len});
    std.debug.print("File Path:   {s}\n\n", .{model.file_path});
}

test "load NAM file" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // This test requires an actual .nam file
    // For now, we'll create a mock test
    const mock_nam_data = "Mock NAM data";

    _ = mock_nam_data;
    _ = allocator;
}
