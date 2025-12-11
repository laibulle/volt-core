/// ============================================================================
/// TRANSISTORS - Generic + Variants
/// ============================================================================
pub const TransistorParams = struct {
    pub const Type = enum { npn, pnp };
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
