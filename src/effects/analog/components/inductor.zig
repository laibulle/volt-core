const std = @import("std");

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
