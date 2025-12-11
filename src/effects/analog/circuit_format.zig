const std = @import("std");

/// Simplified internal circuit format
///
/// This is the runtime-optimized representation of a circuit.
/// It contains only the essential data needed for simulation:
/// - Component parameters (resistance, capacitance, etc.)
/// - Node connectivity (which components connect where)
/// - Initial state information
///
/// This format is produced by the KiCAD parser and consumed by the simulator.
/// It's much simpler and faster than the parsed KiCAD representation.
/// Component type identifier
pub const ComponentKind = enum(u8) {
    resistor = 0,
    capacitor = 1,
    inductor = 2,
    diode = 3,
    opamp = 4,
    transistor = 5,
};

/// Simplified component definition for runtime
pub const RuntimeComponent = struct {
    /// Component type
    kind: ComponentKind,

    /// Node indices
    from_node: u32,
    to_node: u32,

    /// Primary parameter (resistance, capacitance, etc.)
    primary_value: f32,

    /// Secondary parameter (for more complex components)
    secondary_value: f32 = 0.0,

    /// Third parameter if needed
    tertiary_value: f32 = 0.0,

    pub fn init(kind: ComponentKind, from: u32, to: u32, value: f32) RuntimeComponent {
        return .{
            .kind = kind,
            .from_node = from,
            .to_node = to,
            .primary_value = value,
        };
    }
};

/// Node state information
pub const RuntimeNode = struct {
    /// Node identifier (kept for debugging, could be removed for production)
    id: []const u8,

    /// Current voltage at this node
    voltage: f32 = 0.0,

    /// Index of first connected component (for fast lookup)
    component_start: u32 = 0,

    /// Number of connected components
    component_count: u32 = 0,

    pub fn init(id: []const u8) RuntimeNode {
        return .{
            .id = id,
            .voltage = 0.0,
        };
    }
};

/// Component state - minimal runtime state for reactive elements
pub const ComponentState = struct {
    /// For capacitors: voltage across capacitor
    /// For inductors: current through inductor
    /// For diodes/opamps: internal state or bias point
    state1: f32 = 0.0,

    /// Secondary state if needed
    state2: f32 = 0.0,

    pub fn reset(self: *ComponentState) void {
        self.state1 = 0.0;
        self.state2 = 0.0;
    }
};

/// Complete internal circuit representation
pub const InternalCircuit = struct {
    /// Circuit name/identifier
    name: []const u8,

    /// All nodes in the circuit
    nodes: []RuntimeNode,

    /// All components in the circuit
    components: []RuntimeComponent,

    /// Component states (parallel to components array)
    component_states: []ComponentState,

    /// Component connectivity lookup (optional, for optimization)
    /// Maps node index to list of connected component indices
    node_connections: ?[][]u32 = null,

    /// Input node index
    input_node: u32 = 0,

    /// Output node index
    output_node: u32 = 1,

    /// Ground node index (always 0V)
    ground_node: u32 = 0,

    /// Allocator for cleanup
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        node_count: usize,
        component_count: usize,
    ) !InternalCircuit {
        const nodes = try allocator.alloc(RuntimeNode, node_count);
        const components = try allocator.alloc(RuntimeComponent, component_count);
        const states = try allocator.alloc(ComponentState, component_count);

        @memset(components, undefined);
        @memset(states, ComponentState{});

        return .{
            .name = try allocator.dupe(u8, name),
            .nodes = nodes,
            .components = components,
            .component_states = states,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InternalCircuit) void {
        self.allocator.free(self.name);
        self.allocator.free(self.nodes);
        self.allocator.free(self.components);
        self.allocator.free(self.component_states);

        if (self.node_connections) |conns| {
            for (conns) |conn| {
                self.allocator.free(conn);
            }
            self.allocator.free(conns);
        }
    }

    /// Get component at index
    pub fn getComponent(self: *const InternalCircuit, idx: usize) *const RuntimeComponent {
        return &self.components[idx];
    }

    /// Get mutable component at index
    pub fn getComponentMut(self: *InternalCircuit, idx: usize) *RuntimeComponent {
        return &self.components[idx];
    }

    /// Get component state at index
    pub fn getComponentState(self: *const InternalCircuit, idx: usize) *const ComponentState {
        return &self.component_states[idx];
    }

    /// Get mutable component state at index
    pub fn getComponentStateMut(self: *InternalCircuit, idx: usize) *ComponentState {
        return &self.component_states[idx];
    }

    /// Get node at index
    pub fn getNode(self: *const InternalCircuit, idx: usize) *const RuntimeNode {
        return &self.nodes[idx];
    }

    /// Get mutable node at index
    pub fn getNodeMut(self: *InternalCircuit, idx: usize) *RuntimeNode {
        return &self.nodes[idx];
    }

    /// Find node index by id
    pub fn findNodeById(self: *const InternalCircuit, id: []const u8) ?usize {
        for (self.nodes, 0..) |node, idx| {
            if (std.mem.eql(u8, node.id, id)) {
                return idx;
            }
        }
        return null;
    }

    /// Reset all component states
    pub fn resetStates(self: *InternalCircuit) void {
        for (self.component_states) |*state| {
            state.reset();
        }
    }

    /// Get circuit statistics
    pub fn getStats(self: *const InternalCircuit) CircuitStats {
        return .{
            .node_count = self.nodes.len,
            .component_count = self.components.len,
        };
    }
};

/// Circuit statistics
pub const CircuitStats = struct {
    node_count: usize,
    component_count: usize,
};

/// Builder for constructing circuits programmatically
pub const CircuitBuilder = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(RuntimeNode),
    components: std.ArrayList(RuntimeComponent),
    name: []const u8,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !CircuitBuilder {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(RuntimeNode).init(allocator),
            .components = std.ArrayList(RuntimeComponent).init(allocator),
            .name = try allocator.dupe(u8, name),
        };
    }

    pub fn deinit(self: *CircuitBuilder) void {
        self.allocator.free(self.name);
        self.nodes.deinit();
        self.components.deinit();
    }

    /// Add a node to the circuit
    pub fn addNode(self: *CircuitBuilder, id: []const u8) !u32 {
        const idx = self.nodes.items.len;
        try self.nodes.append(RuntimeNode.init(try self.allocator.dupe(u8, id)));
        return @intCast(idx);
    }

    /// Get or create a node
    pub fn getOrCreateNode(self: *CircuitBuilder, id: []const u8) !u32 {
        for (self.nodes.items, 0..) |node, idx| {
            if (std.mem.eql(u8, node.id, id)) {
                return @intCast(idx);
            }
        }
        return try self.addNode(id);
    }

    /// Add a resistor
    pub fn addResistor(
        self: *CircuitBuilder,
        from_id: []const u8,
        to_id: []const u8,
        resistance: f32,
    ) !void {
        const from = try self.getOrCreateNode(from_id);
        const to = try self.getOrCreateNode(to_id);

        try self.components.append(RuntimeComponent.init(
            .resistor,
            from,
            to,
            resistance,
        ));
    }

    /// Add a capacitor
    pub fn addCapacitor(
        self: *CircuitBuilder,
        from_id: []const u8,
        to_id: []const u8,
        capacitance: f32,
    ) !void {
        const from = try self.getOrCreateNode(from_id);
        const to = try self.getOrCreateNode(to_id);

        try self.components.append(RuntimeComponent.init(
            .capacitor,
            from,
            to,
            capacitance,
        ));
    }

    /// Add an inductor
    pub fn addInductor(
        self: *CircuitBuilder,
        from_id: []const u8,
        to_id: []const u8,
        inductance: f32,
    ) !void {
        const from = try self.getOrCreateNode(from_id);
        const to = try self.getOrCreateNode(to_id);

        try self.components.append(RuntimeComponent.init(
            .inductor,
            from,
            to,
            inductance,
        ));
    }

    /// Add a diode
    pub fn addDiode(
        self: *CircuitBuilder,
        from_id: []const u8,
        to_id: []const u8,
    ) !void {
        const from = try self.getOrCreateNode(from_id);
        const to = try self.getOrCreateNode(to_id);

        try self.components.append(RuntimeComponent.init(
            .diode,
            from,
            to,
            1.0, // Placeholder value
        ));
    }

    /// Add an op-amp
    pub fn addOpAmp(
        self: *CircuitBuilder,
        from_id: []const u8,
        to_id: []const u8,
    ) !void {
        const from = try self.getOrCreateNode(from_id);
        const to = try self.getOrCreateNode(to_id);

        try self.components.append(RuntimeComponent.init(
            .opamp,
            from,
            to,
            1.0, // Placeholder value
        ));
    }

    /// Add a transistor
    pub fn addTransistor(
        self: *CircuitBuilder,
        from_id: []const u8,
        to_id: []const u8,
        beta: f32,
    ) !void {
        const from = try self.getOrCreateNode(from_id);
        const to = try self.getOrCreateNode(to_id);

        try self.components.append(RuntimeComponent.init(
            .transistor,
            from,
            to,
            beta,
        ));
    }

    /// Build the final circuit
    pub fn build(self: *CircuitBuilder) !InternalCircuit {
        const circuit = try InternalCircuit.init(
            self.allocator,
            self.name,
            self.nodes.items.len,
            self.components.items.len,
        );

        // Copy nodes
        @memcpy(circuit.nodes, self.nodes.items);

        // Copy components
        @memcpy(circuit.components, self.components.items);

        return circuit;
    }
};

/// Simple test
pub fn testInternalCircuitFormat() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a simple RC circuit
    var builder = try CircuitBuilder.init(allocator, "RC Low-Pass");
    defer builder.deinit();

    try builder.addResistor("in", "out", 10000.0);
    try builder.addCapacitor("out", "gnd", 100e-9);

    var circuit = try builder.build();
    defer circuit.deinit();

    const stats = circuit.getStats();
    std.debug.assert(stats.node_count == 3);
    std.debug.assert(stats.component_count == 2);
}
