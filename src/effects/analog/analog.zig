/// Analog Circuit Emulator Module
///
/// The analog module provides circuit simulation capabilities by:
/// 1. Parsing KiCAD PCB files to extract circuit topology
/// 2. Emulating component-by-component behavior
/// 3. Processing audio signals through simulated circuits
///
/// Key Features:
/// - Component definitions (resistors, capacitors, inductors, diodes, op-amps, transistors)
/// - KiCAD file parsing for circuit topology extraction
/// - Circuit simulator using nodal analysis
/// - AnalogLoader effect that integrates with the effect chain
/// - Presets for common circuits (filters, distortion, tone stacks)
///
/// Usage:
/// ```zig
/// // From KiCAD file
/// var loader = try AnalogLoader.init(allocator, sample_rate);
/// try loader.loadCircuitFromFile("path/to/circuit.kicad_pcb");
///
/// // Or use preset
/// var loader = try CircuitPresets.rcLowPass(allocator, sample_rate, 1000.0);
///
/// // Process audio
/// loader.processBuffer(&audio_buffer);
/// ```
pub const component_definitions = @import("component_definitions.zig");
pub const kicad_parser = @import("kicad_parser.zig");
pub const circuit_simulator = @import("circuit_simulator.zig");
pub const analog_effect = @import("analog_effect.zig");

pub const AnalogLoader = analog_effect.AnalogLoader;
pub const CircuitPresets = analog_effect.CircuitPresets;
pub const CircuitSimulator = circuit_simulator.CircuitSimulator;
pub const KiCADParser = kicad_parser.KiCADParser;

pub const analog_descriptor = analog_effect.analog_descriptor;
pub const processAnalogBuffer = analog_effect.processAnalogBuffer;
pub const deinitAnalogLoader = analog_effect.deinitAnalogLoader;

// Re-export commonly used component types
pub const Component = component_definitions.Component;
pub const ComponentType = component_definitions.ComponentType;
pub const Resistor = component_definitions.Resistor;
pub const Capacitor = component_definitions.Capacitor;
pub const Inductor = component_definitions.Inductor;
pub const Diode = component_definitions.Diode;
pub const OpAmp = component_definitions.OpAmp;
pub const Transistor = component_definitions.Transistor;
