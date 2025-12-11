const std = @import("std");

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
            const normalized = (input - threshold) / threshold;
            const clamped = std.math.min(normalized, 1.0);
            return threshold + clamped * threshold;
        } else if (input < -threshold) {
            const normalized = (-input - threshold) / threshold;
            const clamped = std.math.min(normalized, 1.0);
            return -threshold - clamped * threshold;
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
