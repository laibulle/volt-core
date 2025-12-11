# Analog Module

The `analog` module provides real-time emulation of analog circuits for audio processing. It parses KiCAD PCB files and simulates circuit behavior component by component.

## Quick Start

### Load a Circuit from KiCAD

```zig
const analog = @import("analog/analog.zig");

var loader = try analog.AnalogLoader.init(allocator, 44100);
defer loader.deinit();

try loader.loadCircuitFromFile("path/to/circuit.kicad_pcb");
loader.processBuffer(&audio_buffer);
```

### Use a Preset Circuit

```zig
// RC Low-Pass Filter at 1kHz
var loader = try analog.CircuitPresets.rcLowPass(allocator, 44100, 1000.0);
defer loader.deinit();

loader.setParameter("input_level", 1.5);
loader.processBuffer(&audio_buffer);
```

## Module Structure

| File | Purpose |
|------|---------|
| `analog.zig` | Module root and public API |
| `component_definitions.zig` | Component models (R, L, C, diode, op-amp, transistor) |
| `kicad_parser.zig` | KiCAD PCB file parser |
| `circuit_simulator.zig` | Circuit simulation engine using nodal analysis |
| `analog_effect.zig` | AnalogLoader effect and presets |

## Key Types

### AnalogLoader
Main effect processor that loads and simulates circuits.

**Methods:**
- `init(allocator, sample_rate)` - Initialize with sample rate
- `loadCircuitFromFile(path)` - Load KiCAD file
- `loadCircuitFromContent(content)` - Load from string content
- `buildCircuit(builder_fn)` - Programmatically define circuit
- `setParameter(name, value)` - Set effect parameter
- `getParameter(name)` - Get parameter value
- `processBuffer(buffer)` - Process audio buffer
- `reset()` - Reset circuit state
- `getCircuitStats()` - Get component/node counts
- `deinit()` - Clean up resources

### CircuitSimulator
Low-level circuit simulation engine.

**Methods:**
- `init(allocator, sample_rate)`
- `addResistor(from, to, resistance)`
- `addCapacitor(from, to, capacitance)`
- `addInductor(from, to, inductance)`
- `addDiode(from, to)`
- `addOpAmp()`
- `processSample(input, node_id)` - Process single sample
- `processBuffer(buffer)` - Process audio buffer
- `reset()` - Reset all component states
- `deinit()`

### Component Types

Each component has its own struct with methods:

**Resistor**
- `init(resistance)` - Create with ohmic value
- `voltageFromCurrent(current)` - V = IR
- `currentFromVoltage(voltage)` - I = V/R

**Capacitor**
- `init(capacitance)` - Create with farad value
- `impedanceAtFrequency(frequency)` - Z = 1/(2πfC)
- `update(current, delta_time)` - Integrate voltage
- `voltage()` - Get voltage state

**Inductor**
- `init(inductance)` - Create with henry value
- `impedanceAtFrequency(frequency)` - Z = 2πfL
- `update(voltage, delta_time)` - Integrate current
- `current()` - Get current state

**Diode**
- `init()` - Create with default silicon parameters
- `currentFromVoltage(voltage)` - Shockley equation
- `dynamicResistance(voltage)` - Small-signal resistance

**OpAmp**
- `init()` - Create with ideal parameters
- `processInput(pos, neg)` - Process input voltage

**Transistor**
- `init(type)` - Create NPN or PNP
- `collectorCurrent(vbe, ib)` - Calculate Ic from Vbe and Ib

### CircuitPresets
Static functions for common circuit topologies.

**Available Presets:**
- `rcLowPass(allocator, sample_rate, cutoff_hz)` - RC low-pass filter
- `rcHighPass(allocator, sample_rate, cutoff_hz)` - RC high-pass filter
- `diodeClipping(allocator, sample_rate)` - Diode clipping distortion
- `toneStack(allocator, sample_rate)` - 3-band tone control

## Parameters

| Name | Range | Default | Description |
|------|-------|---------|-------------|
| `input_level` | 0.0 - 2.0 | 1.0 | Pre-circuit gain |
| `output_level` | 0.0 - 2.0 | 1.0 | Post-circuit gain |
| `bias` | -1.0 - 1.0 | 0.0 | DC offset |
| `simulation_quality` | 0.1 - 4.0 | 1.0 | Oversampling factor |

## KiCAD File Support

The module parses KiCAD PCB files (`.kicad_pcb`) and automatically:
1. Detects component types from footprint names
2. Extracts component values (with k/m/u/n/p multipliers)
3. Maps connectivity through pad connections
4. Builds circuit topology

### Supported Component Footprints

| Footprint Pattern | Type |
|------------------|------|
| R_*, resistor | Resistor |
| C_*, capacitor | Capacitor |
| L_*, inductor | Inductor |
| D_*, diode | Diode |
| Q_*, transistor | Transistor |
| U_*, ic | Op-Amp (simplified) |

## Example Circuits

### Example 1: Tone Control
```zig
var loader = try CircuitPresets.toneStack(allocator, 44100);
defer loader.deinit();

loader.setParameter("input_level", 2.0);
loader.processBuffer(&buffer);
```

### Example 2: Custom Circuit
```zig
var loader = try AnalogLoader.init(allocator, 44100);
defer loader.deinit();

try loader.buildCircuit(&struct {
    pub fn build(sim: *CircuitSimulator) !void {
        // 1kΩ resistor in series with 100nF capacitor to ground
        try sim.addResistor("in", "out", 1000.0);
        try sim.addCapacitor("out", "gnd", 100e-9);
    }
});

loader.processBuffer(&buffer);
```

### Example 3: KiCAD File
```zig
const samples_path = "samples/kikad/BMP_BasicClone.kicad_pcb";
var loader = try AnalogLoader.init(allocator, 44100);
defer loader.deinit();

try loader.loadCircuitFromFile(samples_path);

// Inspect loaded circuit
const stats = loader.getCircuitStats();
std.debug.print("Loaded {d} components in {d} nodes\n", 
    .{ stats.component_count, stats.node_count });

loader.processBuffer(&buffer);
```

## Integration

### Adding to Effect Chain

```zig
const effect = try createAnalogEffect(allocator, sample_rate);
try effect_chain.addEffect(
    "analog",
    &analog_descriptor,
    effect,
    &processAnalogBuffer,
    &deinitAnalogLoader
);

// Set parameters through chain
try effect_chain.setEffectParameter("analog", "input_level", 1.5);

// Process audio
effect_chain.processBuffer(&buffer);
```

### Port Interface

The effect implements the standard port interface:

```zig
const effect_slot = EffectSlot{
    .effect_id = "analog",
    .descriptor = &analog_descriptor,
    .instance = loader,
    .process_buffer_fn = &processAnalogBuffer,
    .deinit_fn = &deinitAnalogLoader,
};
```

## Testing

Run the built-in test suite:

```bash
zig test src/effects/analog/analog_effect.zig
```

Tests cover:
- Component initialization and calculations
- AnalogLoader setup and parameter control
- RC filter creation and validation

## Performance Tips

1. **Preset over Custom**: Use `CircuitPresets` for better performance
2. **Reduce Complexity**: Fewer components = faster processing
3. **Quality Setting**: Lower `simulation_quality` reduces CPU usage
4. **Buffer Size**: Larger buffers amortize initialization costs

## Limitations

- Simplified transistor model (basic beta)
- No full SPICE matrix solver (yet)
- Limited topology support
- No frequency-dependent resistances
- Real-time buffering may be needed at very high sample rates

## Future Work

- [ ] Full nodal analysis matrix solver
- [ ] Additional component models (FET, MOSFET)
- [ ] Frequency domain simulation
- [ ] Parameter variation/modulation
- [ ] Circuit stability analysis
- [ ] Harmonic analysis and THD measurement
- [ ] Subcircuit support
- [ ] Visual circuit diagram rendering

## See Also

- [Main ANALOG_DESIGN.md](../ANALOG_DESIGN.md) - Detailed design documentation
- [Component Definitions](component_definitions.zig) - API reference
- [Circuit Simulator](circuit_simulator.zig) - Implementation details
- [KiCAD Parser](kicad_parser.zig) - File format support
