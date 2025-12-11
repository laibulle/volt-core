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
