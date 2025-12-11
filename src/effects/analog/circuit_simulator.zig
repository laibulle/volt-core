const std = @import("std");
const audio = @import("../../audio.zig");
const components = @import("component_definitions.zig");
const parser = @import("kicad_parser.zig");

/// Circuit simulator using nodal analysis
/// Implements numerical simulation of analog circuits component by component
pub const CircuitSimulator = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(components.Node),
    components_storage: std.ArrayList(components.Component),
    connections: std.ArrayList(components.Connection),
    sample_rate: f32,

    pub fn init(allocator: std.mem.Allocator, sample_rate: f32) CircuitSimulator {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(components.Node).init(allocator),
            .components_storage = std.ArrayList(components.Component).init(allocator),
            .connections = std.ArrayList(components.Connection).init(allocator),
            .sample_rate = sample_rate,
        };
    }

    pub fn deinit(self: *CircuitSimulator) void {
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.deinit();
        self.components_storage.deinit();
        self.connections.deinit();
    }

    /// Add a resistor to the circuit
    pub fn addResistor(
        self: *CircuitSimulator,
        from_node_id: []const u8,
        to_node_id: []const u8,
        resistance: f32,
    ) !void {
        const from_idx = try self.getOrCreateNode(from_node_id);
        const to_idx = try self.getOrCreateNode(to_node_id);
        const comp_idx = self.components_storage.items.len;

        try self.components_storage.append(.{ .resistor = components.Resistor.init(resistance) });
        try self.connections.append(components.Connection.init(from_idx, to_idx, comp_idx));

        try self.nodes.items[from_idx].connected_components.append(comp_idx);
        try self.nodes.items[to_idx].connected_components.append(comp_idx);
    }

    /// Add a capacitor to the circuit
    pub fn addCapacitor(
        self: *CircuitSimulator,
        from_node_id: []const u8,
        to_node_id: []const u8,
        capacitance: f32,
    ) !void {
        const from_idx = try self.getOrCreateNode(from_node_id);
        const to_idx = try self.getOrCreateNode(to_node_id);
        const comp_idx = self.components_storage.items.len;

        try self.components_storage.append(.{ .capacitor = components.Capacitor.init(capacitance) });
        try self.connections.append(components.Connection.init(from_idx, to_idx, comp_idx));

        try self.nodes.items[from_idx].connected_components.append(comp_idx);
        try self.nodes.items[to_idx].connected_components.append(comp_idx);
    }

    /// Add an inductor to the circuit
    pub fn addInductor(
        self: *CircuitSimulator,
        from_node_id: []const u8,
        to_node_id: []const u8,
        inductance: f32,
    ) !void {
        const from_idx = try self.getOrCreateNode(from_node_id);
        const to_idx = try self.getOrCreateNode(to_node_id);
        const comp_idx = self.components_storage.items.len;

        try self.components_storage.append(.{ .inductor = components.Inductor.init(inductance) });
        try self.connections.append(components.Connection.init(from_idx, to_idx, comp_idx));

        try self.nodes.items[from_idx].connected_components.append(comp_idx);
        try self.nodes.items[to_idx].connected_components.append(comp_idx);
    }

    /// Add a diode to the circuit
    pub fn addDiode(
        self: *CircuitSimulator,
        from_node_id: []const u8,
        to_node_id: []const u8,
    ) !void {
        const from_idx = try self.getOrCreateNode(from_node_id);
        const to_idx = try self.getOrCreateNode(to_node_id);
        const comp_idx = self.components_storage.items.len;

        try self.components_storage.append(.{ .diode = components.Diode.init() });
        try self.connections.append(components.Connection.init(from_idx, to_idx, comp_idx));

        try self.nodes.items[from_idx].connected_components.append(comp_idx);
        try self.nodes.items[to_idx].connected_components.append(comp_idx);
    }

    /// Add an op-amp to the circuit
    pub fn addOpAmp(self: *CircuitSimulator) !void {
        const comp_idx = self.components_storage.items.len;
        try self.components_storage.append(.{ .opamp = components.OpAmp.init() });
        _ = comp_idx;
    }

    /// Get or create a node by ID
    fn getOrCreateNode(self: *CircuitSimulator, node_id: []const u8) !usize {
        // Check if node already exists
        for (self.nodes.items, 0..) |node, idx| {
            if (std.mem.eql(u8, node.id, node_id)) {
                return idx;
            }
        }

        // Create new node
        const new_node = try components.Node.init(self.allocator, node_id);
        try self.nodes.append(new_node);
        return self.nodes.items.len - 1;
    }

    /// Process a single sample through the circuit
    /// Uses simple iterative method for component updates
    pub fn processSample(self: *CircuitSimulator, input_voltage: f32, input_node_id: []const u8) f32 {
        // Find input node
        var input_node_idx: ?usize = null;
        for (self.nodes.items, 0..) |node, idx| {
            if (std.mem.eql(u8, node.id, input_node_id)) {
                input_node_idx = idx;
                break;
            }
        }

        if (input_node_idx == null) return 0.0;

        // Set input node voltage
        self.nodes.items[input_node_idx.?].voltage = input_voltage;

        // Update all components
        const dt = 1.0 / self.sample_rate;
        for (self.components_storage.items) |*comp| {
            switch (comp.*) {
                .capacitor => |*cap| {
                    // Simplified update: assume current through capacitor
                    const estimated_current = input_voltage * 0.001; // Rough estimate
                    cap.update(estimated_current, dt);
                },
                .inductor => |*ind| {
                    ind.update(input_voltage, dt);
                },
                else => {},
            }
        }

        // Simple output: return processed signal from first output node
        if (self.nodes.items.len > 1) {
            return self.nodes.items[1].voltage;
        }

        return input_voltage;
    }

    /// Process an audio buffer through the circuit
    pub fn processBuffer(self: *CircuitSimulator, buffer: *audio.AudioBuffer) void {
        const frame_count = buffer.frameCount();

        for (0..frame_count) |frame| {
            // Process each channel
            for (0..buffer.channel_count) |ch| {
                const input = buffer.getSample(frame, @intCast(ch));
                const output = self.processSample(input, "in");
                buffer.setSample(frame, @intCast(ch), output);
            }
        }
    }

    /// Reset all component states
    pub fn reset(self: *CircuitSimulator) void {
        for (self.components_storage.items) |*comp| {
            switch (comp.*) {
                .capacitor => |*cap| cap.voltage_state = 0.0,
                .inductor => |*ind| ind.current_state = 0.0,
                else => {},
            }
        }
    }

    /// Load a circuit from parsed KiCAD data
    pub fn loadFromKiCAD(
        self: *CircuitSimulator,
        parsed_circuit: *const parser.ParsedCircuit,
    ) !void {
        // Add components based on parsed data
        for (parsed_circuit.components.items) |comp| {
            const value = try components.parseValue(self.allocator, comp.value);
            defer self.allocator.free(value.unit);

            switch (comp.component_type) {
                .resistor => {
                    try self.addResistor("in", "out", value.value);
                },
                .capacitor => {
                    try self.addCapacitor("in", "out", value.value);
                },
                .inductor => {
                    try self.addInductor("in", "out", value.value);
                },
                .diode => {
                    try self.addDiode("in", "out");
                },
                else => {},
            }
        }
    }

    /// Get circuit statistics for debugging
    pub fn getStats(self: *const CircuitSimulator) CircuitStats {
        return .{
            .node_count = self.nodes.items.len,
            .component_count = self.components_storage.items.len,
            .connection_count = self.connections.items.len,
        };
    }
};

/// Circuit statistics
pub const CircuitStats = struct {
    node_count: usize,
    component_count: usize,
    connection_count: usize,
};

/// Advanced circuit solver using nodal analysis
/// For future enhancement: full SPICE-like solver
pub const AdvancedSolver = struct {
    allocator: std.mem.Allocator,
    /// Conductance matrix (G matrix in nodal analysis)
    g_matrix: ?[][]f32 = null,
    /// Current vector
    i_vector: ?[]f32 = null,
    /// Node voltages
    v_vector: ?[]f32 = null,

    pub fn init(allocator: std.mem.Allocator) AdvancedSolver {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AdvancedSolver) void {
        if (self.g_matrix) |matrix| {
            for (matrix) |row| {
                self.allocator.free(row);
            }
            self.allocator.free(matrix);
        }
        if (self.i_vector) |vec| self.allocator.free(vec);
        if (self.v_vector) |vec| self.allocator.free(vec);
    }

    /// Build the conductance matrix for nodal analysis
    /// This would implement the full SPICE-like nodal analysis
    pub fn buildMatrix(self: *AdvancedSolver, simulator: *const CircuitSimulator) !void {
        const n = simulator.nodes.items.len;

        // Allocate matrices
        self.g_matrix = try self.allocator.alloc([]f32, n);
        for (self.g_matrix.?) |*row| {
            row.* = try self.allocator.alloc(f32, n);
            @memset(row.*, 0.0);
        }

        self.i_vector = try self.allocator.alloc(f32, n);
        @memset(self.i_vector.?, 0.0);

        self.v_vector = try self.allocator.alloc(f32, n);
        @memset(self.v_vector.?, 0.0);

        // Build conductance matrix from components
        for (simulator.connections.items) |conn| {
            // For each component, add its conductance to the matrix
            const comp = simulator.components_storage.items[conn.component_index];

            switch (comp) {
                .resistor => |res| {
                    const g = 1.0 / res.resistance;
                    self.g_matrix.?[conn.from_node][conn.from_node] += g;
                    self.g_matrix.?[conn.to_node][conn.to_node] += g;
                    self.g_matrix.?[conn.from_node][conn.to_node] -= g;
                    self.g_matrix.?[conn.to_node][conn.from_node] -= g;
                },
                else => {},
            }
        }
    }
};
