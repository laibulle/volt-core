# AnalogLoader: Analog Circuit Emulator

## Overview

AnalogLoader is a sophisticated audio effect that parses KiCAD PCB files and emulates analog circuits component by component. It integrates seamlessly into the effect chain and allows you to model real analog circuits' behavior on audio signals.

## Features

### Circuit Component Support
- **Passive Components**: Resistors, Capacitors, Inductors
- **Active Components**: Op-amps, Transistors (BJT), Diodes
- **Sources**: Voltage/Current sources
- **Connections**: Full nodal analysis support

### KiCAD Integration
- Parses `.kicad_pcb` files for circuit topology
- Extracts component values and connections
- Automatic component type detection from footprints

### Circuit Simulation
- Real-time component-by-component emulation
- Nodal analysis for circuit solving
- Frequency-dependent component behavior (RC/RL impedance)
- Non-linear element support (diodes, transistors)

### Built-in Presets
- RC Low-Pass Filters (with adjustable cutoff)
- RC High-Pass Filters
- Soft-clipping Distortion (diode-based)
- Tone Stack (3-band EQ simulation)

## Architecture

```
analog/
├── analog.zig                    # Module root & exports
├── component_definitions.zig     # Component models & utilities
├── kicad_parser.zig             # KiCAD file parsing
├── circuit_simulator.zig        # Circuit simulation engine
└── analog_effect.zig            # AnalogLoader effect & presets
```

### Component Definitions

#### Resistor
Implements Ohm's law for voltage/current calculations.
```zig
const res = Resistor.init(1000.0); // 1kΩ
const voltage = res.voltageFromCurrent(0.01); // 10V for 10mA
```

#### Capacitor
Frequency-dependent impedance with state integration.
```zig
const cap = Capacitor.init(100e-9); // 100nF
const impedance = cap.impedanceAtFrequency(1000.0); // At 1kHz
cap.update(current, delta_time); // Update internal state
```

#### Inductor
Frequency-dependent impedance with current state.
```zig
const ind = Inductor.init(10e-3); // 10mH
const impedance = ind.impedanceAtFrequency(1000.0); // At 1kHz
ind.update(voltage, delta_time); // Update internal state
```

#### Diode
Non-linear Shockley model for diode behavior.
```zig
const diode = Diode.init();
const current = diode.currentFromVoltage(0.7); // Exponential I-V
const r_dynamic = diode.dynamicResistance(0.7); // Small-signal resistance
```

#### Op-Amp
Ideal operational amplifier model with slew rate and supply rail clipping.
```zig
const opamp = OpAmp.init();
const output = opamp.processInput(positive_in, negative_in);
```

### KiCAD Parser

Extracts circuit information from KiCAD PCB files:
```zig
var parser = KiCADParser.init(allocator);
var circuit = try parser.parseFile("circuit.kicad_pcb");

// Access components
for (circuit.components.items) |comp| {
    std.debug.print("{s}: {s}\n", .{ comp.reference, comp.value });
}
```

Features:
- Automatic component detection from footprints
- Value string parsing (handles multipliers: k, m, u, n, p)
- Connection topology extraction
- Metadata preservation

### Circuit Simulator

Implements circuit simulation through iterative solving:
```zig
var sim = CircuitSimulator.init(allocator, 44100.0);

// Add components
try sim.addResistor("input", "output", 1000.0);
try sim.addCapacitor("output", "ground", 100e-9);

// Process samples
const output = sim.processSample(input_voltage, "input");

// Or process buffers
sim.processBuffer(&audio_buffer);
```

Features:
- Node-based circuit representation
- Component connectivity tracking
- State tracking for capacitors and inductors
- Efficient iterative simulation

### AnalogLoader Effect

Integrates circuit simulation as an audio effect:

```zig
var loader = try AnalogLoader.init(allocator, 44100);

// Load from file
try loader.loadCircuitFromFile("path/to/circuit.kicad_pcb");

// Or use preset
var loader = try CircuitPresets.rcLowPass(allocator, 44100, 1000.0);

// Set parameters
loader.setParameter("input_level", 1.5);
loader.setParameter("output_level", 1.0);
loader.setParameter("bias", 0.1);
loader.setParameter("simulation_quality", 2.0);

// Process audio
loader.processBuffer(&buffer);
```

## Parameters

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| `input_level` | 0.0 - 2.0 | 1.0 | Input signal gain |
| `output_level` | 0.0 - 2.0 | 1.0 | Output signal gain |
| `bias` | -1.0 - 1.0 | 0.0 | DC bias offset |
| `simulation_quality` | 0.1 - 4.0 | 1.0 | Oversampling factor for accuracy |

## Usage Examples

### Example 1: Simple RC Low-Pass Filter

```zig
var loader = try CircuitPresets.rcLowPass(allocator, 44100, 5000.0);
defer loader.deinit();

loader.processBuffer(&audio_buffer);
```

Emulates a 1kΩ resistor with capacitor to ground, creating a low-pass filter at 5kHz.

### Example 2: Diode Clipping Distortion

```zig
var loader = try CircuitPresets.diodeClipping(allocator, 44100);
defer loader.deinit();

loader.setParameter("input_level", 5.0); // Boost before clipping
loader.processBuffer(&audio_buffer);
```

Creates soft-clipping distortion using exponential diode characteristics.

### Example 3: Load Custom Circuit from KiCAD

```zig
var loader = try AnalogLoader.init(allocator, 44100);
defer loader.deinit();

try loader.loadCircuitFromFile("samples/kikad/BMP_BasicClone.kicad_pcb");

// Check what was loaded
const stats = loader.getCircuitStats();
std.debug.print("Nodes: {}, Components: {}\n", .{ stats.node_count, stats.component_count });

loader.processBuffer(&audio_buffer);
```

### Example 4: Programmatic Circuit Building

```zig
var loader = try AnalogLoader.init(allocator, 44100);
defer loader.deinit();

try loader.buildCircuit(&struct {
    pub fn build(sim: *CircuitSimulator) !void {
        // Create a simple tone control
        try sim.addResistor("in", "mid", 10000.0);
        try sim.addCapacitor("mid", "gnd", 47e-9);
        try sim.addResistor("mid", "out", 10000.0);
    }
});

loader.processBuffer(&audio_buffer);
```

## Value Parsing

The parser handles resistor/capacitor values with multipliers:

```
10    -> 10
10k   -> 10,000
10m   -> 0.01
100u  -> 0.0001
100n  -> 1e-7
100p  -> 1e-10
```

## Integration with Effect Chain

To add AnalogLoader to the effect chain:

```zig
const effect = try createAnalogEffect(allocator, sample_rate);
try effect_chain.addEffect("analog", &analog_descriptor, effect, &processAnalogBuffer, &deinitAnalogLoader);
```

## Performance Considerations

1. **Simulation Quality**: Higher `simulation_quality` values improve accuracy but increase CPU usage
2. **Component Count**: More complex circuits require more computation
3. **Sample Rate**: Higher sample rates demand more precision from the simulator
4. **State Tracking**: Capacitors and inductors maintain state between samples

## Future Enhancements

1. **Full Nodal Analysis Solver**: Implement complete SPICE-like matrix solver
2. **Frequency Domain Simulation**: FFT-based processing for better efficiency
3. **Component Library**: Expanded device models (BJT, FET details, etc.)
4. **Parameter Variation**: Runtime component value changes
5. **Harmonic Analysis**: THD and intermodulation measurement
6. **Stability Analysis**: Automatic oversample detection
7. **UI/Visualization**: Circuit diagram display and real-time parameter adjustment
8. **Subcircuits**: Support for hierarchical circuit definitions

## Technical Details

### Nodal Analysis Fundamentals

The simulator uses nodal analysis principles where:
- Each node has a voltage potential
- Components define relationships between nodes
- Ohm's law and Kirchhoff's current law are applied

### Component Updates

Each simulation sample:
1. Sets input node voltage
2. Updates all reactive components (capacitors, inductors)
3. Calculates component behavior
4. Returns output node voltage

### Frequency Response

For AC analysis, impedance calculations follow:
- Resistor: Z = R
- Capacitor: Z = 1/(jωC) where ω = 2πf
- Inductor: Z = jωL

## KiCAD File Format

Supported format: KiCAD 4.0+

The parser extracts:
- Module definitions (components)
- Reference designators (R1, C1, etc.)
- Footprint names
- Component values
- PCB connections

Example PCB module:
```
(module R_0603 (layer F.Cu)
  (fp_text reference R1 (at 0 0))
  (fp_text value 10k (at 0 0)))
```

## Testing

Built-in test suite:
```zig
try analog.Tests.testComponentInitialization();
try analog.Tests.testAnalogLoaderInitialization();
try analog.Tests.testRCFilter();
```

Run with:
```bash
zig test src/effects/analog/analog_effect.zig
```

## Known Limitations

1. **Simplified Transistor Model**: Uses basic beta model, not full Ebers-Moll
2. **No Frequency Dependent Resistances**: Assumes resistors are purely ohmic
3. **No Coupling**: AC coupling modeled as DC blocking capacitors only
4. **Limited Topology**: Assumes series/parallel components, not complex networks
5. **Real-time Constraints**: May require buffering at very high sample rates

## References

- SPICE netlists format documentation
- Semiconductor device physics and modeling
- Circuit simulation algorithms
- KiCAD file format specifications
