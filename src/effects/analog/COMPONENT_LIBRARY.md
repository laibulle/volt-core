# Component Library Implementation Guide

## Overview

The component library provides real-time signal processing for individual electronic components. Each component type applies physically-accurate transformations to audio signals, enabling circuit-level emulation.

---

## Components Implemented

### 1. Resistor
**File**: `components.zig::Resistor`

**Signal Processing**:
- Voltage divider: `V_out = V_in * (R_load / (R + R_load))`
- Current calculation: `I = V / R`
- Power dissipation: `P = V² / R`

**Usage**:
```zig
var resistor = Resistor.init(10000.0); // 10kΩ
const signal_out = resistor.processSignal(signal_in, load_impedance);
```

**Real-world Applications**:
- Biasing networks
- Voltage dividers
- Load impedance calculation
- Signal attenuation

---

### 2. Capacitor
**File**: `components.zig::Capacitor`

**Signal Processing**:
- Reactance: `Xc = 1 / (2πfC)`
- High-pass filter: `y = α(y_prev + x - x_prev)`
- Cutoff frequency: `f_c = 1 / (2πRC)`
- Charge: `Q = C * V`
- Energy: `E = 0.5 * C * V²`

**Usage**:
```zig
var cap = Capacitor.init(1e-6); // 1µF
const filtered = cap.processSignal(input, sample_time, load_resistance);
const cutoff = cap.cutoffFrequency(series_resistance);
```

**Real-world Applications**:
- AC coupling (blocks DC)
- High-pass filters
- Low-pass filters
- Energy storage

---

### 3. Inductor
**File**: `components.zig::Inductor`

**Signal Processing**:
- Reactance: `XL = 2πfL`
- Differential equation: `V = L(dI/dt) + I*R`
- Energy: `E = 0.5 * L * I²`
- Resonance: `f_r = 1 / (2π√(LC))`

**Usage**:
```zig
var inductor = Inductor.init(1e-3); // 1mH
const output = inductor.processSignal(input, sample_time, series_resistance);
```

**Real-world Applications**:
- Low-pass filtering
- Output impedance control
- LC resonant circuits
- Current smoothing

---

### 4. Diode
**File**: `components.zig::Diode`

**Signal Processing**:
- Shockley equation: `I = Is(exp(V/Vt) - 1)`
- Hard clipping: Blocks signals beyond forward drop
- Soft clipping: Smooth saturation curve
- Asymmetric clipping: Different forward/reverse behavior

**Usage**:
```zig
var diode = Diode.init();
const clipped = diode.softClip(input_signal);
const asymmetric = diode.asymmetricClip(input_signal);
```

**Real-world Applications**:
- Distortion/clipping effects
- Rectification
- Dynamic range compression
- Tone shaping

---

### 5. Operational Amplifier (Op-Amp)
**File**: `components.zig::OpAmp`

**Signal Processing**:
- Ideal output: `V_out = gain * (V+ - V-)`
- Non-inverting amplifier: `V_out = V_in * (1 + Rf/Ri)`
- Inverting amplifier: `V_out = -V_in * (Rf/Ri)`
- Frequency response: `-3dB bandwidth attenuation`

**Usage**:
```zig
var opamp = OpAmp.init(100000.0, 1e6); // gain, bandwidth
const amplified = opamp.nonInvertingGain(input, feedback_r, input_r);
const gain_at_freq = opamp.gainAt(frequency_hz);
```

**Real-world Applications**:
- Amplification
- Buffering
- Active filtering
- Tone control

---

### 6. Transistor
**File**: `components.zig::Transistor`

**Signal Processing**:
- Collector current: `Ic = β * Ib`
- Common-emitter amplification
- Saturation detection
- Nonlinear distortion

**Usage**:
```zig
var transistor = Transistor.init(.npn, 200.0); // type, beta
const distorted = transistor.distort(input_signal);
const saturated = transistor.isSaturated(vce);
```

**Real-world Applications**:
- Gain stages
- Amplification with clipping
- Distortion
- Switching circuits

---

## Component Library

**File**: `component_library.zig`

Manages collections of components and provides signal processing utilities.

### ComponentLibrary API

```zig
pub const ComponentLibrary = struct {
    // Add components
    pub fn addResistor(resistance_ohms: f32) !usize
    pub fn addCapacitor(capacitance_farads: f32) !usize
    pub fn addInductor(inductance_henries: f32) !usize
    pub fn addDiode() !usize
    pub fn addOpAmp(gain: f32, bandwidth: f32) !usize
    pub fn addTransistor(type: Transistor.Type, beta: f32) !usize
    
    // Access components
    pub fn resistorAtIndex(index: usize) ?*Resistor
    pub fn capacitorAtIndex(index: usize) ?*Capacitor
    // ... etc for other types
    
    // Query
    pub fn componentCount() usize
    pub fn resistorCount() usize
    // ... counters for each type
};
```

### Example Usage

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var lib = ComponentLibrary.init(allocator);
defer lib.deinit();

// Build a circuit
const r1_idx = try lib.addResistor(10000.0);
const c1_idx = try lib.addCapacitor(1e-6);
const d1_idx = try lib.addDiode();

std.debug.print("Created {} components\n", .{lib.componentCount()});
```

---

## Circuit Presets

Pre-built circuits using the component library.

### Available Presets

#### 1. RC Low-Pass Filter
```zig
var circuit = try CircuitPresets.rcLowPass(allocator, sample_rate, 1000.0);
defer circuit.deinit();

// Attenuates frequencies above 1kHz
```

**Frequency Response**:
- Below cutoff: Passes signal
- Above cutoff: Attenuates (-20dB/decade)
- Example: 1kHz cutoff with 10kΩ resistor → C = 15.9 nF

#### 2. RC High-Pass Filter
```zig
var circuit = try CircuitPresets.rcHighPass(allocator, sample_rate, 100.0);
defer circuit.deinit();

// Blocks frequencies below 100Hz
```

**Application**: Removes rumble, AC coupling

#### 3. Diode Clipper
```zig
var circuit = try CircuitPresets.diodeClipping(allocator, sample_rate);
defer circuit.deinit();

// Creates asymmetric clipping distortion
```

**Components**:
- Input coupling capacitor (1µF)
- Input resistor (1kΩ)
- Two diodes (forward and reverse)
- Load resistor (10kΩ)

#### 4. Transistor Amplifier
```zig
var circuit = try CircuitPresets.transistorAmp(allocator, sample_rate, gain);
defer circuit.deinit();

// Provides gain and natural distortion
```

**Components**:
- Biasing network (1M + 10k)
- Coupling capacitor (1µF)
- BC549 transistor (β=200)
- Load resistor (5.6kΩ)

#### 5. Tone Stack
```zig
var circuit = try CircuitPresets.toneStack(allocator, sample_rate);
defer circuit.deinit();

// Three-band EQ control (bass/mid/treble)
```

**Architecture**:
- Bass control: 1kΩ + 100nF → ~1.6 kHz
- Mid control: 10kΩ + 10nF → ~160 Hz
- Treble control: 1nF + 1M → ~160 kHz

#### 6. Fuzz Face
```zig
var circuit = try CircuitPresets.fuzzFace(allocator, sample_rate);
defer circuit.deinit();

// Classic two-transistor distortion
```

**Two-Stage Design**:
1. First transistor: Gain stage (100k load)
2. Second transistor: Output stage
3. Diode clipping between stages
4. Output coupling (2.2µF)

---

## Signal Processor

**File**: `component_library.zig::SignalProcessor`

Applies signal transformations through components.

### API

```zig
pub const SignalProcessor = struct {
    pub fn processResistorDivider(
        input: []f32, 
        output: []f32, 
        r1_index: usize, 
        r2_index: usize
    ) !void
    
    pub fn processCapacitorFilter(
        input: []f32, 
        output: []f32, 
        cap_index: usize, 
        load_r: f32
    ) !void
    
    pub fn processDiodeClipper(
        input: []f32, 
        output: []f32, 
        diode_index: usize
    ) !void
    
    pub fn processTransistorAmp(
        input: []f32, 
        output: []f32, 
        transistor_index: usize, 
        gain_mul: f32
    ) !void
    
    pub fn processOpAmp(
        input: []f32, 
        output: []f32, 
        opamp_index: usize, 
        feedback_r: f32, 
        input_r: f32
    ) !void
};
```

### Example: Processing Audio Buffer

```zig
var circuit = try CircuitPresets.rcLowPass(allocator, 44100, 1000.0);
defer circuit.deinit();

var processor = SignalProcessor.init(circuit);

var input_buffer: [2048]f32 = undefined;
var output_buffer: [2048]f32 = undefined;

// ... fill input_buffer with audio ...

try processor.processCapacitorFilter(&input_buffer, &output_buffer, 0, 10000.0);
```

---

## Signal Flow Example

### Simple Distortion Chain

```
Input Signal
    ↓
[Capacitor: AC Coupling] (removes DC)
    ↓
[Resistor: Input Attenuator] (controls input level)
    ↓
[Transistor: Amplifier with Clipping] (adds gain and distortion)
    ↓
[Diode: Soft Clipping] (refines distortion character)
    ↓
[Capacitor: Output Coupling] (removes DC)
    ↓
Output Signal
```

**Implementation**:
```zig
var circuit = try CircuitPresets.fuzzFace(allocator, sample_rate);
var processor = SignalProcessor.init(circuit);

// Process buffer through each stage
try processor.processCapacitorFilter(&input, &temp1, 0, 10000.0); // coupling
try processor.processResistorDivider(&temp1, &temp2, 0, 1); // input stage
try processor.processTransistorAmp(&temp2, &temp3, 0, 10.0); // first amp
try processor.processDiodeClipper(&temp3, &temp4, 0); // clipping
try processor.processTransistorAmp(&temp4, &output, 1, 5.0); // output amp
```

---

## Physical Constants

### Standard Values

| Component | Typical Value | Unit |
|---|---|---|
| R (Resistor) | 1k - 1M | Ω |
| C (Capacitor) | 1n - 100µ | F |
| L (Inductor) | 1µ - 10m | H |
| Diode Vf | 0.6 - 0.7 | V |
| BJT β (hFE) | 50 - 600 | (unitless) |
| Vbe (on) | 0.6 - 0.7 | V |
| Vce (sat) | 0.2 - 0.5 | V |

### Frequency Calculations

**RC Cutoff**:
$$f_c = \frac{1}{2\pi RC}$$

**LC Resonance**:
$$f_r = \frac{1}{2\pi\sqrt{LC}}$$

**Capacitive Reactance**:
$$X_c = \frac{1}{2\pi fC}$$

**Inductive Reactance**:
$$X_L = 2\pi fL$$

---

## Performance

### CPU Usage (Estimated @ 44.1 kHz)

| Component | Operations/Sample | CPU Usage |
|---|---|---|
| Resistor | 3-5 | < 0.1% |
| Capacitor | 8-10 | 0.2% |
| Inductor | 15-20 | 0.5% |
| Diode (soft clip) | 20-25 | 0.8% |
| OpAmp (gain) | 10-15 | 0.4% |
| Transistor | 25-30 | 1% |

**Typical Circuit** (Fuzz Face, 6 components): ~3% CPU

### Memory

| Component Type | Memory | Notes |
|---|---|---|
| Resistor | 4 bytes | Float |
| Capacitor | 12 bytes | Float + state |
| Diode | 12 bytes | Float + params |
| OpAmp | 20 bytes | Multiple floats |
| Transistor | 16 bytes | Type + params |

---

## Next Steps

1. **Integration**: Connect ComponentLibrary to CircuitSimulator
2. **Optimization**: SIMD processing for multiple channels
3. **Extended Models**: 
   - Detailed BJT models
   - JFET/MOSFET models
   - Transformer modeling
4. **Measurement**: Add voltage/current probing
5. **Visualization**: Frequency response curves

---

## Testing

All components include built-in tests:

```bash
zig build test  # Runs all component tests
```

**Test Coverage**:
- ✅ Resistor voltage divider
- ✅ Capacitor high-pass filtering
- ✅ Diode clipping
- ✅ Component library operations
- ✅ Signal processor integration

---

## References

- **Shockley Diode Equation**: `I = Is(exp(V/Vt) - 1)`
- **Transistor Modeling**: Small-signal equivalent
- **Op-Amp Theory**: Ideal op-amp assumptions
- **Filter Theory**: RC networks and frequency response
- **Circuit Analysis**: Nodal analysis fundamentals

---

**Status**: ✅ Component library complete and tested
**Integration**: Ready for circuit simulator integration
**Performance**: Suitable for real-time audio processing
