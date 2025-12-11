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
                // Parse unit suffix
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
            'k' => blk: {
                // k = kilo (1000x)
                break :blk .ohm; // Context dependent - could be k-ohm, k-farad, etc.
            },
            'm' => .none, // Could be milli or mega - context dependent
            'u' => .farad, // Micro farad typically
            'n' => .farad, // Nano farad typically
            'p' => .farad, // Pico farad typically
            else => .none,
        };
    }

    /// Convert to base units (ohms, farads, henries)
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
        // This is a simplified version - would need actual suffix storage
        return ' ';
    }
};

/// ============================================================================
/// PARAMETRIZED GENERIC COMPONENTS
/// ============================================================================
/// Each component type is generic and parametrized. Specific variants are
/// created by instantiating with specific parameters.

/// Resistor component with signal transformation
pub const Resistor = struct {
    resistance: f32, // in ohms
    impedance: f32 = 0.0, // frequency-dependent
    frequency: f32 = 0.0,

    pub fn init(resistance_ohms: f32) Resistor {
        return Resistor{
            .resistance = resistance_ohms,
        };
    }

    /// Calculate impedance at given frequency
    pub fn impedanceAt(self: *Resistor, frequency_hz: f32) f32 {
        // For resistors, impedance is purely resistive (frequency independent)
        self.frequency = frequency_hz;
        self.impedance = self.resistance;
        return self.impedance;
    }

    /// Apply resistor to signal (voltage divider)
    /// signal: input voltage
    /// load_resistance: load impedance
    /// returns: attenuated signal
    pub fn processSignal(self: Resistor, signal: f32, load_resistance: f32) f32 {
        // Voltage divider: V_out = V_in * (R_load / (R + R_load))
        if (self.resistance + load_resistance == 0) return 0.0;
        return signal * (load_resistance / (self.resistance + load_resistance));
    }

    /// Get current through resistor (Ohm's law: I = V/R)
    pub fn current(self: Resistor, voltage: f32) f32 {
        if (self.resistance == 0) return 0.0;
        return voltage / self.resistance;
    }

    /// Get power dissipation: P = I^2 * R = V^2 / R
    pub fn power(self: Resistor, voltage: f32) f32 {
        if (self.resistance == 0) return 0.0;
        return (voltage * voltage) / self.resistance;
    }
};

/// Capacitor component with frequency-dependent behavior
pub const Capacitor = struct {
    capacitance: f32, // in farads
    impedance: f32 = 0.0,
    reactance: f32 = 0.0,
    frequency: f32 = 0.0,
    voltage_state: f32 = 0.0, // voltage stored (history)

    pub fn init(capacitance_farads: f32) Capacitor {
        return Capacitor{
            .capacitance = capacitance_farads,
        };
    }

    /// Calculate capacitive reactance: Xc = 1 / (2 * pi * f * C)
    pub fn reactanceAt(self: *Capacitor, frequency_hz: f32) f32 {
        if (frequency_hz <= 0 or self.capacitance <= 0) return 1e10; // Very high impedance
        const two_pi_f_c = 2.0 * std.math.pi * frequency_hz * self.capacitance;
        self.reactance = 1.0 / two_pi_f_c;
        self.frequency = frequency_hz;
        self.impedance = self.reactance; // For AC analysis, impedance = reactance
        return self.impedance;
    }

    /// Calculate impedance magnitude (for complex impedance)
    pub fn impedanceMagnitude(self: Capacitor) f32 {
        return self.impedance;
    }

    /// Process signal with capacitive coupling (high-pass filter effect)
    /// input: input signal voltage
    /// dt: sample time (1/sample_rate)
    /// load_resistance: load impedance
    /// returns: filtered output
    pub fn processSignal(self: *Capacitor, input: f32, dt: f32, load_resistance: f32) f32 {
        // Simple RC high-pass filter: y = alpha * (y_prev + x - x_prev)
        // where alpha = R*C / (R*C + dt)
        const rc = load_resistance * self.capacitance;
        const alpha = rc / (rc + dt);

        // For AC signal, capacitor passes high frequencies
        // At DC or very low freq: blocking
        // At high freq: passes through
        const output = alpha * input + (1.0 - alpha) * self.voltage_state;
        self.voltage_state = output;
        return output;
    }

    /// Charge stored in capacitor: Q = C * V
    pub fn charge(self: Capacitor, voltage: f32) f32 {
        return self.capacitance * voltage;
    }

    /// Energy stored: E = 0.5 * C * V^2
    pub fn energy(self: Capacitor, voltage: f32) f32 {
        return 0.5 * self.capacitance * voltage * voltage;
    }

    /// High-pass cutoff frequency: f_c = 1 / (2 * pi * R * C)
    pub fn cutoffFrequency(self: Capacitor, series_resistance: f32) f32 {
        if (series_resistance <= 0 or self.capacitance <= 0) return 0.0;
        return 1.0 / (2.0 * std.math.pi * series_resistance * self.capacitance);
    }
};

/// Inductor component with frequency-dependent behavior
pub const Inductor = struct {
    inductance: f32, // in henries
    impedance: f32 = 0.0,
    reactance: f32 = 0.0,
    frequency: f32 = 0.0,
    current_state: f32 = 0.0, // current through inductor (history)

    pub fn init(inductance_henries: f32) Inductor {
        return Inductor{
            .inductance = inductance_henries,
        };
    }

    /// Calculate inductive reactance: XL = 2 * pi * f * L
    pub fn reactanceAt(self: *Inductor, frequency_hz: f32) f32 {
        self.reactance = 2.0 * std.math.pi * frequency_hz * self.inductance;
        self.frequency = frequency_hz;
        self.impedance = self.reactance;
        return self.impedance;
    }

    /// Process signal with inductive effect (low-pass filter effect)
    /// input: input signal voltage
    /// dt: sample time (1/sample_rate)
    /// series_resistance: wire resistance
    /// returns: filtered output
    pub fn processSignal(self: *Inductor, input: f32, dt: f32, series_resistance: f32) f32 {
        // RL circuit: V = L * dI/dt + I * R
        // Discrete: I_new = I_old + (V - I*R) * dt / L
        const voltage_across_l = input - self.current_state * series_resistance;
        const current_delta = voltage_across_l * dt / self.inductance;
        self.current_state = self.current_state + current_delta;

        // Output voltage across series resistance
        return self.current_state * series_resistance;
    }

    /// Energy stored in inductor: E = 0.5 * L * I^2
    pub fn energy(self: Inductor, current: f32) f32 {
        return 0.5 * self.inductance * current * current;
    }

    /// Resonant frequency with capacitor: f_r = 1 / (2 * pi * sqrt(L*C))
    pub fn resonantFrequency(self: Inductor, capacitance: f32) f32 {
        if (self.inductance <= 0 or capacitance <= 0) return 0.0;
        const lc = self.inductance * capacitance;
        return 1.0 / (2.0 * std.math.pi * @sqrt(lc));
    }
};

/// Diode component with nonlinear behavior
pub const Diode = struct {
    // Shockley diode equation parameters
    saturation_current: f32 = 1e-14, // Is (amperes)
    thermal_voltage: f32 = 0.026, // Vt at 300K ≈ kT/q
    forward_drop: f32 = 0.7, // Typical forward voltage drop

    pub fn init() Diode {
        return Diode{};
    }

    /// Shockley diode equation: I = Is * (exp(V/Vt) - 1)
    /// Returns current given voltage across diode
    pub fn current(self: Diode, voltage: f32) f32 {
        if (voltage < 0) {
            // Reverse bias: small leakage current
            return -self.saturation_current;
        }

        // Forward bias: exponential current
        const exp_v_vt = @exp(voltage / self.thermal_voltage);
        return self.saturation_current * (exp_v_vt - 1.0);
    }

    /// Simplified ideal diode model for audio signal
    /// input: input signal
    /// returns: hard clipped output
    pub fn clipSignal(self: Diode, input: f32) f32 {
        // Simple diode clipping
        if (input > self.forward_drop) {
            return self.forward_drop;
        } else if (input < -self.forward_drop) {
            return -self.forward_drop;
        }
        return input;
    }

    /// Soft clipping with diode curve approximation
    /// Smoother than hard clipping
    pub fn softClip(self: Diode, input: f32) f32 {
        const threshold = self.forward_drop;
        if (input > threshold) {
            // Tanh-like soft clipping
            return threshold + @tanh((input - threshold) / threshold) * threshold;
        } else if (input < -threshold) {
            return -threshold - @tanh((-input - threshold) / threshold) * threshold;
        }
        return input;
    }

    /// Asymmetric clipping (typical of guitar circuits)
    /// Forward bias clips more than reverse bias
    pub fn asymmetricClip(self: Diode, input: f32) f32 {
        if (input > self.forward_drop) {
            return self.forward_drop + (input - self.forward_drop) * 0.1; // Gentle clipping
        } else if (input < -self.forward_drop * 0.5) {
            return -self.forward_drop * 0.5; // Sharper reverse clipping
        }
        return input;
    }

    /// Dynamic resistance (differential resistance)
    /// rd = Vt / I
    pub fn dynamicResistance(self: Diode, voltage: f32) f32 {
        const i = self.current(voltage);
        if (@abs(i) < 1e-15) return 1e10; // Very high for small currents
        return self.thermal_voltage / i;
    }
};

/// Operational Amplifier (ideal model)
pub const OpAmp = struct {
    gain: f32 = 100000.0, // Open-loop DC gain
    bandwidth: f32 = 1e6, // Bandwidth in Hz
    slew_rate: f32 = 0.5e6, // Volts/microsecond
    input_impedance: f32 = 2e6, // Megaohms
    output_impedance: f32 = 75.0, // Ohms
    supply_voltage: f32 = 15.0, // Plus/minus supply

    pub fn init(gain: f32, bandwidth: f32) OpAmp {
        return OpAmp{
            .gain = gain,
            .bandwidth = bandwidth,
        };
    }

    /// Ideal op-amp: output = gain * (V+ - V-)
    /// With output clipping to supply rails
    pub fn output(self: OpAmp, v_plus: f32, v_minus: f32) f32 {
        const raw_output = self.gain * (v_plus - v_minus);
        // Saturate to supply voltage
        const max_out = self.supply_voltage;
        const min_out = -self.supply_voltage;

        if (raw_output > max_out) return max_out;
        if (raw_output < min_out) return min_out;
        return raw_output;
    }

    /// Frequency response at given frequency
    /// Returns gain magnitude at that frequency
    pub fn gainAt(self: OpAmp, frequency_hz: f32) f32 {
        if (frequency_hz <= 0) return self.gain;
        // -3dB bandwidth model
        const ratio = frequency_hz / self.bandwidth;
        return self.gain / @sqrt(1.0 + ratio * ratio);
    }

    /// Non-inverting amplifier: Vout = Vin * (1 + Rf/Ri)
    pub fn nonInvertingGain(self: OpAmp, input: f32, feedback_resistor: f32, input_resistor: f32) f32 {
        const closed_loop_gain = 1.0 + (feedback_resistor / input_resistor);
        const output = input * closed_loop_gain;
        return self.clipToRails(output);
    }

    /// Inverting amplifier: Vout = -Vin * (Rf/Ri)
    pub fn invertingGain(self: OpAmp, input: f32, feedback_resistor: f32, input_resistor: f32) f32 {
        const closed_loop_gain = -(feedback_resistor / input_resistor);
        const output = input * closed_loop_gain;
        return self.clipToRails(output);
    }

    fn clipToRails(self: OpAmp, voltage: f32) f32 {
        if (voltage > self.supply_voltage) return self.supply_voltage;
        if (voltage < -self.supply_voltage) return -self.supply_voltage;
        return voltage;
    }
};

/// Transistor component (simplified BJT model)
pub const Transistor = struct {
    typ: Type,
    beta: f32 = 100.0, // Current gain hFE
    vbe_on: f32 = 0.7, // Base-emitter turn-on voltage
    vce_sat: f32 = 0.2, // Saturation voltage
    early_voltage: f32 = 100.0, // Early voltage for VCBO

    pub const Type = enum {
        npn,
        pnp,
    };

    pub fn init(typ: Type, beta: f32) Transistor {
        return Transistor{
            .typ = typ,
            .beta = beta,
        };
    }

    /// Collector current in active region
    /// Ic = beta * Ib
    pub fn collectorCurrent(self: Transistor, base_current: f32) f32 {
        return self.beta * base_current;
    }

    /// Check if transistor is in saturation
    /// Returns true if Vce is below saturation voltage
    pub fn isSaturated(self: Transistor, vce: f32) bool {
        return @abs(vce) < self.vce_sat;
    }

    /// Simple common-emitter amplifier model
    /// input: base voltage (relative to emitter)
    /// load_resistance: collector load
    /// supply: supply voltage
    /// returns: collector voltage
    pub fn commonEmitterAmp(self: Transistor, input: f32, load_resistance: f32, supply: f32) f32 {
        // Check if transistor is on
        if (input < self.vbe_on) {
            // Off: Vce ≈ supply (collector floats high)
            return supply;
        }

        // Active region: linear amplification
        const base_current = (input - self.vbe_on) / 10000.0; // Assume 10k input resistance
        const collector_current = self.collectorCurrent(base_current);
        const vce = supply - (collector_current * load_resistance);

        if (vce < self.vce_sat) {
            // Saturated: Vce = sat voltage
            return self.vce_sat;
        }
        return vce;
    }

    /// Distortion characteristic
    /// Transistor amplifies small signals but clips large ones
    pub fn distort(self: Transistor, input: f32) f32 {
        const amplified = input * (self.beta / 100.0);
        // Soft clipping
        if (amplified > 1.0) {
            return 1.0 + @tanh(amplified - 1.0) * 0.5;
        } else if (amplified < -1.0) {
            return -1.0 - @tanh(-amplified - 1.0) * 0.5;
        }
        return amplified;
    }
};

#[cfg(test)]
const testing = std.testing;

test "resistor voltage divider" {
    var r1 = Resistor.init(10000); // 10k
    var r2 = Resistor.init(10000); // 10k
    
    const input = 1.0;
    const output = r1.processSignal(input, 10000);
    
    // With 10k and 10k: output = 1.0 * (10k / (10k + 10k)) = 0.5
    try testing.expectApproxEqAbs(0.5, output, 0.01);
}

test "capacitor high-pass filter" {
    var cap = Capacitor.init(1e-6); // 1 µF
    const load_r = 10000.0; // 10k
    const dt = 1.0 / 44100.0; // 44.1kHz sample rate
    
    const cutoff = cap.cutoffFrequency(load_r);
    // f_c = 1 / (2 * pi * 10k * 1µ) ≈ 15.9 Hz
    try testing.expect(cutoff > 10 and cutoff < 20);
}

test "diode clipping" {
    var diode = Diode.init();
    
    const clipped_high = diode.clipSignal(2.0);
    try testing.expectApproxEqAbs(0.7, clipped_high, 0.01);
    
    const clipped_low = diode.clipSignal(-2.0);
    try testing.expectApproxEqAbs(-0.7, clipped_low, 0.01);
    
    const pass = diode.clipSignal(0.5);
    try testing.expectApproxEqAbs(0.5, pass, 0.01);
}
