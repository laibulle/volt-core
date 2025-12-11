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
