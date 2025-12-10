const std = @import("std");
const testing = std.testing;
const effect_chain_mod = @import("effect_chain.zig");
const distortion_mod = @import("../effects/distortions/distortion.zig");
const ports = @import("../ports/effects.zig");

const EffectChain = effect_chain_mod.EffectChain;
const EffectSlot = effect_chain_mod.EffectSlot;
const Distortion = distortion_mod.Distortion;

test "EffectSlot: init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dist = Distortion.init();
    var slot = try EffectSlot.init(
        allocator,
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );
    defer slot.deinit();

    try testing.expectEqualSlices(u8, slot.effect_id, "distortion");
    try testing.expectEqual(slot.enabled, true);
}

test "EffectSlot: set and get parameters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dist = Distortion.init();
    var slot = try EffectSlot.init(
        allocator,
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );
    defer slot.deinit();

    // Set parameters
    try testing.expect(try slot.setParameter("drive", 2.5));
    try testing.expect(try slot.setParameter("tone", 0.7));

    // Get parameters
    try testing.expectEqual(slot.getParameter("drive"), 2.5);
    try testing.expectEqual(slot.getParameter("tone"), 0.7);
}

test "EffectSlot: parameter clamping" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dist = Distortion.init();
    var slot = try EffectSlot.init(
        allocator,
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );
    defer slot.deinit();

    // Set out-of-range values
    _ = try slot.setParameter("drive", 50.0); // max is 10.0
    _ = try slot.setParameter("tone", -5.0); // min is 0.0

    // Values should be clamped
    try testing.expectEqual(slot.getParameter("drive"), 10.0);
    try testing.expectEqual(slot.getParameter("tone"), 0.0);
}

test "EffectSlot: invalid parameter name" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dist = Distortion.init();
    var slot = try EffectSlot.init(
        allocator,
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );
    defer slot.deinit();

    try testing.expect(!(try slot.setParameter("invalid", 0.5)));
    try testing.expectEqual(slot.getParameter("invalid"), null);
}

test "EffectSlot: enable/disable" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dist = Distortion.init();
    var slot = try EffectSlot.init(
        allocator,
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );
    defer slot.deinit();

    try testing.expectEqual(slot.isEnabled(), true);
    slot.setEnabled(false);
    try testing.expectEqual(slot.isEnabled(), false);
    slot.setEnabled(true);
    try testing.expectEqual(slot.isEnabled(), true);
}

test "EffectSlot: disabled effect passes through input" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var dist = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 5.0 },
        .{ .name = "tone", .value = 0.5 },
    });
    var slot = try EffectSlot.init(
        allocator,
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );
    defer slot.deinit();

    const input: f32 = 0.5;

    // Disabled: should pass through
    slot.setEnabled(false);
    try testing.expectEqual(slot.process(input), input);

    // Enabled: should process
    slot.setEnabled(true);
    const output = slot.process(input);
    try testing.expect(output != input); // Should be different (distorted)
}

test "EffectChain: init and deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    try testing.expectEqual(chain.effectCount(), 0);
}

test "EffectChain: add effect" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.init();
    try chain.addEffect(
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    try testing.expectEqual(chain.effectCount(), 1);
}

test "EffectChain: add multiple effects" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist1 = Distortion.init();
    var dist2 = Distortion.init();

    try chain.addEffect(
        "distortion_1",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist1),
        @ptrCast(&Distortion.process),
    );
    try chain.addEffect(
        "distortion_2",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist2),
        @ptrCast(&Distortion.process),
    );

    try testing.expectEqual(chain.effectCount(), 2);
}

test "EffectChain: get effect by index" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.init();
    try chain.addEffect(
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    if (chain.getEffect(0)) |slot| {
        try testing.expectEqualSlices(u8, slot.effect_id, "distortion");
    } else {
        try testing.expect(false);
    }

    try testing.expectEqual(chain.getEffect(1), null);
}

test "EffectChain: get effect by ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.init();
    try chain.addEffect(
        "my_distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    if (chain.getEffectById("my_distortion")) |slot| {
        try testing.expectEqualSlices(u8, slot.effect_id, "my_distortion");
    } else {
        try testing.expect(false);
    }

    try testing.expectEqual(chain.getEffectById("nonexistent"), null);
}

test "EffectChain: set and get effect parameters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.init();
    try chain.addEffect(
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    try testing.expect(try chain.setEffectParameter(0, "drive", 3.5));
    try testing.expectEqual(chain.getEffectParameter(0, "drive"), 3.5);
}

test "EffectChain: set and get effect parameters by ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.init();
    try chain.addEffect(
        "dist_main",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    try testing.expect(try chain.setEffectParameterById("dist_main", "tone", 0.8));
    try testing.expectEqual(chain.getEffectParameter(0, "tone"), 0.8);
}

test "EffectChain: remove effect" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.init();
    try chain.addEffect(
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    try testing.expectEqual(chain.effectCount(), 1);
    try testing.expect(chain.removeEffect(0));
    try testing.expectEqual(chain.effectCount(), 0);
    try testing.expect(!chain.removeEffect(0));
}

test "EffectChain: enable/disable effect" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.init();
    try chain.addEffect(
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    try testing.expect(chain.setEffectEnabled(0, false));
    if (chain.getEffect(0)) |slot| {
        try testing.expectEqual(slot.isEnabled(), false);
    }

    try testing.expect(chain.setEffectEnabled(0, true));
    if (chain.getEffect(0)) |slot| {
        try testing.expectEqual(slot.isEnabled(), true);
    }
}

test "EffectChain: enable/disable effect by ID" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.init();
    try chain.addEffect(
        "main_distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    try testing.expect(chain.setEffectEnabledById("main_distortion", false));
    if (chain.getEffectById("main_distortion")) |slot| {
        try testing.expectEqual(slot.isEnabled(), false);
    }
}

test "EffectChain: process audio through single effect" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 2.0 },
        .{ .name = "tone", .value = 1.0 },
    });
    try chain.addEffect(
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    const input: f32 = 0.5;
    const output = chain.process(input);
    try testing.expect(output != input); // Should be distorted
}

test "EffectChain: process audio through multiple effects" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist1 = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 1.5 },
        .{ .name = "tone", .value = 0.5 },
    });
    var dist2 = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 1.0 },
        .{ .name = "tone", .value = 0.8 },
    });

    try chain.addEffect(
        "distortion_1",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist1),
        @ptrCast(&Distortion.process),
    );
    try chain.addEffect(
        "distortion_2",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist2),
        @ptrCast(&Distortion.process),
    );

    const input: f32 = 0.3;
    const output = chain.process(input);
    try testing.expect(output != input);
}

test "EffectChain: disabled effect in chain passes through" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = EffectChain.init(allocator);
    defer chain.deinit();

    var dist = Distortion.initWithParams(&[_]ports.Parameter{
        .{ .name = "drive", .value = 5.0 },
        .{ .name = "tone", .value = 0.5 },
    });
    try chain.addEffect(
        "distortion",
        &distortion_mod.distortion_descriptor,
        @ptrCast(&dist),
        @ptrCast(&Distortion.process),
    );

    const input: f32 = 0.5;

    // Enabled
    var output = chain.process(input);
    try testing.expect(output != input);

    // Disable and test
    _ = chain.setEffectEnabled(0, false);
    output = chain.process(input);
    try testing.expectEqual(output, input);
}
