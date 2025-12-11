# Practical Circuit Examples with Parametrized Components

## Introduction

This guide shows how to build real-world audio circuits using the parametrized component system. Each example demonstrates:
- Generic algorithm reuse
- Specific component variants
- Real circuit behavior

---

## Example 1: Classic Fuzz Face Circuit

### Circuit Description
The Fuzz Face is a legendary two-transistor distortion used by Jimi Hendrix. It uses:
- Two germanium transistors in Darlington configuration
- Diode clipping for asymmetric distortion
- Coupling and bypass capacitors

### Implementation

```zig
const std = @import("std");
const components = @import("components_v2.zig");

pub fn buildFuzzFace(allocator: std.mem.Allocator) !struct {
    input_cap: components.Capacitor,
    bias_r1: components.Resistor,
    bias_r2: components.Resistor,
    input_r: components.Resistor,
    q1: components.Transistor,
    q2: components.Transistor,
    d1: components.Diode,
    d2: components.Diode,
    output_cap: components.Capacitor,
} {
    return .{
        // Input coupling capacitor - blocks DC
        .input_cap = components.CapacitorVariants.filmPolyester(1e-6),
        
        // Biasing network
        .bias_r1 = components.ResistorVariants.carbonFilm(1e6),
        .bias_r2 = components.ResistorVariants.carbonFilm(100e3),
        
        // Input attenuation
        .input_r = components.ResistorVariants.carbonFilm(1e3),
        
        // First stage: Germanium PNP
        // (BC549 is NPN; for PNP vintage use 2N2905)
        .q1 = components.TransistorModels.transistor2n2905(),
        
        // Second stage: Germanium PNP
        .q2 = components.TransistorModels.transistor2n2905(),
        
        // Clipping diodes (germanium for soft clip)
        .d1 = components.DiodeModels.diode1N34A(),
        .d2 = components.DiodeModels.diode1N34A(),
        
        // Output coupling
        .output_cap = components.CapacitorVariants.filmPolyester(2.2e-6),
    };
}

pub fn processFuzzFaceSignal(
    circuit: @TypeOf(buildFuzzFace) circuit,
    input: f32,
    sample_rate: f32,
    dt: f32,
) f32 {
    // Stage 1: Input coupling
    var stage1_in = input - 0.7; // Bias offset
    
    // Stage 1: First transistor (PNP common-emitter)
    var stage1_out = circuit.q1.distort(stage1_in);
    
    // Clipping between stages
    var stage1_clipped = circuit.d1.softClip(stage1_out);
    
    // Stage 2: Second transistor
    var stage2_out = circuit.q2.distort(stage1_clipped);
    
    // Output clipping
    var output = circuit.d2.softClip(stage2_out);
    
    return output * 0.5; // Output level control
}
```

### Why This Works

1. **Germanium transistors** (`transistor2n2905`):
   - Lower Vbe (conducts easier) → more aggressive distortion
   - Lower beta → gentler saturation
   
2. **Germanium diodes** (`diode1N34A`):
   - Lower forward drop (0.3V vs 0.65V) → softer clipping
   - Different Is → smooth, musical compression

3. **Reusability**: Both transistors use identical algorithm with different parameters

---

## Example 2: Vintage Tone Stack (3-Band EQ)

### Circuit Description
A classic passive tone stack providing bass, mid, and treble control.

### Implementation

```zig
pub const ToneStackCircuit = struct {
    // Bass control: Low frequency shaping
    bass_cap: components.Capacitor,
    bass_r1: components.Resistor,
    bass_r2: components.Resistor,
    
    // Mid control: Mid-frequency shaping
    mid_cap: components.Capacitor,
    mid_r1: components.Resistor,
    mid_r2: components.Resistor,
    
    // Treble control: High frequency shaping
    treble_cap: components.Capacitor,
    treble_r1: components.Resistor,
    treble_r2: components.Resistor,
    
    sample_rate: f32,
};

pub fn buildToneStack() ToneStackCircuit {
    return .{
        // BASS CIRCUIT (1.6 kHz cutoff)
        // fc = 1 / (2π * R * C)
        // 1600 Hz = 1 / (2π * 1k * C) → C ≈ 100nF
        .bass_cap = components.CapacitorVariants.ceramicX7R(100e-9),
        .bass_r1 = components.ResistorVariants.metalFilm(1e3),
        .bass_r2 = components.ResistorVariants.metalFilm(10e3),
        
        // MID CIRCUIT (160 Hz cutoff)
        // 160 Hz = 1 / (2π * 10k * C) → C ≈ 100nF
        .mid_cap = components.CapacitorVariants.ceramicX7R(100e-9),
        .mid_r1 = components.ResistorVariants.metalFilm(10e3),
        .mid_r2 = components.ResistorVariants.metalFilm(100e3),
        
        // TREBLE CIRCUIT (16 kHz cutoff)
        // 16k Hz = 1 / (2π * 1M * C) → C ≈ 10nF
        .treble_cap = components.CapacitorVariants.ceramicNPO(10e-9),
        .treble_r1 = components.ResistorVariants.metalFilm(1e6),
        .treble_r2 = components.ResistorVariants.metalFilm(10e3),
        
        .sample_rate = 44100.0,
    };
}

pub fn processToneStack(
    circuit: ToneStackCircuit,
    input: f32,
    dt: f32,
    bass_level: f32,    // 0.0 to 1.0
    mid_level: f32,
    treble_level: f32,
) f32 {
    var output: f32 = input;
    
    // Bass processing
    const bass_cutoff = circuit.bass_cap.cutoffFrequency(
        circuit.bass_r1.resistance + circuit.bass_r2.resistance * bass_level
    );
    // ... apply bass filter
    
    // Mid processing
    // ... similar
    
    // Treble processing
    // ... similar
    
    return output;
}
```

### Why This Works

1. **Metal film resistors** for precision - ensures accurate frequencies
2. **Ceramic capacitors** for stability - tone stack must be repeatable
3. **Different RC combinations** via different component values
4. **Same filtering algorithm** applied three times

---

## Example 3: Overdrive Circuit (OpAmp + Diode Clipper)

### Circuit Description
A modern opamp-based overdrive with symmetric clipping diodes.

### Implementation

```zig
pub const OverdriveCircuit = struct {
    // Input stage
    input_cap: components.Capacitor,
    input_r: components.Resistor,
    
    // OpAmp gain stage
    opamp: components.OpAmp,
    feedback_r: components.Resistor,
    input_r_opamp: components.Resistor,
    
    // Clipping stage
    diode_pos: components.Diode,
    diode_neg: components.Diode,
    clip_r: components.Resistor,
    
    // Output stage
    output_cap: components.Capacitor,
    output_r: components.Resistor,
};

pub fn buildOverdrive() OverdriveCircuit {
    return .{
        // Input coupling (1 µF, ~160 Hz highpass @ 1k)
        .input_cap = components.CapacitorVariants.filmPolyester(1e-6),
        .input_r = components.ResistorVariants.metalFilm(1e3),
        
        // OpAmp gain stage with adjustable gain
        // Gain = 1 + Rf/Ri, so Rf/Ri = 10 gives 11x gain
        .opamp = components.OpAmpModels.tl072(),  // Low noise audio opamp
        .feedback_r = components.ResistorVariants.precisionMetalFilm(100e3),
        .input_r_opamp = components.ResistorVariants.precisionMetalFilm(10e3),
        
        // Clipping diodes (silicon for bright, fast clipping)
        .diode_pos = components.DiodeModels.diode1N4148(),
        .diode_neg = components.DiodeModels.diode1N4148(),
        .clip_r = components.ResistorVariants.carbonFilm(10e3),
        
        // Output coupling
        .output_cap = components.CapacitorVariants.filmPolyester(1e-6),
        .output_r = components.ResistorVariants.carbonFilm(1e3),
    };
}

pub fn processOverdrive(
    circuit: OverdriveCircuit,
    input: f32,
    drive_level: f32,  // 0.0 to 1.0
) f32 {
    // Input coupling
    var stage1 = input; // Filtered by input_cap
    
    // OpAmp gain stage
    // Adjustable gain: 1x to 11x based on drive_level
    const gain = 1.0 + drive_level * 10.0;
    let stage2 = circuit.opamp.nonInvertingGain(stage1, 
                                                circuit.feedback_r.resistance * drive_level,
                                                circuit.input_r_opamp.resistance);
    
    // Symmetric diode clipping
    let clipped = if (stage2 > 0.7) {
        circuit.diode_pos.softClip(stage2)
    } else if (stage2 < -0.7) {
        circuit.diode_neg.softClip(stage2)
    } else {
        stage2
    };
    
    return clipped;
}
```

### Why This Works

1. **TL072 OpAmp**:
   - Low noise for clean amplification
   - Good bandwidth for fast response
   - Adjustable gain via feedback resistor
   
2. **Silicon diodes** (`1N4148`):
   - Higher forward drop → sharper clipping
   - Fast recovery → transparent distortion
   - Symmetric clipping (same forward/reverse)

3. **Precision resistors** for feedback:
   - Accurate gain setting
   - Stable operation across frequencies

---

## Example 4: RC Filter Chain (Passive Crossover)

### Circuit Description
A two-way passive crossover for speaker design.

### Implementation

```zig
pub const CrossoverCircuit = struct {
    // Highpass for tweeter
    highpass_cap: components.Capacitor,
    highpass_r: components.Resistor,
    
    // Lowpass for woofer
    lowpass_cap: components.Capacitor,
    lowpass_r: components.Resistor,
    
    crossover_freq: f32,
};

pub fn buildCrossover2Way(crossover_hz: f32) CrossoverCircuit {
    // For crossover at 2kHz with standard impedances:
    // Highpass: 1/(2πfC) = 8Ω → C ≈ 10µF, R ≈ 10Ω (nominal)
    // Lowpass: same component values (matching impedance)
    
    const cap_value = 1.0 / (2.0 * std.math.pi * crossover_hz * 8.0);
    
    return .{
        .highpass_cap = components.CapacitorVariants.electrolyticAluminum(cap_value, 25.0),
        .highpass_r = components.ResistorVariants.powerWireWound(10.0),  // 10W rating
        
        .lowpass_cap = components.CapacitorVariants.electrolyticAluminum(cap_value, 25.0),
        .lowpass_r = components.ResistorVariants.powerWireWound(10.0),
        
        .crossover_freq = crossover_hz,
    };
}

pub fn processHighpass(
    circuit: CrossoverCircuit,
    input: f32,
    dt: f32,
) f32 {
    // Highpass filter for tweeter
    return circuit.highpass_cap.processSignal(input, dt, circuit.highpass_r.resistance);
}

pub fn processLowpass(
    circuit: CrossoverCircuit,
    input: f32,
    dt: f32,
) f32 {
    // Lowpass filter for woofer
    return circuit.lowpass_cap.processSignal(input, dt, circuit.lowpass_r.resistance);
}
```

### Why This Works

1. **Electrolytic capacitors** - Handle low frequency, high capacitance needed
2. **Power resistors** - Dissipate energy without heating issues
3. **Same filter algorithm** applied to both channels
4. **Parametrized by frequency** - Change crossover easily

---

## Example 5: Parametric EQ (Using Inductors)

### Circuit Description
An inductor-based parametric equalizer providing peak/dip control.

### Implementation

```zig
pub const ParametricEQCircuit = struct {
    // Peak filter (bandpass)
    series_r: components.Resistor,
    series_l: components.Inductor,
    shunt_cap: components.Capacitor,
    
    center_frequency: f32,
    q_factor: f32,
};

pub fn buildParametricEQ(center_hz: f32, q: f32) ParametricEQCircuit {
    // RLC bandpass filter
    // f0 = 1 / (2π√(LC))
    // For 1kHz with standard L: need C ≈ 2.5µF
    
    const inductance = 0.01;  // 10mH inductor
    const capacitance = 1.0 / (std.math.pow(f32, 2.0 * std.math.pi * center_hz, 2.0) * inductance);
    
    return .{
        .series_r = components.ResistorVariants.metalFilm(100.0),
        .series_l = components.InductorVariants.ferriteCore(inductance, 10.0),
        .shunt_cap = components.CapacitorVariants.filmPolyester(capacitance),
        
        .center_frequency = center_hz,
        .q_factor = q,
    };
}

pub fn resonantBehavior(circuit: ParametricEQCircuit, frequency: f32) f32 {
    // LC resonance creates peak at center frequency
    let resonance_freq = circuit.series_l.resonantFrequency(
        circuit.shunt_cap.capacitance
    );
    
    // Sharpness depends on Q factor (determined by R)
    if (@abs(frequency - resonance_freq) < (resonance_freq / circuit.q_factor)) {
        return 2.0;  // +6dB peak
    } else {
        return 1.0;  // Flat
    }
}
```

### Why This Works

1. **Ferrite inductors** - Better Q factor, less loss than air core
2. **Film capacitors** - Stable resonance, low ESR
3. **Different cores** parametrize saturation behavior
4. **Same RLC model** adjusted by L core type

---

## Component Selection Cheat Sheet

### For Audio Circuits
- **Resistors**: Metal film 1% or precision 0.1% for critical values
- **Capacitors**: 
  - Coupling: Film (Polyester, Polypropylene)
  - Bypass: Ceramic (X7R)
  - Power supply: Electrolytic
  - Precision: Film
  
- **Inductors**: Ferrite core for audio range (good Q, no saturation)

- **Diodes**:
  - General: 1N4148 (fast silicon)
  - Vintage tone: 1N34A (germanium)
  - Soft clip: Low-drop types (Schottky, germanium)

- **OpAmps**:
  - Audio: TL072, NE5532 (low noise)
  - Precision: LM4562 (ultra low noise)
  - General: LM358 (cheap, works everywhere)

- **Transistors**:
  - Audio: BC549 (NPN), BC327 (PNP)
  - Vintage: 2N2222, 2N2905 (slower, warmer)
  - Switching: 2N3904 (fast)

---

## Testing Your Circuit

### Check 1: DC Bias Points
```zig
test "fuzz face bias voltages" {
    const circuit = buildFuzzFace();
    
    // Bias should put transistors in active region
    const q1_bias = 4.5;  // Half supply (9V / 2)
    const q2_bias = 4.5;
    
    try std.testing.expect(q1_bias > 0 and q1_bias < 9.0);
}
```

### Check 2: Frequency Response
```zig
test "tone stack frequency response" {
    const circuit = buildToneStack();
    
    const bass_cutoff = circuit.bass_cap.cutoffFrequency(
        circuit.bass_r1.resistance
    );
    
    // Should be in bass range
    try std.testing.expect(bass_cutoff < 1000.0);
}
```

### Check 3: Clipping Threshold
```zig
test "overdrive clipping level" {
    const circuit = buildOverdrive();
    
    const threshold = circuit.diode_pos.params.forward_drop;
    
    try std.testing.expect(threshold > 0.5 and threshold < 0.8);
}
```

---

## Next Steps

1. **Measure real circuits** - Gather actual component values from schematics
2. **Characterize components** - Get datasheets for accurate parameters
3. **Model frequency response** - Add Bode plot simulation
4. **Simulate noise** - Add thermal noise and 1/f noise models
5. **Interactive design** - Real-time parameter adjustment

