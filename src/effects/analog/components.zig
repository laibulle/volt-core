const std = @import("std");

/// Component value with unit
pub const ComponentValue = struct {
    magnitude: f32,
    unit: Unit,

    pub const Unit = enum {
        ohm,
        farad,
        henry,
        siemens,
        none,
    };

    /// Parse component value string (e.g., "10k", "100u", "2.2m")
    pub fn parse(value_str: []const u8) !ComponentValue {
        var magnitude: f32 = 0.0;
        var unit: Unit = .none;
        var has_digit = false;
        var decimal_pos: usize = 0;
        var is_decimal = false;

        for (value_str, 0..) |ch, i| {
            if (ch >= '0' and ch <= '9') {
                has_digit = true;
                const digit = @as(f32, @floatFromInt(ch - '0'));
                if (is_decimal) {
                    magnitude = magnitude + digit / std.math.pow(f32, 10.0, @floatFromInt(decimal_pos));
                    decimal_pos += 1;
                } else {
                    magnitude = magnitude * 10.0 + digit;
                }
            } else if (ch == '.') {
                is_decimal = true;
                decimal_pos = 1;
            } else if (ch >= 'a' and ch <= 'z' or ch >= 'A' and ch <= 'Z') {
                const suffix = value_str[i..];
                unit = parseUnitSuffix(suffix);
                break;
            }
        }

        if (!has_digit) return error.InvalidValue;

        return ComponentValue{
            .magnitude = magnitude,
            .unit = unit,
        };
    }

    fn parseUnitSuffix(suffix: []const u8) Unit {
        if (suffix.len == 0) return .none;
        return switch (std.ascii.toLower(suffix[0])) {
            'k' => .ohm,
            'm' => .none,
            'u' => .farad,
            'n' => .farad,
            'p' => .farad,
            else => .none,
        };
    }

    pub fn toBase(self: ComponentValue) f32 {
        const multiplier = switch (std.ascii.toLower(self.getUnitChar())) {
            'p' => 1e-12,
            'n' => 1e-9,
            'u' => 1e-6,
            'm' => 1e-3,
            'k' => 1e3,
            'M' => 1e6,
            'G' => 1e9,
            else => 1.0,
        };
        return self.magnitude * multiplier;
    }

    fn getUnitChar(self: ComponentValue) u8 {
        return ' ';
    }
};

/// ============================================================================
/// PARAMETRIZED COMPONENT SYSTEM
/// ============================================================================
/// Components are generic structures parametrized by their characteristics.
/// Specific variants (e.g., different diode models) are created by defining
/// specific parameters, reusing the same generic algorithm.
/// ============================================================================
/// RESISTORS - Generic + Variants
/// ============================================================================
pub const Resistor = struct {
    resistance: f32,
    impedance: f32 = 0.0,
    frequency: f32 = 0.0,
    tolerance: f32 = 0.05,
    max_power: f32 = 0.25,

    pub fn init(resistance_ohms: f32) Resistor {
        return Resistor{
            .resistance = resistance_ohms,
        };
    }

    pub fn initWith(resistance_ohms: f32, tolerance: f32, max_power: f32) Resistor {
        return Resistor{
            .resistance = resistance_ohms,
            .tolerance = tolerance,
            .max_power = max_power,
        };
    }

    pub fn impedanceAt(self: *Resistor, frequency_hz: f32) f32 {
        self.frequency = frequency_hz;
        self.impedance = self.resistance;
        return self.impedance;
    }

    pub fn processSignal(self: Resistor, signal: f32, load_impedance: f32) f32 {
        if (self.resistance + load_impedance == 0) return 0.0;
        return signal * (load_impedance / (self.resistance + load_impedance));
    }

    pub fn current(self: Resistor, voltage: f32) f32 {
        if (self.resistance == 0) return 0.0;
        return voltage / self.resistance;
    }

    pub fn power(self: Resistor, voltage: f32) f32 {
        if (self.resistance == 0) return 0.0;
        return (voltage * voltage) / self.resistance;
    }
};

/// Resistor variants - reuse generic algorithm with specific parameters
pub const ResistorVariants = struct {
    pub fn carbonFilm(resistance: f32) Resistor {
        return Resistor.initWith(resistance, 0.05, 0.25);
    }

    pub fn metalFilm(resistance: f32) Resistor {
        return Resistor.initWith(resistance, 0.01, 0.5);
    }

    pub fn precisionMetalFilm(resistance: f32) Resistor {
        return Resistor.initWith(resistance, 0.001, 0.5);
    }

    pub fn powerWireWound(resistance: f32) Resistor {
        return Resistor.initWith(resistance, 0.05, 5.0);
    }

    pub fn filmResistor(resistance: f32, tolerance: f32) Resistor {
        return Resistor.initWith(resistance, tolerance, 0.25);
    }
};

/// ============================================================================
/// CAPACITORS - Generic + Variants
/// ============================================================================
pub const Capacitor = struct {
    capacitance: f32,
    impedance: f32 = 0.0,
    reactance: f32 = 0.0,
    frequency: f32 = 0.0,
    voltage_state: f32 = 0.0,
    voltage_rating: f32 = 16.0,
    dielectric_type: DielectricType = .ceramic,

    pub const DielectricType = enum {
        ceramic,
        film,
        electrolytic,
        tantalum,
    };

    pub fn init(capacitance_farads: f32) Capacitor {
        return Capacitor{
            .capacitance = capacitance_farads,
        };
    }

    pub fn initWith(capacitance_farads: f32, voltage_rating: f32, dielectric: DielectricType) Capacitor {
        return Capacitor{
            .capacitance = capacitance_farads,
            .voltage_rating = voltage_rating,
            .dielectric_type = dielectric,
        };
    }

    pub fn reactanceAt(self: *Capacitor, frequency_hz: f32) f32 {
        if (frequency_hz <= 0 or self.capacitance <= 0) return 1e10;
        const two_pi_f_c = 2.0 * std.math.pi * frequency_hz * self.capacitance;
        self.reactance = 1.0 / two_pi_f_c;
        self.frequency = frequency_hz;
        self.impedance = self.reactance;
        return self.impedance;
    }

    pub fn processSignal(self: *Capacitor, input: f32, dt: f32, load_resistance: f32) f32 {
        const rc = load_resistance * self.capacitance;
        const alpha = rc / (rc + dt);
        const prev_voltage = self.voltage_state;
        self.voltage_state = alpha * input + (1.0 - alpha) * prev_voltage;
        return input - self.voltage_state;
    }

    pub fn charge(self: Capacitor, voltage: f32) f32 {
        return self.capacitance * voltage;
    }

    pub fn energy(self: Capacitor, voltage: f32) f32 {
        return 0.5 * self.capacitance * voltage * voltage;
    }

    pub fn cutoffFrequency(self: Capacitor, series_resistance: f32) f32 {
        const rc = series_resistance * self.capacitance;
        if (rc <= 0) return 0.0;
        return 1.0 / (2.0 * std.math.pi * rc);
    }

    /// Leakage current (voltage-dependent, varies by type)
    pub fn leakageCurrent(self: Capacitor, voltage: f32) f32 {
        return switch (self.dielectric_type) {
            .ceramic => 1e-9 * voltage * 0.01,
            .film => 1e-12 * voltage,
            .electrolytic => 1e-8 * voltage * 0.01,
            .tantalum => 1e-9 * voltage * 0.02,
        };
    }
};

/// Capacitor variants
pub const CapacitorVariants = struct {
    pub fn ceramicNPO(capacitance: f32) Capacitor {
        return Capacitor.initWith(capacitance, 50.0, .ceramic);
    }

    pub fn ceramicX7R(capacitance: f32) Capacitor {
        return Capacitor.initWith(capacitance, 16.0, .ceramic);
    }

    pub fn filmPolyester(capacitance: f32) Capacitor {
        return Capacitor.initWith(capacitance, 63.0, .film);
    }

    pub fn filmPolypropylene(capacitance: f32) Capacitor {
        return Capacitor.initWith(capacitance, 100.0, .film);
    }

    pub fn electrolyticAluminum(capacitance: f32, voltage_rating: f32) Capacitor {
        return Capacitor.initWith(capacitance, voltage_rating, .electrolytic);
    }

    pub fn tantalumSolid(capacitance: f32, voltage_rating: f32) Capacitor {
        return Capacitor.initWith(capacitance, voltage_rating, .tantalum);
    }
};

/// ============================================================================
/// INDUCTORS - Generic + Variants
/// ============================================================================
pub const Inductor = struct {
    inductance: f32,
    impedance: f32 = 0.0,
    reactance: f32 = 0.0,
    frequency: f32 = 0.0,
    current_state: f32 = 0.0,
    dc_resistance: f32 = 0.0,
    core_type: CoreType = .air,

    pub const CoreType = enum {
        air,
        iron_powder,
        ferrite,
        mu_metal,
    };

    pub fn init(inductance_henries: f32) Inductor {
        return Inductor{
            .inductance = inductance_henries,
        };
    }

    pub fn initWith(inductance_henries: f32, dc_resistance: f32, core_type: CoreType) Inductor {
        return Inductor{
            .inductance = inductance_henries,
            .dc_resistance = dc_resistance,
            .core_type = core_type,
        };
    }

    pub fn reactanceAt(self: *Inductor, frequency_hz: f32) f32 {
        self.reactance = 2.0 * std.math.pi * frequency_hz * self.inductance;
        self.frequency = frequency_hz;
        self.impedance = self.reactance;
        return self.impedance;
    }

    pub fn processSignal(self: *Inductor, input: f32, dt: f32, series_resistance: f32) f32 {
        const total_resistance = self.dc_resistance + series_resistance;
        const voltage_across_l = input - self.current_state * total_resistance;
        const current_delta = voltage_across_l * dt / self.inductance;
        self.current_state = self.current_state + current_delta;
        return self.current_state * total_resistance;
    }

    pub fn energy(self: Inductor, current: f32) f32 {
        return 0.5 * self.inductance * current * current;
    }

    pub fn resonantFrequency(self: Inductor, capacitance: f32) f32 {
        if (self.inductance <= 0 or capacitance <= 0) return 0.0;
        const lc = self.inductance * capacitance;
        return 1.0 / (2.0 * std.math.pi * @sqrt(lc));
    }

    /// Core saturation effect - reduces inductance at high currents
    pub fn saturationFactor(self: Inductor, current: f32) f32 {
        return switch (self.core_type) {
            .air => 1.0,
            .iron_powder => @max(0.5, 1.0 - @abs(current) * 0.1),
            .ferrite => @max(0.3, 1.0 - @abs(current) * 0.2),
            .mu_metal => @max(0.6, 1.0 - @abs(current) * 0.08),
        };
    }
};

/// Inductor variants
pub const InductorVariants = struct {
    pub fn airCore(inductance: f32) Inductor {
        return Inductor.initWith(inductance, 0.1, .air);
    }

    pub fn ironPowderCore(inductance: f32, dc_resistance: f32) Inductor {
        return Inductor.initWith(inductance, dc_resistance, .iron_powder);
    }

    pub fn ferriteCore(inductance: f32, dc_resistance: f32) Inductor {
        return Inductor.initWith(inductance, dc_resistance, .ferrite);
    }

    pub fn toroidalFerrite(inductance: f32, dc_resistance: f32) Inductor {
        return Inductor.initWith(inductance, dc_resistance, .ferrite);
    }

    pub fn muMetalShielded(inductance: f32) Inductor {
        return Inductor.initWith(inductance, 0.05, .mu_metal);
    }
};

/// ============================================================================
/// DIODES - Generic + Specific Models
/// ============================================================================
pub const DiodeParams = struct {
    saturation_current: f32,
    thermal_voltage: f32,
    forward_drop: f32,
    series_resistance: f32,
};

pub const Diode = struct {
    params: DiodeParams,

    pub fn init(params: DiodeParams) Diode {
        return Diode{ .params = params };
    }

    pub fn current(self: Diode, voltage: f32) f32 {
        if (voltage < 0) {
            return -self.params.saturation_current;
        }
        const exp_v_vt = @exp(voltage / self.params.thermal_voltage);
        return self.params.saturation_current * (exp_v_vt - 1.0);
    }

    pub fn clipSignal(self: Diode, input: f32) f32 {
        if (input > self.params.forward_drop) {
            return self.params.forward_drop;
        } else if (input < -self.params.forward_drop) {
            return -self.params.forward_drop;
        }
        return input;
    }

    pub fn softClip(self: Diode, input: f32) f32 {
        const threshold = self.params.forward_drop;
        if (input > threshold) {
            return threshold + @tanh((input - threshold) / threshold) * threshold;
        } else if (input < -threshold) {
            return -threshold - @tanh((-input - threshold) / threshold) * threshold;
        }
        return input;
    }

    pub fn asymmetricClip(self: Diode, input: f32) f32 {
        if (input > self.params.forward_drop) {
            return self.params.forward_drop + (input - self.params.forward_drop) * 0.1;
        } else if (input < -self.params.forward_drop * 0.5) {
            return -self.params.forward_drop * 0.5;
        }
        return input;
    }

    pub fn dynamicResistance(self: Diode, voltage: f32) f32 {
        const i = self.current(voltage);
        if (@abs(i) < 1e-15) return 1e10;
        return self.params.thermal_voltage / i;
    }
};

/// Specific diode models - reuse generic algorithm with different parameters
pub const DiodeModels = struct {
    /// 1N4148 - Fast switching diode (commonly used in circuits)
    pub fn diode1N4148() Diode {
        return Diode.init(.{
            .saturation_current = 2.68e-15,
            .thermal_voltage = 0.0257,
            .forward_drop = 0.65,
            .series_resistance = 6.0,
        });
    }

    /// 1N4007 - General purpose rectifier (slower, high voltage)
    pub fn diode1N4007() Diode {
        return Diode.init(.{
            .saturation_current = 7.61e-15,
            .thermal_voltage = 0.0256,
            .forward_drop = 0.72,
            .series_resistance = 15.0,
        });
    }

    /// 1N34A - Germanium diode (lower forward drop, vintage)
    pub fn diode1N34A() Diode {
        return Diode.init(.{
            .saturation_current = 1.2e-12,
            .thermal_voltage = 0.026,
            .forward_drop = 0.3,
            .series_resistance = 20.0,
        });
    }

    /// 1N60 - Germanium point contact (used in fuzz boxes)
    pub fn diode1N60() Diode {
        return Diode.init(.{
            .saturation_current = 1e-12,
            .thermal_voltage = 0.026,
            .forward_drop = 0.25,
            .series_resistance = 50.0,
        });
    }

    /// Schottky diode BAT54 - Very low forward drop
    pub fn schottkyBAT54() Diode {
        return Diode.init(.{
            .saturation_current = 5e-15,
            .thermal_voltage = 0.026,
            .forward_drop = 0.3,
            .series_resistance = 10.0,
        });
    }

    /// LED - High forward drop, different curve
    pub fn redLED() Diode {
        return Diode.init(.{
            .saturation_current = 1e-17,
            .thermal_voltage = 0.026,
            .forward_drop = 2.0,
            .series_resistance = 50.0,
        });
    }

    /// Generic diode with custom parameters
    pub fn custom(params: DiodeParams) Diode {
        return Diode.init(params);
    }
};

/// ============================================================================
/// OPERATIONAL AMPLIFIERS - Generic + Variants
/// ============================================================================
pub const OpAmpParams = struct {
    gain: f32,
    bandwidth: f32,
    slew_rate: f32,
    input_impedance: f32,
    output_impedance: f32,
    supply_voltage: f32,
};

pub const OpAmp = struct {
    params: OpAmpParams,

    pub fn init(params: OpAmpParams) OpAmp {
        return OpAmp{ .params = params };
    }

    pub fn output(self: OpAmp, v_plus: f32, v_minus: f32) f32 {
        const raw_output = self.params.gain * (v_plus - v_minus);
        const max_out = self.params.supply_voltage;
        const min_out = -self.params.supply_voltage;

        if (raw_output > max_out) return max_out;
        if (raw_output < min_out) return min_out;
        return raw_output;
    }

    pub fn gainAt(self: OpAmp, frequency_hz: f32) f32 {
        if (self.params.bandwidth <= 0) return 1.0;
        const gain_bw_product = self.params.gain * self.params.bandwidth;
        return gain_bw_product / frequency_hz;
    }

    pub fn nonInvertingGain(self: OpAmp, input: f32, feedback_r: f32, input_r: f32) f32 {
        const gain = 1.0 + (feedback_r / input_r);
        return input * gain;
    }

    pub fn invertingGain(self: OpAmp, input: f32, feedback_r: f32, input_r: f32) f32 {
        const gain = -(feedback_r / input_r);
        return input * gain;
    }

    pub fn clipToRails(self: OpAmp, voltage: f32) f32 {
        const max_v = self.params.supply_voltage;
        const min_v = -self.params.supply_voltage;
        if (voltage > max_v) return max_v;
        if (voltage < min_v) return min_v;
        return voltage;
    }
};

/// OpAmp variants
pub const OpAmpModels = struct {
    /// TL072 - Low noise dual opamp (common in audio)
    pub fn tl072() OpAmp {
        return OpAmp.init(.{
            .gain = 200000.0,
            .bandwidth = 13e6,
            .slew_rate = 13.0e6,
            .input_impedance = 2e12,
            .output_impedance = 75.0,
            .supply_voltage = 15.0,
        });
    }

    /// LM358 - General purpose, single supply
    pub fn lm358() OpAmp {
        return OpAmp.init(.{
            .gain = 100000.0,
            .bandwidth = 1e6,
            .slew_rate = 0.5e6,
            .input_impedance = 2e6,
            .output_impedance = 75.0,
            .supply_voltage = 5.0,
        });
    }

    /// NE5532 - Audio grade (less noise)
    pub fn ne5532() OpAmp {
        return OpAmp.init(.{
            .gain = 200000.0,
            .bandwidth = 10e6,
            .slew_rate = 9.5e6,
            .input_impedance = 3e6,
            .output_impedance = 60.0,
            .supply_voltage = 15.0,
        });
    }

    /// LM4562 - Ultra low noise audio opamp
    pub fn lm4562() OpAmp {
        return OpAmp.init(.{
            .gain = 200000.0,
            .bandwidth = 6e6,
            .slew_rate = 12.0e6,
            .input_impedance = 3e6,
            .output_impedance = 50.0,
            .supply_voltage = 15.0,
        });
    }

    /// Custom opamp with specified parameters
    pub fn custom(params: OpAmpParams) OpAmp {
        return OpAmp.init(params);
    }
};

/// ============================================================================
/// TRANSISTORS - Generic + Variants
/// ============================================================================
pub const TransistorParams = struct {
    transistor_type: Type,
    beta: f32,
    vbe_on: f32,
    vce_sat: f32,
    max_ic: f32,
};

pub const Transistor = struct {
    pub const Type = enum { npn, pnp };

    params: TransistorParams,

    pub fn init(params: TransistorParams) Transistor {
        return Transistor{ .params = params };
    }

    pub fn collectorCurrent(self: Transistor, base_current: f32) f32 {
        return self.params.beta * base_current;
    }

    pub fn isSaturated(self: Transistor, vce: f32) bool {
        return vce < self.params.vce_sat;
    }

    pub fn commonEmitterAmp(self: Transistor, base_voltage: f32, supply_voltage: f32) f32 {
        if (base_voltage < self.params.vbe_on) {
            return supply_voltage;
        }
        const base_current = (base_voltage - self.params.vbe_on) / 100000.0;
        const ic = self.collectorCurrent(base_current);
        return supply_voltage - (ic * 5000.0);
    }

    pub fn distort(self: Transistor, input: f32) f32 {
        const biased = input + self.params.vbe_on;
        const output = self.commonEmitterAmp(biased, 9.0);
        return output * 0.1;
    }
};

/// Transistor variants
pub const TransistorModels = struct {
    /// BC549 - Small signal transistor (common in audio circuits)
    pub fn bc549() Transistor {
        return Transistor.init(.{
            .transistor_type = .npn,
            .beta = 200.0,
            .vbe_on = 0.65,
            .vce_sat = 0.2,
            .max_ic = 0.1,
        });
    }

    /// 2N2222 - General purpose NPN
    pub fn transistor2n2222() Transistor {
        return Transistor.init(.{
            .transistor_type = .npn,
            .beta = 255.0,
            .vbe_on = 0.7,
            .vce_sat = 0.3,
            .max_ic = 0.6,
        });
    }

    /// 2N3904 - Small signal, fast switching
    pub fn transistor2n3904() Transistor {
        return Transistor.init(.{
            .transistor_type = .npn,
            .beta = 150.0,
            .vbe_on = 0.6,
            .vce_sat = 0.2,
            .max_ic = 0.2,
        });
    }

    /// 2N2905 - General purpose PNP
    pub fn transistor2n2905() Transistor {
        return Transistor.init(.{
            .transistor_type = .pnp,
            .beta = 100.0,
            .vbe_on = 0.7,
            .vce_sat = 0.3,
            .max_ic = 0.6,
        });
    }

    /// BC327 - Audio output stage
    pub fn bc327() Transistor {
        return Transistor.init(.{
            .transistor_type = .pnp,
            .beta = 200.0,
            .vbe_on = 0.65,
            .vce_sat = 0.2,
            .max_ic = 1.0,
        });
    }

    /// Custom transistor with specified parameters
    pub fn custom(params: TransistorParams) Transistor {
        return Transistor.init(params);
    }
};

// ============================================================================
// UNIT TESTS
// ============================================================================

test "resistor variants use same algorithm" {
    const carbon = ResistorVariants.carbonFilm(10000.0);
    const metal = ResistorVariants.metalFilm(10000.0);

    // Same input, same processing but different tolerances
    const input: f32 = 1.0;
    const load: f32 = 10000.0;

    const output_carbon = carbon.processSignal(input, load);
    const output_metal = metal.processSignal(input, load);

    // Same algorithm produces identical results
    try std.testing.expect(output_carbon == output_metal);
    try std.testing.expect(carbon.tolerance == 0.05);
    try std.testing.expect(metal.tolerance == 0.01);
}

test "diode models use same algorithm with different parameters" {
    const silicon = DiodeModels.diode1N4148();
    const germanium = DiodeModels.diode1N34A();

    const voltage: f32 = 0.5;

    // Different models produce different results based on parameters
    const current_si = silicon.current(voltage);
    const current_ge = germanium.current(voltage);

    try std.testing.expect(current_si != current_ge);
    try std.testing.expect(silicon.params.forward_drop > germanium.params.forward_drop);
}

test "opamp variants use same algorithm" {
    const tl072 = OpAmpModels.tl072();
    const lm358 = OpAmpModels.lm358();

    const gain_tl = tl072.gainAt(1000.0);
    const gain_lm = lm358.gainAt(1000.0);

    try std.testing.expect(gain_tl > gain_lm);
    try std.testing.expect(tl072.params.bandwidth > lm358.params.bandwidth);
}

test "capacitor variants with different dielectrics" {
    const ceramic = CapacitorVariants.ceramicNPO(1e-6);
    const film = CapacitorVariants.filmPolyester(1e-6);

    // Same capacitance, different leakage characteristics
    try std.testing.expect(ceramic.dielectric_type == .ceramic);
    try std.testing.expect(film.dielectric_type == .film);

    const leakage_ceramic = ceramic.leakageCurrent(5.0);
    const leakage_film = film.leakageCurrent(5.0);

    try std.testing.expect(leakage_ceramic > leakage_film);
}

test "transistor models parameterized" {
    const npn = TransistorModels.bc549();
    const pnp = TransistorModels.transistor2n2905();

    try std.testing.expect(npn.params.transistor_type == .npn);
    try std.testing.expect(pnp.params.transistor_type == .pnp);
    try std.testing.expect(npn.params.beta == 200.0);
    try std.testing.expect(pnp.params.beta == 100.0);
}
