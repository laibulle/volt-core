const std = @import("std");
const components = @import("components/mod.zig");

const Resistor = components.Resistor;
const Capacitor = components.Capacitor;
const Inductor = components.Inductor;
const Diode = components.Diode;
const OpAmp = components.OpAmp;
const Transistor = components.Transistor;

/// Component library for building circuits
/// Manages collections of components with signal processing
pub const ComponentLibrary = struct {
    allocator: std.mem.Allocator,
    resistors: std.ArrayList(Resistor),
    capacitors: std.ArrayList(Capacitor),
    inductors: std.ArrayList(Inductor),
    diodes: std.ArrayList(Diode),
    opamps: std.ArrayList(OpAmp),
    transistors: std.ArrayList(Transistor),
    sample_rate: f32 = 44100.0,

    pub fn init(allocator: std.mem.Allocator) ComponentLibrary {
        return ComponentLibrary{
            .allocator = allocator,
            .resistors = std.ArrayList(Resistor).init(allocator),
            .capacitors = std.ArrayList(Capacitor).init(allocator),
            .inductors = std.ArrayList(Inductor).init(allocator),
            .diodes = std.ArrayList(Diode).init(allocator),
            .opamps = std.ArrayList(OpAmp).init(allocator),
            .transistors = std.ArrayList(Transistor).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentLibrary) void {
        self.resistors.deinit();
        self.capacitors.deinit();
        self.inductors.deinit();
        self.diodes.deinit();
        self.opamps.deinit();
        self.transistors.deinit();
    }

    pub fn setSampleRate(self: *ComponentLibrary, sample_rate: f32) void {
        self.sample_rate = sample_rate;
    }

    // Resistor operations
    pub fn addResistor(self: *ComponentLibrary, resistance_ohms: f32) !usize {
        try self.resistors.append(Resistor.init(resistance_ohms));
        return self.resistors.items.len - 1;
    }

    pub fn resistorAtIndex(self: *ComponentLibrary, index: usize) ?*Resistor {
        if (index < self.resistors.items.len) {
            return &self.resistors.items[index];
        }
        return null;
    }

    // Capacitor operations
    pub fn addCapacitor(self: *ComponentLibrary, capacitance_farads: f32) !usize {
        try self.capacitors.append(Capacitor.init(capacitance_farads));
        return self.capacitors.items.len - 1;
    }

    pub fn capacitorAtIndex(self: *ComponentLibrary, index: usize) ?*Capacitor {
        if (index < self.capacitors.items.len) {
            return &self.capacitors.items[index];
        }
        return null;
    }

    // Inductor operations
    pub fn addInductor(self: *ComponentLibrary, inductance_henries: f32) !usize {
        try self.inductors.append(Inductor.init(inductance_henries));
        return self.inductors.items.len - 1;
    }

    pub fn inductorAtIndex(self: *ComponentLibrary, index: usize) ?*Inductor {
        if (index < self.inductors.items.len) {
            return &self.inductors.items[index];
        }
        return null;
    }

    // Diode operations
    pub fn addDiode(self: *ComponentLibrary) !usize {
        try self.diodes.append(Diode.init());
        return self.diodes.items.len - 1;
    }

    pub fn diodeAtIndex(self: *ComponentLibrary, index: usize) ?*Diode {
        if (index < self.diodes.items.len) {
            return &self.diodes.items[index];
        }
        return null;
    }

    // OpAmp operations
    pub fn addOpAmp(self: *ComponentLibrary, gain: f32, bandwidth: f32) !usize {
        try self.opamps.append(OpAmp.init(gain, bandwidth));
        return self.opamps.items.len - 1;
    }

    pub fn opampAtIndex(self: *ComponentLibrary, index: usize) ?*OpAmp {
        if (index < self.opamps.items.len) {
            return &self.opamps.items[index];
        }
        return null;
    }

    // Transistor operations
    pub fn addTransistor(self: *ComponentLibrary, typ: Transistor.Type, beta: f32) !usize {
        try self.transistors.append(Transistor.init(typ, beta));
        return self.transistors.items.len - 1;
    }

    pub fn transistorAtIndex(self: *ComponentLibrary, index: usize) ?*Transistor {
        if (index < self.transistors.items.len) {
            return &self.transistors.items[index];
        }
        return null;
    }

    // Statistics
    pub fn componentCount(self: ComponentLibrary) usize {
        return self.resistors.items.len + self.capacitors.items.len +
            self.inductors.items.len + self.diodes.items.len +
            self.opamps.items.len + self.transistors.items.len;
    }

    pub fn resistorCount(self: ComponentLibrary) usize {
        return self.resistors.items.len;
    }

    pub fn capacitorCount(self: ComponentLibrary) usize {
        return self.capacitors.items.len;
    }

    pub fn inductorCount(self: ComponentLibrary) usize {
        return self.inductors.items.len;
    }

    pub fn diodeCount(self: ComponentLibrary) usize {
        return self.diodes.items.len;
    }

    pub fn opampCount(self: ComponentLibrary) usize {
        return self.opamps.items.len;
    }

    pub fn transistorCount(self: ComponentLibrary) usize {
        return self.transistors.items.len;
    }
};

/// Preset circuits built from the component library
pub const CircuitPresets = struct {
    /// RC Low-pass filter
    /// Attenuates high frequencies
    pub fn rcLowPass(allocator: std.mem.Allocator, sample_rate: f32, cutoff_freq: f32) !ComponentLibrary {
        var lib = ComponentLibrary.init(allocator);
        lib.setSampleRate(sample_rate);

        // Calculate component values for RC low-pass
        // f_c = 1 / (2 * pi * R * C)
        // Choose R = 10k, solve for C
        const r = 10000.0;
        const c = 1.0 / (2.0 * std.math.pi * cutoff_freq * r);

        _ = try lib.addResistor(r);
        _ = try lib.addCapacitor(c);

        return lib;
    }

    /// RC High-pass filter
    /// Blocks low frequencies
    pub fn rcHighPass(allocator: std.mem.Allocator, sample_rate: f32, cutoff_freq: f32) !ComponentLibrary {
        var lib = ComponentLibrary.init(allocator);
        lib.setSampleRate(sample_rate);

        // Same as low-pass but components are oriented differently
        const r = 10000.0;
        const c = 1.0 / (2.0 * std.math.pi * cutoff_freq * r);

        _ = try lib.addCapacitor(c);
        _ = try lib.addResistor(r);

        return lib;
    }

    /// Diode clipping circuit
    /// Creates asymmetric clipping for distortion
    pub fn diodeClipping(allocator: std.mem.Allocator, sample_rate: f32) !ComponentLibrary {
        var lib = ComponentLibrary.init(allocator);
        lib.setSampleRate(sample_rate);

        // Input coupling
        _ = try lib.addCapacitor(1e-6); // 1µF

        // Input resistor
        _ = try lib.addResistor(1000.0); // 1k

        // Clipping diodes (forward and reverse biased)
        _ = try lib.addDiode();
        _ = try lib.addDiode();

        // Load resistor
        _ = try lib.addResistor(10000.0); // 10k

        return lib;
    }

    /// Simple transistor amplifier
    /// Provides gain and distortion
    pub fn transistorAmp(allocator: std.mem.Allocator, sample_rate: f32, _: f32) !ComponentLibrary {
        var lib = ComponentLibrary.init(allocator);
        lib.setSampleRate(sample_rate);

        // Biasing resistors
        _ = try lib.addResistor(1e6); // 1M base bias
        _ = try lib.addResistor(10000.0); // 10k emitter

        // Coupling capacitor
        _ = try lib.addCapacitor(1e-6); // 1µF

        // Output transistor
        _ = try lib.addTransistor(.npn, 200.0); // BC549 typical beta

        // Load resistor for collector
        _ = try lib.addResistor(5600.0); // 5.6k

        return lib;
    }

    /// Tone stack circuit (simplified)
    /// Three-band EQ-like control
    pub fn toneStack(allocator: std.mem.Allocator, sample_rate: f32) !ComponentLibrary {
        var lib = ComponentLibrary.init(allocator);
        lib.setSampleRate(sample_rate);

        // Bass control (low-pass)
        _ = try lib.addResistor(1000.0); // 1k series
        _ = try lib.addCapacitor(100e-9); // 100n

        // Mid control
        _ = try lib.addResistor(10000.0); // 10k series
        _ = try lib.addCapacitor(10e-9); // 10n

        // Treble control (high-pass)
        _ = try lib.addCapacitor(1e-9); // 1n series
        _ = try lib.addResistor(1e6); // 1M load

        return lib;
    }

    /// Simple Fuzz Face style circuit
    pub fn fuzzFace(allocator: std.mem.Allocator, sample_rate: f32) !ComponentLibrary {
        var lib = ComponentLibrary.init(allocator);
        lib.setSampleRate(sample_rate);

        // Input coupling
        _ = try lib.addCapacitor(1e-6); // 1µF

        // First transistor stage
        _ = try lib.addTransistor(.npn, 200.0);
        _ = try lib.addResistor(100000.0); // 100k collector load
        _ = try lib.addCapacitor(10e-9); // 10n coupling

        // Second transistor stage
        _ = try lib.addTransistor(.npn, 200.0);
        _ = try lib.addResistor(100000.0); // 100k collector load

        // Diode clipping
        _ = try lib.addDiode();

        // Output coupling
        _ = try lib.addCapacitor(2.2e-6); // 2.2µF

        return lib;
    }
};

/// Signal processing with component library
pub const SignalProcessor = struct {
    library: ComponentLibrary,
    dt: f32, // sample time

    pub fn init(library: ComponentLibrary) SignalProcessor {
        const dt = 1.0 / library.sample_rate;
        return SignalProcessor{
            .library = library,
            .dt = dt,
        };
    }

    /// Process audio buffer through resistor voltage divider
    pub fn processResistorDivider(self: SignalProcessor, input: []f32, output: []f32, r1_index: usize, r2_index: usize) !void {
        if (input.len != output.len) return error.LengthMismatch;
        if (input.len == 0) return;

        const r1 = self.library.resistorAtIndex(r1_index) orelse return error.InvalidIndex;
        const r2_resistance = if (self.library.resistorAtIndex(r2_index)) |r2| r2.resistance else 10000.0;

        for (input, output) |sample, *out_ptr| {
            out_ptr.* = r1.processSignal(sample, r2_resistance);
        }
    }

    /// Process audio buffer through capacitor (high-pass filter)
    pub fn processCapacitorFilter(self: SignalProcessor, input: []f32, output: []f32, cap_index: usize, load_r: f32) !void {
        if (input.len != output.len) return error.LengthMismatch;
        if (input.len == 0) return;

        const cap = self.library.capacitorAtIndex(cap_index) orelse return error.InvalidIndex;

        for (input, output) |sample, *out_ptr| {
            out_ptr.* = cap.processSignal(sample, self.dt, load_r);
        }
    }

    /// Process audio buffer through diode clipper
    pub fn processDiodeClipper(self: SignalProcessor, input: []f32, output: []f32, diode_index: usize) !void {
        if (input.len != output.len) return error.LengthMismatch;
        if (input.len == 0) return;

        const diode = self.library.diodeAtIndex(diode_index) orelse return error.InvalidIndex;

        for (input, output) |sample, *out_ptr| {
            out_ptr.* = diode.softClip(sample);
        }
    }

    /// Process audio buffer through transistor amplifier
    pub fn processTransistorAmp(self: SignalProcessor, input: []f32, output: []f32, transistor_index: usize, gain_mul: f32) !void {
        if (input.len != output.len) return error.LengthMismatch;
        if (input.len == 0) return;

        const transistor = self.library.transistorAtIndex(transistor_index) orelse return error.InvalidIndex;

        for (input, output) |sample, *out_ptr| {
            const amplified = sample * gain_mul;
            out_ptr.* = transistor.distort(amplified);
        }
    }

    /// Process audio buffer through opamp
    pub fn processOpAmp(self: SignalProcessor, input: []f32, output: []f32, opamp_index: usize, feedback_r: f32, input_r: f32) !void {
        if (input.len != output.len) return error.LengthMismatch;
        if (input.len == 0) return;

        const opamp = self.library.opampAtIndex(opamp_index) orelse return error.InvalidIndex;

        for (input, output) |sample, *out_ptr| {
            out_ptr.* = opamp.nonInvertingGain(sample, feedback_r, input_r);
        }
    }
};

const testing = std.testing;

test "component library resistor" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lib = ComponentLibrary.init(allocator);
    defer lib.deinit();

    const idx = try lib.addResistor(10000.0);
    try testing.expectEqual(@as(usize, 0), idx);
    try testing.expectEqual(@as(usize, 1), lib.resistorCount());

    const r = lib.resistorAtIndex(0);
    try testing.expect(r != null);
    try testing.expectApproxEqAbs(10000.0, r.?.resistance, 1.0);
}

test "component library preset RC low-pass" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lib = try CircuitPresets.rcLowPass(allocator, 44100, 1000.0);
    defer lib.deinit();

    try testing.expectEqual(@as(usize, 1), lib.resistorCount());
    try testing.expectEqual(@as(usize, 1), lib.capacitorCount());
}

test "component library total count" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lib = ComponentLibrary.init(allocator);
    defer lib.deinit();

    _ = try lib.addResistor(10000.0);
    _ = try lib.addCapacitor(1e-6);
    _ = try lib.addDiode();

    try testing.expectEqual(@as(usize, 3), lib.componentCount());
}

test "signal processor resistor divider" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lib = ComponentLibrary.init(allocator);
    defer lib.deinit();

    _ = try lib.addResistor(10000.0); // R1
    _ = try lib.addResistor(10000.0); // R2

    var processor = SignalProcessor.init(lib);

    var input = [_]f32{1.0};
    var output = [_]f32{0.0};

    try processor.processResistorDivider(&input, &output, 0, 1);

    // With equal resistors: 1.0 * (10k / 20k) = 0.5
    try testing.expectApproxEqAbs(0.5, output[0], 0.01);
}
