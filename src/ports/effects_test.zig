const std = @import("std");
const testing = std.testing;
const ports = @import("effects.zig");

test "Parameter: name and value" {
    const param = ports.Parameter{
        .name = "test_param",
        .value = 42.0,
    };
    try testing.expectEqualSlices(u8, param.name, "test_param");
    try testing.expectEqual(param.value, 42.0);
}

test "ParameterType: enum values" {
    const float_type = ports.ParameterType.float;
    const int_type = ports.ParameterType.integer;
    const bool_type = ports.ParameterType.boolean;
    const enum_type = ports.ParameterType.enum_type;

    try testing.expectEqual(float_type, ports.ParameterType.float);
    try testing.expectEqual(int_type, ports.ParameterType.integer);
    try testing.expectEqual(bool_type, ports.ParameterType.boolean);
    try testing.expectEqual(enum_type, ports.ParameterType.enum_type);
}

test "ParameterDescriptor: isValid within range" {
    const descriptor = ports.ParameterDescriptor{
        .name = "test",
        .param_type = ports.ParameterType.float,
        .default_value = 0.5,
        .min_value = 0.0,
        .max_value = 1.0,
    };

    try testing.expect(descriptor.isValid(0.0));
    try testing.expect(descriptor.isValid(0.5));
    try testing.expect(descriptor.isValid(1.0));
    try testing.expect(!descriptor.isValid(-0.1));
    try testing.expect(!descriptor.isValid(1.1));
}

test "ParameterDescriptor: clamp min value" {
    const descriptor = ports.ParameterDescriptor{
        .name = "test",
        .param_type = ports.ParameterType.float,
        .default_value = 0.5,
        .min_value = 0.0,
        .max_value = 1.0,
    };

    try testing.expectEqual(descriptor.clamp(-5.0), 0.0);
}

test "ParameterDescriptor: clamp max value" {
    const descriptor = ports.ParameterDescriptor{
        .name = "test",
        .param_type = ports.ParameterType.float,
        .default_value = 0.5,
        .min_value = 0.0,
        .max_value = 1.0,
    };

    try testing.expectEqual(descriptor.clamp(5.0), 1.0);
}

test "ParameterDescriptor: clamp within range" {
    const descriptor = ports.ParameterDescriptor{
        .name = "test",
        .param_type = ports.ParameterType.float,
        .default_value = 0.5,
        .min_value = 0.0,
        .max_value = 1.0,
    };

    try testing.expectEqual(descriptor.clamp(0.5), 0.5);
    try testing.expectEqual(descriptor.clamp(0.0), 0.0);
    try testing.expectEqual(descriptor.clamp(1.0), 1.0);
}

test "ParameterDescriptor: with default description" {
    const descriptor = ports.ParameterDescriptor{
        .name = "test",
        .param_type = ports.ParameterType.float,
        .default_value = 0.5,
    };

    try testing.expectEqualSlices(u8, descriptor.description, "");
}

test "ParameterDescriptor: with custom description" {
    const descriptor = ports.ParameterDescriptor{
        .name = "test",
        .param_type = ports.ParameterType.float,
        .default_value = 0.5,
        .description = "A test parameter",
    };

    try testing.expectEqualSlices(u8, descriptor.description, "A test parameter");
}

test "EffectDescriptor: basic structure" {
    const params = &[_]ports.ParameterDescriptor{
        .{
            .name = "param1",
            .param_type = ports.ParameterType.float,
            .default_value = 0.5,
        },
    };

    const descriptor = ports.EffectDescriptor{
        .id = "test_effect",
        .name = "Test Effect",
        .available_parameters = params,
    };

    try testing.expectEqualSlices(u8, descriptor.id, "test_effect");
    try testing.expectEqualSlices(u8, descriptor.name, "Test Effect");
    try testing.expectEqual(descriptor.available_parameters.len, 1);
}

test "EffectDescriptor: with description and version" {
    const params = &[_]ports.ParameterDescriptor{};

    const descriptor = ports.EffectDescriptor{
        .id = "test_effect",
        .name = "Test Effect",
        .description = "A test effect",
        .version = "2.0.0",
        .available_parameters = params,
    };

    try testing.expectEqualSlices(u8, descriptor.description, "A test effect");
    try testing.expectEqualSlices(u8, descriptor.version, "2.0.0");
}

test "EffectDescriptor: default version" {
    const params = &[_]ports.ParameterDescriptor{};

    const descriptor = ports.EffectDescriptor{
        .id = "test_effect",
        .name = "Test Effect",
        .available_parameters = params,
    };

    try testing.expectEqualSlices(u8, descriptor.version, "1.0.0");
}

test "EffectDescriptor: multiple parameters" {
    const params = &[_]ports.ParameterDescriptor{
        .{
            .name = "drive",
            .param_type = ports.ParameterType.float,
            .default_value = 1.0,
            .min_value = 0.1,
            .max_value = 10.0,
        },
        .{
            .name = "tone",
            .param_type = ports.ParameterType.float,
            .default_value = 0.5,
            .min_value = 0.0,
            .max_value = 1.0,
        },
        .{
            .name = "enabled",
            .param_type = ports.ParameterType.boolean,
            .default_value = 1.0,
        },
    };

    const descriptor = ports.EffectDescriptor{
        .id = "complex_effect",
        .name = "Complex Effect",
        .available_parameters = params,
    };

    try testing.expectEqual(descriptor.available_parameters.len, 3);
    try testing.expectEqualSlices(u8, descriptor.available_parameters[0].name, "drive");
    try testing.expectEqualSlices(u8, descriptor.available_parameters[1].name, "tone");
    try testing.expectEqualSlices(u8, descriptor.available_parameters[2].name, "enabled");
}
