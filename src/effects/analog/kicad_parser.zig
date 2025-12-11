const std = @import("std");
const components = @import("component_definitions.zig");

/// KiCAD PCB file parser
/// Extracts components and their connections from .kicad_pcb files
pub const KiCADParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) KiCADParser {
        return .{ .allocator = allocator };
    }

    /// Parse a KiCAD PCB file and extract component information
    pub fn parseFile(self: *KiCADParser, file_path: []const u8) !ParsedCircuit {
        var file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var reader = file.reader();
        var buffer: [8192]u8 = undefined;
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        while (true) {
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) break;
            try content.appendSlice(buffer[0..bytes_read]);
        }

        return try self.parseContent(content.items);
    }

    /// Parse KiCAD PCB content from string
    pub fn parseContent(self: *KiCADParser, content: []const u8) !ParsedCircuit {
        const parsed_components = std.ArrayList(ParsedComponent).init(self.allocator);
        const parsed_connections = std.ArrayList(ParsedConnection).init(self.allocator);
        var circuit = ParsedCircuit{
            .components = parsed_components,
            .connections = parsed_connections,
            .metadata = CircuitMetadata{
                .name = "",
                .description = "",
            },
        };

        var lines = std.mem.splitSequence(u8, content, "\n");

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            // Parse modules (components)
            if (std.mem.startsWith(u8, trimmed, "(module ")) {
                if (try self.parseModule(trimmed)) |parsed_comp| {
                    try circuit.components.append(parsed_comp);
                }
            }

            // Parse segments (nets/connections)
            if (std.mem.startsWith(u8, trimmed, "(segment")) {
                if (try self.parseSegment(trimmed)) |conn| {
                    try circuit.connections.append(conn);
                }
            }

            // Parse general info
            if (std.mem.startsWith(u8, trimmed, "(general")) {
                // Extract general circuit info
            }
        }

        return circuit;
    }

    /// Parse a module (component) definition from KiCAD
    /// Example: (module R_0603 (layer F.Cu) (tedit 5A02E0C5) (tstamp 5A4F81DC)
    fn parseModule(self: *KiCADParser, line: []const u8) !?ParsedComponent {
        var tokens = std.mem.splitSequence(u8, line, " ");
        _ = tokens.next(); // Skip "(module"

        const footprint_name = tokens.next() orelse "";

        // Parse component type from footprint
        const comp_type = detectComponentType(footprint_name);
        if (comp_type == null) return null;

        return ParsedComponent{
            .reference = "",
            .footprint = try self.allocator.dupe(u8, footprint_name),
            .value = "",
            .component_type = comp_type.?,
            .position = Position{ .x = 0, .y = 0 },
            .rotation = 0,
        };
    }

    /// Parse a segment (connection) definition
    fn parseSegment(self: *KiCADParser, line: []const u8) !?ParsedConnection {
        _ = self;
        _ = line;
        // Segments in KiCAD PCB represent traces/wires between pads
        // For now, we'll extract this from pad connections
        return null;
    }

    /// Detect component type from footprint name
    fn detectComponentType(footprint: []const u8) ?components.ComponentType {
        const lower = std.mem.toLower(footprint);

        if (std.mem.containsAtLeast(u8, lower, 1, "r_") or std.mem.eql(u8, lower, "resistor")) {
            return .resistor;
        }
        if (std.mem.containsAtLeast(u8, lower, 1, "c_") or std.mem.eql(u8, lower, "capacitor")) {
            return .capacitor;
        }
        if (std.mem.containsAtLeast(u8, lower, 1, "l_") or std.mem.eql(u8, lower, "inductor")) {
            return .inductor;
        }
        if (std.mem.containsAtLeast(u8, lower, 1, "u_") or std.mem.eql(u8, lower, "ic")) {
            return .opamp; // Simplification: IC -> OpAmp
        }
        if (std.mem.containsAtLeast(u8, lower, 1, "d_") or std.mem.eql(u8, lower, "diode")) {
            return .diode;
        }
        if (std.mem.containsAtLeast(u8, lower, 1, "q_") or std.mem.eql(u8, lower, "transistor")) {
            return .transistor;
        }

        return null;
    }
};

/// Parsed circuit structure from KiCAD file
pub const ParsedCircuit = struct {
    components: std.ArrayList(ParsedComponent),
    connections: std.ArrayList(ParsedConnection),
    metadata: CircuitMetadata,

    pub fn deinit(self: *ParsedCircuit) void {
        for (self.components.items) |*comp| {
            comp.deinit(self.components.allocator);
        }
        self.components.deinit();
        self.connections.deinit();
    }
};

/// Parsed component from KiCAD file
pub const ParsedComponent = struct {
    reference: []const u8, // e.g., "R1", "C5"
    footprint: []const u8, // e.g., "R_0603"
    value: []const u8, // e.g., "10k", "100n"
    component_type: components.ComponentType,
    position: Position,
    rotation: i32,

    pub fn deinit(self: *ParsedComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.footprint);
    }
};

/// Position of component on PCB
pub const Position = struct {
    x: i32, // in 0.01mm units (KiCAD default)
    y: i32,
};

/// Parsed connection between components
pub const ParsedConnection = struct {
    from_node: []const u8,
    to_node: []const u8,
    net_name: []const u8,
};

/// Circuit metadata
pub const CircuitMetadata = struct {
    name: []const u8 = "",
    description: []const u8 = "",
    version: []const u8 = "1.0",
    timestamp: []const u8 = "",
};

/// Helper to extract value from KiCAD property string
pub fn extractPropertyValue(
    allocator: std.mem.Allocator,
    line: []const u8,
    property_name: []const u8,
) !?[]const u8 {
    var start_idx: ?usize = null;

    // Find property pattern
    const pattern = try std.fmt.allocPrint(allocator, "({s} \"", .{property_name});
    defer allocator.free(pattern);

    if (std.mem.indexOf(u8, line, pattern)) |idx| {
        start_idx = idx + pattern.len;
    }

    if (start_idx == null) {
        return null;
    }

    // Find closing quote
    if (std.mem.indexOf(u8, line[start_idx.?..], "\"")) |end_idx| {
        const result = line[start_idx.? .. start_idx.? + end_idx];
        return try allocator.dupe(u8, result);
    }

    return null;
}
