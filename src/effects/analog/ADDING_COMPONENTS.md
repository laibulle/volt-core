# Adding New Components & Variants Guide

## Quick Start: Adding a New Component Variant

### Example 1: Add New Resistor Type

**Goal**: Add a film resistor variant with custom tolerance

```zig
// In ResistorVariants struct (components_v2.zig)
pub fn filmResistor_05percent(resistance: f32) Resistor {
    return Resistor.initWith(resistance, 0.005, 0.25); // 0.5% tolerance
}

// Use it:
const r = ResistorVariants.filmResistor_05percent(47000.0);
const output = r.processSignal(input, load_impedance);
```

**Lines changed**: 1-3 (just add one function)
**Algorithm changes**: 0 (reuses existing `Resistor.processSignal`)

---

### Example 2: Add New Diode Model

**Goal**: Add a specific diode model for a particular circuit

```zig
// In DiodeModels struct (components_v2.zig)
pub fn diodeOA91() Diode {
    return Diode.init(.{
        .saturation_current = 8e-13,  // Germanium - higher Is
        .thermal_voltage = 0.026,
        .forward_drop = 0.2,           // Germanium - lower Vf
        .series_resistance = 100.0,    // Germanium - higher Rs
    });
}

// Use it:
const d = DiodeModels.diodeOA91();
const clipped = d.softClip(input_signal);
```

**Lines changed**: 1-7 (one function with parameters)
**Algorithm changes**: 0 (reuses existing `Diode.softClip`)
**Result**: Physically accurate behavior without code duplication

---

### Example 3: Add Capacitor Variant with New Dielectric

**Goal**: Add a supercapacitor variant

```zig
// In CapacitorVariants struct
pub fn supercap_doubleLayer(capacitance: f32) Capacitor {
    return Capacitor.initWith(capacitance, 5.5, .film);
}

// Use it:
const c = CapacitorVariants.supercap_doubleLayer(0.47);
const leakage = c.leakageCurrent(5.0);
```

**Lines changed**: 1-3
**Algorithm changes**: 0

---

### Example 4: Add OpAmp Variant

**Goal**: Add vintage opamp model

```zig
// In OpAmpModels struct
pub fn mc1458() OpAmp {
    return OpAmp.init(.{
        .gain = 200000.0,
        .bandwidth = 1e6,          // Limited bandwidth = vintage tone
        .slew_rate = 0.5e6,        // Slow slew rate
        .input_impedance = 2e6,
        .output_impedance = 75.0,
        .supply_voltage = 15.0,
    });
}

// Use it:
const opamp = OpAmpModels.mc1458();
const output = opamp.nonInvertingGain(input, 10000.0, 1000.0);
```

**Lines changed**: 1-9
**Algorithm changes**: 0

---

## Adding a Completely New Component Type

### Step 1: Define Parameter Structure

```zig
pub const NewComponentParams = struct {
    param1: f32,
    param2: f32,
    param3_enum: SomeEnum,
    // ... other parameters
};
```

### Step 2: Create Generic Component

```zig
pub const NewComponent = struct {
    params: NewComponentParams,
    state: f32 = 0.0,  // For components with history

    pub fn init(params: NewComponentParams) NewComponent {
        return NewComponent{ .params = params };
    }

    // Generic algorithm (used by all variants)
    pub fn processSignal(self: *NewComponent, input: f32) f32 {
        // Physical model using self.params
        return generic_algorithm(input, self.params);
    }

    // Other methods...
    pub fn someCalculation(self: NewComponent) f32 {
        // ...
    }
};
```

### Step 3: Create Variant Functions

```zig
pub const NewComponentModels = struct {
    pub fn variant1() NewComponent {
        return NewComponent.init(.{
            .param1 = 0.5,
            .param2 = 1000.0,
            .param3_enum = .type_a,
        });
    }

    pub fn variant2() NewComponent {
        return NewComponent.init(.{
            .param1 = 0.8,
            .param2 = 2000.0,
            .param3_enum = .type_b,
        });
    }

    pub fn custom(params: NewComponentParams) NewComponent {
        return NewComponent.init(params);
    }
};
```

### Step 4: Add Unit Tests

```zig
test "new component variant 1" {
    const comp = NewComponentModels.variant1();
    const output = comp.processSignal(1.0);
    try std.testing.expect(output > 0);
}

test "new component variants use same algorithm" {
    const v1 = NewComponentModels.variant1();
    const v2 = NewComponentModels.variant2();

    // Same parameters → same result
    const params_same = v1.params;
    const comp_same = NewComponent.init(params_same);
    
    const output1 = v1.processSignal(1.0);
    const output_same = comp_same.processSignal(1.0);
    
    try std.testing.expect(output1 == output_same);
}
```

### Step 5: Export from analog.zig

```zig
// In src/effects/analog/analog.zig
pub const components = @import("components_v2.zig");

// Export the new component
pub const NewComponent = components.NewComponent;
pub const NewComponentModels = components.NewComponentModels;
```

---

## Parameter Design Guidelines

### For Passive Components (R, L, C)

**Parameters to consider**:
- Primary value (resistance, capacitance, inductance)
- Tolerance/precision
- Power/voltage rating
- Temperature coefficient
- Frequency range

**Example - Resistor**:
```zig
resistance: f32,        // Primary value (Ohms)
tolerance: f32,         // Manufacturing tolerance (0.01-0.20)
max_power: f32,         // Power rating (0.25W, 0.5W, 5W)
temp_coeff: f32 = 0.0,  // Temperature coefficient (future)
```

### For Nonlinear Components (Diode, Transistor)

**Parameters to consider**:
- DC characteristics (Is, Vbe, beta)
- Switching parameters (reverse recovery, transition time)
- Frequency limits
- Temperature dependence

**Example - Diode**:
```zig
saturation_current: f32,  // Is (1e-15 to 1e-12)
thermal_voltage: f32,     // Vt ≈ 0.026V at room temp
forward_drop: f32,        // Vf (0.2V to 2V depending on type)
series_resistance: f32,   // Parasitic resistance
```

### For Active Components (OpAmp, Transistor)

**Parameters to consider**:
- Gain (DC and frequency-dependent)
- Bandwidth and slew rate
- Supply voltages
- Input/output impedance

**Example - OpAmp**:
```zig
gain: f32,              // Open-loop DC gain (100k to 200k+)
bandwidth: f32,         // -3dB bandwidth (1MHz to 13MHz+)
slew_rate: f32,         // V/µs (0.5 to 20)
supply_voltage: f32,    // Rail voltage (5V to 15V)
```

---

## Naming Conventions

### Generic Types
- `ComponentName` (singular, generic)
- Example: `Diode`, `Resistor`, `OpAmp`

### Variant Collections
- `ComponentNameVariants` or `ComponentNameModels`
- Example: `DiodeModels.diode1N4148()`, `ResistorVariants.metalFilm()`

### Parameter Structures
- `ComponentNameParams` or `ComponentTypeParams`
- Example: `DiodeParams`, `OpAmpParams`

### Enum Variants
- `componentType` or `variant_name`
- Example: `DielectricType`, `CoreType`, `Type` (for transistor NPN/PNP)

---

## Real-World Examples

### Example: Adding Silicon vs Germanium Diodes

**Concept**: Same algorithm, different Is and Vf

```zig
pub const DiodeModels = struct {
    // Silicon - high Is, high Vf
    pub fn silicon1N4148() Diode {
        return Diode.init(.{
            .saturation_current = 2.68e-15,  // ← Key difference
            .thermal_voltage = 0.0257,
            .forward_drop = 0.65,            // ← Key difference
            .series_resistance = 6.0,
        });
    }

    // Germanium - higher Is, lower Vf
    pub fn germanium1N34A() Diode {
        return Diode.init(.{
            .saturation_current = 1.2e-12,   // ← Much higher
            .thermal_voltage = 0.026,
            .forward_drop = 0.3,             // ← Much lower
            .series_resistance = 20.0,
        });
    }
};
```

**Result**: Same `current()` and `softClip()` methods, but:
- Germanium clips softer (lower Vf)
- Germanium conducts at lower voltages (higher Is)
- Different clipping character in circuits

### Example: Adding Component Tolerance Options

**Concept**: Same value, different tolerance

```zig
pub const ResistorVariants = struct {
    // Standard 5%
    pub fn standard(resistance: f32) Resistor {
        return Resistor.initWith(resistance, 0.05, 0.25);
    }

    // Precision 1%
    pub fn precision(resistance: f32) Resistor {
        return Resistor.initWith(resistance, 0.01, 0.25);
    }

    // High precision 0.1%
    pub fn highPrecision(resistance: f32) Resistor {
        return Resistor.initWith(resistance, 0.001, 0.25);
    }
};
```

**Use in circuit analysis**:
```zig
// Worst-case analysis
const r_min = ResistorVariants.standard(10000.0).resistance * (1 - 0.05);
const r_max = ResistorVariants.standard(10000.0).resistance * (1 + 0.05);

// Precise circuit
const r_precise = ResistorVariants.highPrecision(10000.0);
```

---

## Testing Strategy

### Test 1: Variant Consistency
```zig
test "all resistor variants use same algorithm" {
    const carbon = ResistorVariants.carbonFilm(1000.0);
    const metal = ResistorVariants.metalFilm(1000.0);
    
    const input = 5.0;
    const load = 1000.0;
    
    // Same parameters → same output
    try std.testing.expect(carbon.processSignal(input, load) == 
                           metal.processSignal(input, load));
}
```

### Test 2: Physical Differences
```zig
test "germanium vs silicon diodes produce different behavior" {
    const si = DiodeModels.diode1N4148();
    const ge = DiodeModels.diode1N34A();
    
    // Different parameters
    try std.testing.expect(si.params.forward_drop > ge.params.forward_drop);
    
    // Produces different clipping
    try std.testing.expect(si.softClip(1.0) != ge.softClip(1.0));
}
```

### Test 3: Edge Cases
```zig
test "component handles edge cases" {
    const r = Resistor.init(1000.0);
    
    // Zero input
    try std.testing.expect(r.processSignal(0.0, 1000.0) == 0.0);
    
    // Very high impedance
    const output = r.processSignal(1.0, 1e10);
    try std.testing.expect(output > 0.999);
}
```

---

## Performance Tips

1. **Keep parameters simple** - Float values only (no complex calculations)
2. **Precompute in init** - Store derived values if needed
3. **Use inline calculations** - Let compiler optimize simple functions
4. **Minimize state** - Only store necessary history for filters

---

## Checklist: Adding a New Component

- [ ] Define parameter structure (`ComponentParams`)
- [ ] Create generic component struct with `init()` method
- [ ] Implement generic algorithm (processSignal, etc.)
- [ ] Create variant struct with specific models
- [ ] Add unit tests for variants
- [ ] Add unit test for algorithm consistency
- [ ] Export from `analog.zig`
- [ ] Document in PARAMETRIZED_COMPONENTS.md
- [ ] Build and test: `zig build test`

---

## Future Enhancements

### Planned Features
1. **Temperature parameters** - Add `temperature: f32` to all components
2. **Frequency models** - Advanced Bode plots for precise frequency response
3. **Monte Carlo tolerance** - Randomize within tolerance for analysis
4. **Aging effects** - Capacitor degradation, resistor drift
5. **Thermal runaway** - Temperature feedback for power components
6. **Hysteresis** - For devices with memory effects

### Planned Component Types
1. **JFET/MOSFET** - Voltage-controlled transistors
2. **Transformer** - Inductive coupling with frequency response
3. **Thermistor** - Temperature-dependent resistor
4. **Varistor** - Voltage-dependent resistor
5. **Varactor** - Voltage-dependent capacitor
6. **Relay** - Switching with delay and bounce

