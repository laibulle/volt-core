const std = @import("std");
const audio = @import("../../audio.zig");

/// Component types that can be emulated in an analog circuit
pub const ComponentType = enum {
    /// Passive: Resistor (impedance in ohms)
    resistor,
    /// Passive: Capacitor (capacitance in farads)
    capacitor,
    /// Passive: Inductor (inductance in henries)
    inductor,
    /// Active: Op-amp (ideal operational amplifier)
    opamp,
    /// Active: Transistor (BJT/FET)
    transistor,
    /// Active: Diode (non-linear element)
    diode,
    /// Utility: Voltage/Current source
    source,
    /// Utility: Ground node
    ground,
};

/// Resistor component
/// Implements Ohm's law: V = I * R
pub const Resistor = struct {
    /// Resistance in ohms
    resistance: f32,

    pub fn init(resistance: f32) Resistor {
        return .{ .resistance = resistance };
    }

    /// Calculate voltage drop given current
    pub fn voltageFromCurrent(self: *const Resistor, current: f32) f32 {
        return current * self.resistance;
    }

    /// Calculate current given voltage
    pub fn currentFromVoltage(self: *const Resistor, voltage: f32) f32 {
        if (self.resistance == 0) return 0.0;
        return voltage / self.resistance;
    }
};

/// Capacitor component with frequency-dependent behavior
/// Impedance: Z = 1 / (2 * pi * f * C)
pub const Capacitor = struct {
    /// Capacitance in farads
    capacitance: f32,
    /// Internal voltage state for integration
    voltage_state: f32 = 0.0,

    pub fn init(capacitance: f32) Capacitor {
        return .{
            .capacitance = capacitance,
            .voltage_state = 0.0,
        };
    }

    /// Calculate impedance at a given frequency
    pub fn impedanceAtFrequency(self: *const Capacitor, frequency: f32) f32 {
        const pi = std.math.pi;
        const omega = 2.0 * pi * frequency;
        if (self.capacitance == 0) return 1e10; // Very high impedance
        return 1.0 / (omega * self.capacitance);
    }

    /// Update capacitor state with given current and delta time
    pub fn update(self: *Capacitor, current: f32, delta_time: f32) void {
        if (self.capacitance > 0) {
            self.voltage_state += current * delta_time / self.capacitance;
        }
    }

    /// Get voltage across capacitor
    pub fn voltage(self: *const Capacitor) f32 {
        return self.voltage_state;
    }
};

/// Inductor component with frequency-dependent behavior
/// Impedance: Z = 2 * pi * f * L
pub const Inductor = struct {
    /// Inductance in henries
    inductance: f32,
    /// Internal current state for integration
    current_state: f32 = 0.0,

    pub fn init(inductance: f32) Inductor {
        return .{
            .inductance = inductance,
            .current_state = 0.0,
        };
    }

    /// Calculate impedance at a given frequency
    pub fn impedanceAtFrequency(self: *const Inductor, frequency: f32) f32 {
        const pi = std.math.pi;
        const omega = 2.0 * pi * frequency;
        return omega * self.inductance;
    }

    /// Update inductor state with given voltage and delta time
    pub fn update(self: *Inductor, voltage: f32, delta_time: f32) void {
        if (self.inductance > 0) {
            self.current_state += voltage * delta_time / self.inductance;
        }
    }

    /// Get current through inductor
    pub fn current(self: *const Inductor) f32 {
        return self.current_state;
    }
};

/// Operational Amplifier (ideal model)
/// Models basic op-amp behavior: high input impedance, low output impedance
pub const OpAmp = struct {
    /// Open-loop gain
    gain: f32 = 100000.0,
    /// Supply voltage (positive)
    vcc: f32 = 15.0,
    /// Supply voltage (negative)
    vee: f32 = -15.0,
    /// Output impedance
    output_impedance: f32 = 75.0,
    /// Feedback configuration type
    feedback_type: FeedbackType = .open_loop,

    pub const FeedbackType = enum {
        open_loop,
        negative_feedback,
        unity_gain,
    };

    pub fn init() OpAmp {
        return .{};
    }

    /// Calculate output voltage given input
    /// Simplified model: clips at supply rails
    pub fn processInput(self: *const OpAmp, positive_input: f32, negative_input: f32) f32 {
        const diff = positive_input - negative_input;
        var output = diff * self.gain;

        // Clip to supply rails
        if (output > self.vcc) output = self.vcc;
        if (output < self.vee) output = self.vee;

        return output;
    }
};

/// Diode component (non-linear)
/// Simple model using exponential I-V relationship
pub const Diode = struct {
    /// Reverse saturation current (A)
    is: f32 = 1e-14,
    /// Thermal voltage (V) at room temperature ≈ 0.026V
    vt: f32 = 0.026,
    /// Series resistance (ohms)
    rs: f32 = 1.0,

    pub fn init() Diode {
        return .{};
    }

    /// Simplified Shockley diode equation: I = Is * (exp(V/Vt) - 1)
    pub fn currentFromVoltage(self: *const Diode, voltage: f32) f32 {
        const exp_arg = voltage / self.vt;
        // Clip exponential to prevent overflow
        const clipped_arg = if (exp_arg > 100) 100 else exp_arg;
        return self.is * (@exp(clipped_arg) - 1.0);
    }

    /// Calculate dynamic resistance at a given operating point
    pub fn dynamicResistance(self: *const Diode, voltage: f32) f32 {
        const current = self.currentFromVoltage(voltage);
        if (current < 1e-9) return 1e10; // Very high resistance for zero current
        return self.vt / current;
    }
};

/// Transistor component (simplified BJT model)
pub const Transistor = struct {
    /// Beta (current gain)
    beta: f32 = 100.0,
    /// Vbe threshold (base-emitter voltage) ≈ 0.7V for silicon
    vbe_threshold: f32 = 0.7,
    /// Type of transistor
    transistor_type: TransistorType = .npn,

    pub const TransistorType = enum {
        npn,
        pnp,
    };

    pub fn init(transistor_type: TransistorType) Transistor {
        return .{
            .transistor_type = transistor_type,
        };
    }

    /// Simplified Ebers-Moll model
    /// Calculate collector current given base current and Vbe
    pub fn collectorCurrent(self: *const Transistor, vbe: f32, ib: f32) f32 {
        if (vbe < self.vbe_threshold) {
            return 0.0; // Below threshold, transistor is off
        }
        return ib * self.beta;
    }
};

/// Generic circuit node containing voltage state
pub const Node = struct {
    /// Node identifier
    id: []const u8,
    /// Current voltage at node
    voltage: f32 = 0.0,
    /// Connected components (indices into circuit's component array)
    connected_components: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator, id: []const u8) !Node {
        return .{
            .id = try allocator.dupe(u8, id),
            .connected_components = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        self.connected_components.deinit();
    }
};

/// Generic component wrapper for heterogeneous component storage
pub const Component = union(ComponentType) {
    resistor: Resistor,
    capacitor: Capacitor,
    inductor: Inductor,
    opamp: OpAmp,
    transistor: Transistor,
    diode: Diode,
    source: Source,
    ground: Ground,

    pub fn getType(self: *const Component) ComponentType {
        return @as(ComponentType, self.*);
    }
};

/// Voltage or current source
pub const Source = struct {
    /// Source type
    source_type: SourceType = .voltage,
    /// Current value (for AC analysis, this is magnitude/phase)
    value: f32 = 0.0,
    /// Frequency for AC sources
    frequency: f32 = 1000.0,

    pub const SourceType = enum {
        voltage,
        current,
    };

    pub fn init(source_type: SourceType, value: f32) Source {
        return .{
            .source_type = source_type,
            .value = value,
        };
    }
};

/// Ground reference node
pub const Ground = struct {
    /// Ground nodes always have 0V potential
    voltage: f32 = 0.0,

    pub fn init() Ground {
        return .{};
    }
};

/// Circuit connection information
pub const Connection = struct {
    /// From node index
    from_node: usize,
    /// To node index
    to_node: usize,
    /// Component index
    component_index: usize,

    pub fn init(from_node: usize, to_node: usize, component_index: usize) Connection {
        return .{
            .from_node = from_node,
            .to_node = to_node,
            .component_index = component_index,
        };
    }
};

/// KiCAD footprint value lookup
/// Maps KiCAD component properties to electrical parameters
pub const ComponentValue = struct {
    /// Reference designation (e.g., "R1", "C10")
    reference: []const u8,
    /// Component value string (e.g., "10k", "100n")
    value: []const u8,
    /// Parsed numerical value
    numerical_value: f32,
    /// Unit string (e.g., "Ω", "F", "H")
    unit: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        reference: []const u8,
        value: []const u8,
    ) !ComponentValue {
        const parsed = try parseValue(allocator, value);
        return .{
            .reference = try allocator.dupe(u8, reference),
            .value = try allocator.dupe(u8, value),
            .numerical_value = parsed.value,
            .unit = try allocator.dupe(u8, parsed.unit),
        };
    }

    pub fn deinit(self: *ComponentValue, allocator: std.mem.Allocator) void {
        allocator.free(self.reference);
        allocator.free(self.value);
        allocator.free(self.unit);
    }
};

/// Parse component value string with multipliers
/// e.g., "10k" -> 10000, "100n" -> 100e-9
pub const ParsedValue = struct {
    value: f32,
    unit: []const u8,
};

pub fn parseValue(allocator: std.mem.Allocator, value_str: []const u8) !ParsedValue {
    var trimmed = std.mem.trim(u8, value_str, " \t");
    if (trimmed.len == 0) {
        return ParsedValue{ .value = 1.0, .unit = "" };
    }

    // Extract multiplier from the end
    const last_char = trimmed[trimmed.len - 1];
    var multiplier: f32 = 1.0;
    var unit: []const u8 = "";

    if (last_char == 'k' or last_char == 'K') {
        multiplier = 1000.0;
        unit = "k";
        trimmed = trimmed[0 .. trimmed.len - 1];
    } else if (last_char == 'm' or last_char == 'M') {
        multiplier = 0.001;
        unit = "m";
        trimmed = trimmed[0 .. trimmed.len - 1];
    } else if (last_char == 'u' or last_char == 'μ') {
        multiplier = 1e-6;
        unit = "μ";
        trimmed = trimmed[0 .. trimmed.len - 1];
    } else if (last_char == 'n' or last_char == 'N') {
        multiplier = 1e-9;
        unit = "n";
        trimmed = trimmed[0 .. trimmed.len - 1];
    } else if (last_char == 'p' or last_char == 'P') {
        multiplier = 1e-12;
        unit = "p";
        trimmed = trimmed[0 .. trimmed.len - 1];
    }

    const parsed = try std.fmt.parseFloat(f32, trimmed);
    return ParsedValue{
        .value = parsed * multiplier,
        .unit = try allocator.dupe(u8, unit),
    };
}
