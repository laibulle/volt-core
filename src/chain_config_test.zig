const std = @import("std");
const testing = std.testing;
const chain_config = @import("chain_config.zig");

test "chain_config: parse valid JSON configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "effects": [
        \\    {
        \\      "id": "distortion_1",
        \\      "type": "distortion",
        \\      "parameters": {
        \\        "drive": 2.5,
        \\        "tone": 0.7
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    var config = try chain_config.parseChainConfig(allocator, json);
    defer config.deinit(allocator);

    try testing.expectEqual(config.effects.len, 1);
    try testing.expectEqualSlices(u8, config.effects[0].id, "distortion_1");
    try testing.expectEqualSlices(u8, config.effects[0].effect_type, "distortion");
    try testing.expectEqual(config.effects[0].parameters.get("drive"), 2.5);
    try testing.expectEqual(config.effects[0].parameters.get("tone"), 0.7);
}

test "chain_config: parse multiple effects" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "effects": [
        \\    {
        \\      "id": "dist_1",
        \\      "type": "distortion",
        \\      "parameters": {"drive": 1.5}
        \\    },
        \\    {
        \\      "id": "dist_2",
        \\      "type": "distortion",
        \\      "parameters": {"drive": 3.0, "tone": 0.5}
        \\    }
        \\  ]
        \\}
    ;

    var config = try chain_config.parseChainConfig(allocator, json);
    defer config.deinit(allocator);

    try testing.expectEqual(config.effects.len, 2);
    try testing.expectEqualSlices(u8, config.effects[0].id, "dist_1");
    try testing.expectEqualSlices(u8, config.effects[1].id, "dist_2");
}

test "chain_config: parse empty parameters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "effects": [
        \\    {
        \\      "id": "distortion_1",
        \\      "type": "distortion"
        \\    }
        \\  ]
        \\}
    ;

    var config = try chain_config.parseChainConfig(allocator, json);
    defer config.deinit(allocator);

    try testing.expectEqual(config.effects.len, 1);
    try testing.expectEqual(config.effects[0].parameters.count(), 0);
}

test "chain_config: missing effects array" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = "{}";

    try testing.expectError(error.MissingEffectsArray, chain_config.parseChainConfig(allocator, json));
}

test "chain_config: missing effect id" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "effects": [
        \\    {
        \\      "type": "distortion"
        \\    }
        \\  ]
        \\}
    ;

    try testing.expectError(error.MissingEffectId, chain_config.parseChainConfig(allocator, json));
}

test "chain_config: missing effect type" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "effects": [
        \\    {
        \\      "id": "effect_1"
        \\    }
        \\  ]
        \\}
    ;

    try testing.expectError(error.MissingEffectType, chain_config.parseChainConfig(allocator, json));
}

test "chain_config: integer parameter conversion" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json =
        \\{
        \\  "effects": [
        \\    {
        \\      "id": "distortion_1",
        \\      "type": "distortion",
        \\      "parameters": {
        \\        "drive": 2
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    var config = try chain_config.parseChainConfig(allocator, json);
    defer config.deinit(allocator);

    try testing.expectEqual(config.effects[0].parameters.get("drive"), 2.0);
}
