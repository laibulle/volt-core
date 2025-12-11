const std = @import("std");

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
