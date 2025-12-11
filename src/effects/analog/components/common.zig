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

    fn getUnitChar(_: ComponentValue) u8 {
        return ' ';
    }
};
