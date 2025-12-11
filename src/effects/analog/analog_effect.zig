const std = @import("std");
const audio = @import("../../audio.zig");
const ports = @import("../../ports/effects.zig");
const components = @import("component_definitions.zig");
const parser = @import("kicad_parser.zig");
const simulator = @import("circuit_simulator.zig");

/// AnalogLoader effect: Emulates analog circuits from KiCAD files
pub const analog_descriptor: ports.EffectDescriptor = .{
    .id = "analog",
    .name = "Analog Circuit Emulator",
    .description = "Emulates analog circuits from KiCAD PCB files component by component",
    .version = "1.0.0",
    .available_parameters = &.{
        .{
            .name = "input_level",
            .param_type = ports.ParameterType.float,
            .default_value = 1.0,
            .min_value = 0.0,
            .max_value = 2.0,
            .description = "Input signal level (gain)",
        },
        .{
            .name = "output_level",
            .param_type = ports.ParameterType.float,
            .default_value = 1.0,
            .min_value = 0.0,
            .max_value = 2.0,
            .description = "Output signal level (gain)",
        },
        .{
            .name = "bias",
            .param_type = ports.ParameterType.float,
            .default_value = 0.0,
            .min_value = -1.0,
            .max_value = 1.0,
            .description = "DC bias offset",
        },
        .{
            .name = "simulation_quality",
            .param_type = ports.ParameterType.float,
            .default_value = 1.0,
            .min_value = 0.1,
            .max_value = 4.0,
            .description = "Oversampling factor for simulation accuracy",
        },
    },
};

/// AnalogLoader effect processor
pub const AnalogLoader = struct {
    circuit_simulator: simulator.CircuitSimulator,
    input_level: f32,
    output_level: f32,
    bias: f32,
    simulation_quality: f32,
    allocator: std.mem.Allocator,
    circuit_loaded: bool = false,

    /// Initialize AnalogLoader with sample rate
    pub fn init(allocator: std.mem.Allocator, sample_rate: f32) !AnalogLoader {
        return .{
            .circuit_simulator = simulator.CircuitSimulator.init(allocator, sample_rate),
            .input_level = analog_descriptor.available_parameters[0].default_value,
            .output_level = analog_descriptor.available_parameters[1].default_value,
            .bias = analog_descriptor.available_parameters[2].default_value,
            .simulation_quality = analog_descriptor.available_parameters[3].default_value,
            .allocator = allocator,
        };
    }

    /// Load a circuit from a KiCAD PCB file
    pub fn loadCircuitFromFile(self: *AnalogLoader, file_path: []const u8) !void {
        var kicad_parser = parser.KiCADParser.init(self.allocator);
        var parsed_circuit = try kicad_parser.parseFile(file_path);
        defer parsed_circuit.deinit();

        try self.circuit_simulator.loadFromKiCAD(&parsed_circuit);
        self.circuit_loaded = true;
    }

    /// Load a circuit from KiCAD content string
    pub fn loadCircuitFromContent(self: *AnalogLoader, content: []const u8) !void {
        var kicad_parser = parser.KiCADParser.init(self.allocator);
        var parsed_circuit = try kicad_parser.parseContent(content);
        defer parsed_circuit.deinit();

        try self.circuit_simulator.loadFromKiCAD(&parsed_circuit);
        self.circuit_loaded = true;
    }

    /// Manually build a circuit (for testing or programmatic use)
    pub fn buildCircuit(self: *AnalogLoader, builder: *const fn (sim: *simulator.CircuitSimulator) anyerror!void) !void {
        try builder(&self.circuit_simulator);
        self.circuit_loaded = true;
    }

    /// Set a parameter value
    pub fn setParameter(self: *AnalogLoader, name: []const u8, value: f32) void {
        if (std.mem.eql(u8, name, "input_level")) {
            self.input_level = value;
        } else if (std.mem.eql(u8, name, "output_level")) {
            self.output_level = value;
        } else if (std.mem.eql(u8, name, "bias")) {
            self.bias = value;
        } else if (std.mem.eql(u8, name, "simulation_quality")) {
            self.simulation_quality = value;
        }
    }

    /// Get a parameter value
    pub fn getParameter(self: *const AnalogLoader, name: []const u8) ?f32 {
        if (std.mem.eql(u8, name, "input_level")) {
            return self.input_level;
        } else if (std.mem.eql(u8, name, "output_level")) {
            return self.output_level;
        } else if (std.mem.eql(u8, name, "bias")) {
            return self.bias;
        } else if (std.mem.eql(u8, name, "simulation_quality")) {
            return self.simulation_quality;
        }
        return null;
    }

    /// Process a single sample through the circuit
    pub fn processSample(self: *AnalogLoader, sample: f32) f32 {
        if (!self.circuit_loaded) {
            return sample;
        }

        // Apply input level and bias
        var processed = sample * self.input_level + self.bias;

        // Process through circuit
        processed = self.circuit_simulator.processSample(processed, "in");

        // Apply output level
        processed *= self.output_level;

        return processed;
    }

    /// Process audio buffer through the loaded circuit
    pub fn processBuffer(self: *AnalogLoader, buffer: *audio.AudioBuffer) void {
        if (!self.circuit_loaded) {
            return;
        }

        const frame_count = buffer.frameCount();

        for (0..frame_count) |frame| {
            for (0..buffer.channel_count) |ch| {
                const sample = buffer.getSample(frame, @intCast(ch));
                const processed = self.processSample(sample);
                buffer.setSample(frame, @intCast(ch), processed);
            }
        }
    }

    /// Reset circuit state
    pub fn reset(self: *AnalogLoader) void {
        self.circuit_simulator.reset();
    }

    /// Get circuit statistics
    pub fn getCircuitStats(self: *const AnalogLoader) simulator.CircuitStats {
        return self.circuit_simulator.getStats();
    }

    /// Deinitialize the analog loader
    pub fn deinit(self: *AnalogLoader) void {
        self.circuit_simulator.deinit();
    }
};

/// Common circuit patterns (presets)
pub const CircuitPresets = struct {
    /// Simple RC low-pass filter circuit
    pub fn rcLowPass(allocator: std.mem.Allocator, sample_rate: f32, cutoff_freq: f32) !AnalogLoader {
        var loader = try AnalogLoader.init(allocator, sample_rate);

        // For RC filter: fc = 1 / (2 * pi * R * C)
        // Let's use R = 1k, calculate C for desired cutoff
        const pi = std.math.pi;
        const R = 1000.0; // 1k resistor
        const C = 1.0 / (2.0 * pi * cutoff_freq * R);

        try loader.circuit_simulator.addResistor("in", "out", R);
        try loader.circuit_simulator.addCapacitor("out", "gnd", C);

        loader.circuit_loaded = true;
        return loader;
    }

    /// Simple RC high-pass filter circuit
    pub fn rcHighPass(allocator: std.mem.Allocator, sample_rate: f32, cutoff_freq: f32) !AnalogLoader {
        var loader = try AnalogLoader.init(allocator, sample_rate);

        const pi = std.math.pi;
        const C = 100e-9; // 100nF capacitor
        const R = 1.0 / (2.0 * pi * cutoff_freq * C);

        try loader.circuit_simulator.addCapacitor("in", "mid", C);
        try loader.circuit_simulator.addResistor("mid", "gnd", R);
        try loader.circuit_simulator.addResistor("mid", "out", 100.0); // Output coupling

        loader.circuit_loaded = true;
        return loader;
    }

    /// Soft-clipping distortion circuit with diode clipping
    pub fn diodeClipping(allocator: std.mem.Allocator, sample_rate: f32) !AnalogLoader {
        var loader = try AnalogLoader.init(allocator, sample_rate);

        try loader.circuit_simulator.addResistor("in", "clipping", 1000.0); // 1k series resistor
        try loader.circuit_simulator.addDiode("clipping", "gnd"); // Diode to ground
        try loader.circuit_simulator.addResistor("clipping", "out", 1000.0); // Output

        loader.circuit_loaded = true;
        return loader;
    }

    /// Simple tone stack circuit (3-band EQ approximation)
    pub fn toneStack(allocator: std.mem.Allocator, sample_rate: f32) !AnalogLoader {
        var loader = try AnalogLoader.init(allocator, sample_rate);

        // Bass: low-pass filter
        try loader.circuit_simulator.addResistor("in", "bass_node", 10000.0);
        try loader.circuit_simulator.addCapacitor("bass_node", "gnd", 100e-9);

        // Mid: resonant circuit (not fully implemented, simplified)
        try loader.circuit_simulator.addResistor("in", "mid_node", 47000.0);
        try loader.circuit_simulator.addCapacitor("mid_node", "gnd", 10e-9);

        // Treble: high-pass filter
        try loader.circuit_simulator.addCapacitor("in", "treble_node", 10e-9);
        try loader.circuit_simulator.addResistor("treble_node", "gnd", 100000.0);

        loader.circuit_loaded = true;
        return loader;
    }
};

/// Port implementation for the AnalogLoader effect
pub fn createAnalogEffect(
    allocator: std.mem.Allocator,
    sample_rate: f32,
) !*AnalogLoader {
    const effect = try allocator.create(AnalogLoader);
    effect.* = try AnalogLoader.init(allocator, sample_rate);
    return effect;
}

/// Port function: process buffer through analog loader
pub fn processAnalogBuffer(self: *anyopaque, buffer: *audio.AudioBuffer) void {
    const analog_loader: *AnalogLoader = @ptrCast(@alignCast(self));
    analog_loader.processBuffer(buffer);
}

/// Port function: deinitialize analog loader
pub fn deinitAnalogLoader(allocator: std.mem.Allocator, self: *anyopaque) void {
    const analog_loader: *AnalogLoader = @ptrCast(@alignCast(self));
    analog_loader.deinit();
    allocator.destroy(analog_loader);
}

/// Test suite
pub const Tests = struct {
    pub fn testComponentInitialization() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        // Test resistor
        const res = components.Resistor.init(1000.0);
        std.debug.assert(res.resistance == 1000.0);

        // Test capacitor
        const cap = components.Capacitor.init(100e-9);
        std.debug.assert(cap.capacitance == 100e-9);

        // Test diode
        const diode = components.Diode.init();
        const current = diode.currentFromVoltage(0.7);
        std.debug.assert(current > 0);

        _ = allocator;
    }

    pub fn testAnalogLoaderInitialization() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var loader = try AnalogLoader.init(allocator, 44100);
        defer loader.deinit();

        std.debug.assert(loader.input_level == 1.0);
        std.debug.assert(loader.output_level == 1.0);

        loader.setParameter("input_level", 2.0);
        std.debug.assert(loader.getParameter("input_level") == 2.0);
    }

    pub fn testRCFilter() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var loader = try CircuitPresets.rcLowPass(allocator, 44100, 1000.0);
        defer loader.deinit();

        std.debug.assert(loader.circuit_loaded);
        const stats = loader.getCircuitStats();
        std.debug.assert(stats.component_count > 0);
    }
};
