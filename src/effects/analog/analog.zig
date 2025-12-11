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
pub const circuit_format = @import("circuit_format.zig");
pub const kicad_parser = @import("kicad_parser.zig");
pub const circuit_simulator = @import("circuit_simulator.zig");
pub const analog_effect = @import("analog_effect.zig");
pub const components = @import("components.zig");
pub const component_library = @import("component_library.zig");

pub const AnalogLoader = analog_effect.AnalogLoader;
pub const CircuitPresets = analog_effect.CircuitPresets;
pub const CircuitSimulator = circuit_simulator.CircuitSimulator;
pub const KiCADParser = kicad_parser.KiCADParser;
pub const InternalCircuit = circuit_format.InternalCircuit;
pub const CircuitBuilder = circuit_format.CircuitBuilder;
pub const ComponentLibrary = component_library.ComponentLibrary;
pub const SignalProcessor = component_library.SignalProcessor;
pub const CircuitLibraryPresets = component_library.CircuitPresets;

pub const analog_descriptor = analog_effect.analog_descriptor;
pub const processAnalogBuffer = analog_effect.processAnalogBuffer;
pub const deinitAnalogLoader = analog_effect.deinitAnalogLoader;

// Re-export commonly used component types from both modules
pub const Component = component_definitions.Component;
pub const ComponentType = component_definitions.ComponentType;
pub const ResistorDef = component_definitions.Resistor;
pub const CapacitorDef = component_definitions.Capacitor;
pub const InductorDef = component_definitions.Inductor;
pub const DiodeDef = component_definitions.Diode;
pub const OpAmpDef = component_definitions.OpAmp;
pub const TransistorDef = component_definitions.Transistor;

// Re-export signal processing component types
pub const Resistor = components.Resistor;
pub const Capacitor = components.Capacitor;
pub const Inductor = components.Inductor;
pub const Diode = components.Diode;
pub const OpAmp = components.OpAmp;
pub const Transistor = components.Transistor;
pub const ComponentValue = components.ComponentValue;
