# Parametrized Components - Quick Reference

## One-Minute Overview

**Concept**: Components have one generic algorithm. Specific models are just different parameter sets.

```zig
// One algorithm (processSignal, softClip, etc.)
// Multiple models via parameters
const d1 = DiodeModels.diode1N4148();  // Parameters: Is=2.68e-15, Vf=0.65
const d2 = DiodeModels.diode1N34A();   // Parameters: Is=1.2e-12, Vf=0.30
// Same softClip() algorithm, different behavior
```

---

## Resistors

### Create Generic
```zig
let r = Resistor.init(10000.0);
```

### Variants
```zig
ResistorVariants.carbonFilm(10000.0)           // 5%, 0.25W
ResistorVariants.metalFilm(10000.0)            // 1%, 0.5W
ResistorVariants.precisionMetalFilm(10000.0)   // 0.1%, 0.5W
ResistorVariants.powerWireWound(10000.0)       // 5W
```

### Methods
```zig
r.processSignal(voltage, load_impedance)  // Voltage divider
r.current(voltage)                        // Ohm's law
r.power(voltage)                          // Power dissipation
r.impedanceAt(freq)                       // Frequency response
```

---

## Capacitors

### Create Generic
```zig
let c = Capacitor.init(1e-6);
```

### Variants
```zig
CapacitorVariants.ceramicNPO(1e-6)           // Stable
CapacitorVariants.ceramicX7R(1e-6)           // General purpose
CapacitorVariants.filmPolyester(1e-6)        // Audio
CapacitorVariants.filmPolypropylene(1e-6)    // Low loss
CapacitorVariants.electrolyticAluminum(1e-6, 25.0)  // High cap
CapacitorVariants.tantalumSolid(1e-6, 16.0)        // Compact
```

### Methods
```zig
c.processSignal(input, dt, load_r)   // RC high-pass filter
c.reactanceAt(freq)                  // Frequency impedance
c.charge(voltage)                    // Q = C*V
c.energy(voltage)                    // E = 0.5*C*V²
c.cutoffFrequency(series_r)          // fc = 1/(2πRC)
c.leakageCurrent(voltage)            // Type-dependent
```

---

## Inductors

### Create Generic
```zig
let l = Inductor.init(1e-3);
```

### Variants
```zig
InductorVariants.airCore(1e-3)              // No saturation
InductorVariants.ironPowderCore(1e-3, 0.5)  // Moderate sat
InductorVariants.ferriteCore(1e-3, 0.2)     // High sat
InductorVariants.toroidalFerrite(1e-3, 0.2) // Shielded
InductorVariants.muMetalShielded(1e-3)      // Ultra stable
```

### Methods
```zig
l.processSignal(input, dt, series_r)      // RL low-pass filter
l.reactanceAt(freq)                       // Frequency impedance
l.energy(current)                         // E = 0.5*L*I²
l.resonantFrequency(capacitance)          // LC resonance
l.saturationFactor(current)               // Core saturation effect
```

---

## Diodes

### Create Generic (with params)
```zig
let d = Diode.init(.{
    .saturation_current = 1e-14,
    .thermal_voltage = 0.026,
    .forward_drop = 0.7,
    .series_resistance = 10.0,
});
```

### Specific Models
```zig
DiodeModels.diode1N4148()      // Silicon, fast, 0.65V drop
DiodeModels.diode1N4007()      // Silicon, general, 0.72V drop
DiodeModels.diode1N34A()       // Germanium, vintage, 0.30V drop
DiodeModels.diode1N60()        // Germanium, point contact, 0.25V
DiodeModels.schottkyBAT54()    // Schottky, 0.30V drop
DiodeModels.redLED()           // LED, 2.0V drop
```

### Methods
```zig
d.current(voltage)          // Shockley equation
d.clipSignal(input)         // Hard clipping
d.softClip(input)           // Smooth saturation
d.asymmetricClip(input)     // Diode-like behavior
d.dynamicResistance(voltage) // Differential resistance
```

---

## Op-Amps

### Create Generic (with params)
```zig
let op = OpAmp.init(.{
    .gain = 200000.0,
    .bandwidth = 10e6,
    .slew_rate = 9.5e6,
    .input_impedance = 2e6,
    .output_impedance = 75.0,
    .supply_voltage = 15.0,
});
```

### Specific Models
```zig
OpAmpModels.tl072()         // Low noise audio, 13MHz BW
OpAmpModels.lm358()         // General, single supply
OpAmpModels.ne5532()        // Audio grade, 10MHz BW
OpAmpModels.lm4562()        // Ultra low noise, 6MHz BW
```

### Methods
```zig
op.output(v_plus, v_minus)                    // Ideal op-amp
op.gainAt(frequency)                          // Frequency response
op.nonInvertingGain(input, feedback_r, input_r)  // Amplifier
op.invertingGain(input, feedback_r, input_r)    // Inverting amp
op.clipToRails(voltage)                       // Saturation
```

---

## Transistors

### Create Generic (with params)
```zig
let t = Transistor.init(.{
    .transistor_type = .npn,
    .beta = 200.0,
    .vbe_on = 0.65,
    .vce_sat = 0.2,
    .max_ic = 0.1,
});
```

### Specific Models
```zig
TransistorModels.bc549()           // NPN preamp, beta=200
TransistorModels.transistor2n2222() // NPN general, beta=255
TransistorModels.transistor2n3904() // NPN fast, beta=150
TransistorModels.bc327()           // PNP output stage, beta=200
TransistorModels.transistor2n2905() // PNP general, beta=100
```

### Methods
```zig
t.collectorCurrent(base_current)          // Ic = β*Ib
t.isSaturated(vce)                        // Check saturation
t.commonEmitterAmp(base_voltage, supply)  // CE configuration
t.distort(input)                          // Nonlinear distortion
```

---

## Common Circuit Patterns

### Low-Pass Filter (RC)
```zig
const c = CapacitorVariants.ceramicX7R(1e-6);
const r = ResistorVariants.metalFilm(10e3);
const fc = c.cutoffFrequency(r.resistance);
let output = c.processSignal(input, dt, r.resistance);
```

### High-Pass Filter (RC)
```zig
const c = CapacitorVariants.filmPolyester(1e-6);
const r = ResistorVariants.metalFilm(10e3);
let output = c.processSignal(input, dt, r.resistance);
```

### Diode Clipping
```zig
const d = DiodeModels.diode1N4148();
let clipped = d.softClip(input_signal);
```

### Amplifier
```zig
const op = OpAmpModels.tl072();
let gain = 10.0;  // 1 + Rf/Ri
let output = op.nonInvertingGain(input, 90e3, 10e3);
```

### Transistor Distortion
```zig
const t = TransistorModels.bc549();
let distorted = t.distort(input_signal);
```

---

## Parameter Quick Reference

### Resistor Tolerances
```
Carbon film:       5% (0.05)
Metal film:        1% (0.01)
Precision:         0.1% (0.001)
```

### Capacitor Voltage Ratings
```
Ceramic:           16V - 50V
Film:              63V - 100V
Electrolytic:      16V - 50V
Tantalum:          6V - 35V
```

### Diode Forward Drops
```
Silicon (1N4148):  0.65V (Vf typical)
Silicon (1N4007):  0.72V
Germanium (1N34A): 0.30V
Schottky:          0.30V
LED (Red):         2.0V
```

### OpAmp Bandwidths
```
TL072:             13 MHz
LM358:             1 MHz
NE5532:            10 MHz
LM4562:            6 MHz
```

### Transistor Betas
```
BC549:             200
2N2222:            255
2N3904:            150
BC327 (PNP):       200
2N2905 (PNP):      100
```

---

## Adding New Variant (Template)

```zig
pub fn myNewVariant(primary_value: f32) ComponentType {
    return ComponentType.initWith(
        primary_value,
        parameter1_value,
        parameter2_value,
    );
}
```

Example:
```zig
pub fn greenLED() Diode {
    return Diode.init(.{
        .saturation_current = 1e-17,
        .thermal_voltage = 0.026,
        .forward_drop = 2.2,    // Green LEDs drop ~2.2V
        .series_resistance = 50.0,
    });
}
```

---

## Testing Your Component

### Check 1: Basic Operation
```zig
const component = ComponentType.init(value);
const output = component.processSignal(input);
try std.testing.expect(output != 0);
```

### Check 2: Variant Consistency
```zig
const v1 = Variant1();
const v2 = Variant2();
// Same parameters should give same output
```

### Check 3: Physical Bounds
```zig
// Output should be reasonable
try std.testing.expect(output < supply_voltage);
try std.testing.expect(output > -supply_voltage);
```

---

## Files to Reference

| File | Purpose |
|------|---------|
| `components.zig` | All component definitions |
| `PARAMETRIZED_COMPONENTS.md` | Deep dive explanation |
| `ADDING_COMPONENTS.md` | How to add variants/types |
| `CIRCUIT_EXAMPLES.md` | Real circuit implementations |
| `PARAMETRIZED_SYSTEM_SUMMARY.md` | Overview & status |

---

## Key Principle

**Parametrization**: One algorithm, infinite variants

```zig
// This principle applies to all components:
// Generic.Algorithm() uses Component.params
// Different params → Different behavior
// Same code → Different results
```

