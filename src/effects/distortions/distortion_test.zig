const std = @import("std");
const testing = std.testing;
const distortion_mod = @import("distortion.zig");
const ports = @import("../../ports/effects.zig");

const Distortion = distortion_mod.Distortion;
const distortion_descriptor = distortion_mod.distortion_descriptor;

test "distortion: init with defaults" {
    const dist = Distortion.init();
    try testing.expectEqual(dist.drive, 1.0);
    try testing.expectEqual(dist.tone, 0.5);
}

test "distortion: initWithParams applies parameters" {
    const params = &[_]ports.Parameter{
        .{ .name = "drive", .value = 2.5 },
        .{ .name = "tone", .value = 0.7 },
    };
    const dist = Distortion.initWithParams(params);
    try testing.expectEqual(dist.drive, 2.5);
    try testing.expectEqual(dist.tone, 0.7);
}

test "distortion: initWithParams clamps out-of-range values" {
    const params = &[_]ports.Parameter{
        .{ .name = "drive", .value = 50.0 }, // max is 10.0
        .{ .name = "tone", .value = -5.0 }, // min is 0.0
    };
    const dist = Distortion.initWithParams(params);
    try testing.expectEqual(dist.drive, 10.0);
    try testing.expectEqual(dist.tone, 0.0);
}

test "distortion: setParameter updates values" {
    var dist = Distortion.init();
    try testing.expect(dist.setParameter("drive", 3.5));
    try testing.expectEqual(dist.drive, 3.5);
    try testing.expect(dist.setParameter("tone", 0.8));
    try testing.expectEqual(dist.tone, 0.8);
}

test "distortion: setParameter clamps values" {
    var dist = Distortion.init();
    _ = dist.setParameter("drive", 20.0); // exceeds max
    try testing.expectEqual(dist.drive, 10.0); // clamped to max
    _ = dist.setParameter("tone", -1.0); // below min
    try testing.expectEqual(dist.tone, 0.0); // clamped to min
}

test "distortion: setParameter returns false for invalid names" {
    var dist = Distortion.init();
    try testing.expect(!dist.setParameter("invalid_param", 0.5));
}

test "distortion: getParameter retrieves values" {
    var dist = Distortion.init();
    dist.drive = 2.0;
    dist.tone = 0.3;
    try testing.expectEqual(dist.getParameter("drive"), 2.0);
    try testing.expectEqual(dist.getParameter("tone"), 0.3);
}

test "distortion: getParameter returns null for invalid names" {
    const dist = Distortion.init();
    try testing.expectEqual(dist.getParameter("invalid_param"), null);
}

test "distortion: process without distortion (drive=1, tone=1)" {
    const dist = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 1.0 },
        .{ .name = "tone", .value = 1.0 },
    });
    const input: f32 = 0.5;
    const output = dist.process(input);
    // With drive=1.0: sample = 0.5
    // With tanh: tanh(0.5) ≈ 0.4621
    // With tone=1.0: 0.4621 * 1.0 ≈ 0.4621
    const expected = std.math.tanh(0.5);
    try testing.expectApproxEqAbs(output, expected, 0.001);
}

test "distortion: process with increased drive" {
    const dist = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 2.0 },
        .{ .name = "tone", .value = 1.0 },
    });
    const input: f32 = 0.5;
    const output = dist.process(input);
    // With drive=2.0: sample = 0.5 * 2.0 = 1.0
    // With tanh: tanh(1.0) ≈ 0.7616
    // With tone=1.0: 0.7616 * 1.0 ≈ 0.7616
    const expected = std.math.tanh(1.0);
    try testing.expectApproxEqAbs(output, expected, 0.001);
}

test "distortion: process with tone reduction" {
    const dist = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 1.0 },
        .{ .name = "tone", .value = 0.5 },
    });
    const input: f32 = 0.5;
    const output = dist.process(input);
    // With drive=1.0: sample = 0.5
    // With tanh: tanh(0.5) ≈ 0.4621
    // With tone=0.5: 0.4621 * 0.5 ≈ 0.2311
    const expected = std.math.tanh(0.5) * 0.5;
    try testing.expectApproxEqAbs(output, expected, 0.001);
}

test "distortion: process clips extreme values" {
    const dist = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 10.0 }, // maximum drive
        .{ .name = "tone", .value = 1.0 },
    });
    const input: f32 = 0.5;
    const output = dist.process(input);
    // With drive=10.0: sample = 0.5 * 10.0 = 5.0
    // tanh(5.0) approaches 1.0 (soft clipping)
    try testing.expect(output > 0.99 and output <= 1.0);
}

test "distortion: descriptor has correct metadata" {
    try testing.expectEqualSlices(u8, distortion_descriptor.id, "distortion");
    try testing.expectEqualSlices(u8, distortion_descriptor.name, "Distortion");
    try testing.expect(distortion_descriptor.available_parameters.len == 2);
}

test "distortion: descriptor drive parameter" {
    const drive_param = distortion_descriptor.available_parameters[0];
    try testing.expectEqualSlices(u8, drive_param.name, "drive");
    try testing.expectEqual(drive_param.param_type, ports.ParameterType.float);
    try testing.expectEqual(drive_param.default_value, 1.0);
    try testing.expectEqual(drive_param.min_value, 0.1);
    try testing.expectEqual(drive_param.max_value, 10.0);
}

test "distortion: descriptor tone parameter" {
    const tone_param = distortion_descriptor.available_parameters[1];
    try testing.expectEqualSlices(u8, tone_param.name, "tone");
    try testing.expectEqual(tone_param.param_type, ports.ParameterType.float);
    try testing.expectEqual(tone_param.default_value, 0.5);
    try testing.expectEqual(tone_param.min_value, 0.0);
    try testing.expectEqual(tone_param.max_value, 1.0);
}
