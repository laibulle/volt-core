# AnalogLoader - Quick Start Guide

## Installation

The analog module is located in `src/effects/analog/` and consists of:
- `analog.zig` - Main module import
- `component_definitions.zig` - Component models
- `kicad_parser.zig` - KiCAD file parsing
- `circuit_simulator.zig` - Simulation engine
- `analog_effect.zig` - Effect implementation

## Basic Usage

### 1. Import the Module

```zig
const analog = @import("effects/analog/analog.zig");
```

### 2. Create an AnalogLoader

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

// Create with sample rate
var loader = try analog.AnalogLoader.init(allocator, 44100);
defer loader.deinit();
```

### 3. Load a Circuit

**Option A: From KiCAD File**
```zig
try loader.loadCircuitFromFile("path/to/circuit.kicad_pcb");
```

**Option B: From Content String**
```zig
const kicad_content = @embedFile("circuit.kicad_pcb");
try loader.loadCircuitFromContent(kicad_content);
```

**Option C: Use a Preset**
```zig
var loader = try analog.CircuitPresets.rcLowPass(allocator, 44100, 1000.0);
```

**Option D: Build Programmatically**
```zig
try loader.buildCircuit(&struct {
    pub fn build(sim: *analog.CircuitSimulator) !void {
        try sim.addResistor("in", "out", 10000.0);
        try sim.addCapacitor("out", "gnd", 100e-9);
    }
});
```

### 4. Process Audio

```zig
// Process buffer
loader.processBuffer(&audio_buffer);

// Or process single sample
const output = loader.processSample(input_sample);
```

### 5. Set Parameters

```zig
loader.setParameter("input_level", 1.5);
loader.setParameter("output_level", 1.0);
loader.setParameter("bias", 0.1);
loader.setParameter("simulation_quality", 2.0);
```

## Preset Circuits

### RC Low-Pass Filter

```zig
var loader = try analog.CircuitPresets.rcLowPass(allocator, 44100, 5000.0);
defer loader.deinit();

// 5 kHz cutoff frequency
loader.processBuffer(&buffer);
```

**Circuit**: 1kΩ resistor → output, 100nF capacitor to ground
**Use Case**: Remove high-frequency content, smooth treble

### RC High-Pass Filter

```zig
var loader = try analog.CircuitPresets.rcHighPass(allocator, 44100, 100.0);
defer loader.deinit();

// 100 Hz cutoff frequency
loader.processBuffer(&buffer);
```

**Circuit**: 100nF capacitor → output, 1kΩ resistor to ground
**Use Case**: Remove low-frequency rumble, boost bass

### Diode Clipping Distortion

```zig
var loader = try analog.CircuitPresets.diodeClipping(allocator, 44100);
defer loader.deinit();

loader.setParameter("input_level", 5.0);  // Boost before clipping
loader.setParameter("output_level", 0.5); // Reduce after clipping
loader.processBuffer(&buffer);
```

**Circuit**: 1kΩ resistor → diode to ground → 1kΩ output
**Use Case**: Soft-clipping distortion, guitar tone shaping

### Tone Stack (3-Band EQ)

```zig
var loader = try analog.CircuitPresets.toneStack(allocator, 44100);
defer loader.deinit();

loader.processBuffer(&buffer);
```

**Circuit**: Bass, mid, treble RC circuits combined
**Use Case**: 3-band equalization, tone control

## Custom Circuits

### Simple RC Network

```zig
var loader = try analog.AnalogLoader.init(allocator, 44100);
defer loader.deinit();

try loader.buildCircuit(&struct {
    pub fn build(sim: *analog.CircuitSimulator) !void {
        // Create RC low-pass: input → 10k resistor → capacitor to ground
        try sim.addResistor("input", "output", 10000.0);     // 10kΩ
        try sim.addCapacitor("output", "ground", 100e-9);    // 100nF
        // Cutoff frequency: fc = 1/(2π*R*C) = 159.2 Hz
    }
});

loader.processBuffer(&buffer);
```

### RLC Resonant Circuit

```zig
try loader.buildCircuit(&struct {
    pub fn build(sim: *analog.CircuitSimulator) !void {
        // Series RLC circuit
        try sim.addResistor("in", "node1", 1000.0);         // 1kΩ
        try sim.addInductor("node1", "node2", 10e-3);       // 10mH
        try sim.addCapacitor("node2", "gnd", 100e-9);       // 100nF
        // Creates resonance at: f = 1/(2π√(LC))
    }
});
```

### Multi-Stage Filter

```zig
try loader.buildCircuit(&struct {
    pub fn build(sim: *analog.CircuitSimulator) !void {
        // First stage: input RC filter
        try sim.addResistor("in", "stage1", 10000.0);
        try sim.addCapacitor("stage1", "gnd", 100e-9);
        
        // Second stage: output RC filter
        try sim.addResistor("stage1", "out", 10000.0);
        try sim.addCapacitor("out", "gnd", 100e-9);
        // Creates steeper roll-off
    }
});
```

### Diode Ring Modulator (Simplified)

```zig
try loader.buildCircuit(&struct {
    pub fn build(sim: *analog.CircuitSimulator) !void {
        // Simplified diode soft-clipping
        try sim.addResistor("in", "clip", 1000.0);
        try sim.addDiode("clip", "gnd");
        try sim.addDiode("gnd", "clip");  // Two-way clipping
        try sim.addResistor("clip", "out", 1000.0);
    }
});
```

## Integration with Effect Chain

```zig
const ports = @import("ports/effects.zig");
const chain = @import("core/effect_chain.zig");

// Create effect
const effect = try analog.createAnalogEffect(allocator, 44100);

// Create effect slot
const slot = try chain.EffectSlot.init(
    allocator,
    "analog",
    &analog.analog_descriptor,
    effect,
    &analog.processAnalogBuffer,
);
slot.deinit_fn = &analog.deinitAnalogLoader;

// Add to chain
try effect_chain.addEffect(slot);

// Use parameters
try effect_chain.setEffectParameter("analog", "input_level", 1.5);

// Process audio
effect_chain.processBuffer(&audio_buffer);
```

## Component Value Format

The parser automatically handles these value formats:

| Input | Parsed | Unit |
|-------|--------|------|
| `10` | 10 | - |
| `10k` | 10,000 | Ω |
| `10m` | 0.01 | Ω |
| `100u` | 0.0001 | F |
| `100n` | 1×10⁻⁷ | F |
| `100p` | 1×10⁻¹⁰ | F |

## Getting Circuit Information

```zig
// Get loaded circuit statistics
const stats = loader.getCircuitStats();
std.debug.print("Nodes: {d}, Components: {d}, Connections: {d}\n",
    .{ stats.node_count, stats.component_count, stats.connection_count });

// Check if circuit loaded
if (loader.circuit_loaded) {
    std.debug.print("Circuit loaded successfully\n", .{});
}
```

## Common Cutoff Frequencies

For RC filters, use these common cutoff frequencies:

| Frequency | Use Case |
|-----------|----------|
| 20 Hz | Sub-bass rumble removal |
| 100 Hz | Low-frequency rumble |
| 1 kHz | Mud region |
| 5 kHz | Presence peak |
| 10 kHz | Brightness |
| 20 kHz | Nyquist region |

Example:
```zig
var bass_cut = try analog.CircuitPresets.rcHighPass(allocator, 44100, 80.0);
var treble_cut = try analog.CircuitPresets.rcLowPass(allocator, 44100, 12000.0);
```

## Error Handling

```zig
var loader = analog.AnalogLoader.init(allocator, 44100) catch |err| {
    std.debug.print("Failed to create loader: {}\n", .{err});
    return;
};
defer loader.deinit();

loader.loadCircuitFromFile("circuit.kicad_pcb") catch |err| {
    std.debug.print("Failed to load circuit: {}\n", .{err});
    return;
};
```

## Performance Tips

1. **Reuse Instances**: Create once, process many
2. **Preset > Custom**: Presets are optimized
3. **Batch Processing**: Process larger buffers when possible
4. **Quality Setting**: Lower quality = faster, less accurate
5. **Component Count**: Fewer components = faster processing

## Common Patterns

### Guitar Amp Tone Stack
```zig
var loader = try analog.CircuitPresets.toneStack(allocator, 44100);
loader.setParameter("input_level", 10.0);  // Drive
loader.processBuffer(&buffer);
```

### Bass Boost
```zig
var loader = try analog.CircuitPresets.rcHighPass(allocator, 44100, 50.0);
loader.setParameter("input_level", 1.5);
loader.processBuffer(&buffer);
```

### Crisp Treble
```zig
var loader = try analog.CircuitPresets.rcLowPass(allocator, 44100, 8000.0);
loader.setParameter("output_level", 0.8);
loader.processBuffer(&buffer);
```

### Soft Distortion
```zig
var loader = try analog.CircuitPresets.diodeClipping(allocator, 44100);
loader.setParameter("input_level", 3.0);
loader.setParameter("output_level", 1.0);
loader.processBuffer(&buffer);
```

## Next Steps

1. Read `README.md` for detailed API reference
2. Check `ARCHITECTURE.md` for implementation details
3. Review `DESIGN_SUMMARY.md` for overview
4. Look at `ANALOG_DESIGN.md` for comprehensive documentation
5. Explore the `.kicad_pcb` files in `samples/kikad/` directory

## Support

For issues or questions:
1. Check the documentation files
2. Review test cases in `analog_effect.zig`
3. Examine component implementations
4. Trace through the circuit simulator

## Example: Complete Audio Processing Loop

```zig
const std = @import("std");
const analog = @import("effects/analog/analog.zig");
const audio = @import("audio.zig");

pub fn processAudioWithAnalog(
    allocator: std.mem.Allocator,
    buffer: *audio.AudioBuffer,
    cutoff_hz: f32,
) !void {
    // Create filter
    var loader = try analog.CircuitPresets.rcLowPass(
        allocator,
        buffer.sample_rate,
        cutoff_hz
    );
    defer loader.deinit();

    // Configure
    loader.setParameter("input_level", 1.0);
    loader.setParameter("output_level", 1.0);

    // Process
    loader.processBuffer(buffer);

    // Optional: check results
    const stats = loader.getCircuitStats();
    std.debug.print("Processed with {d} components\n", .{stats.component_count});
}
```
