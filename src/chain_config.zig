const std = @import("std");
const effect_chain_mod = @import("core/effect_chain.zig");
const distortion_mod = @import("effects/distortions/distortion.zig");
const convolver_mod = @import("effects/convolver/convolver.zig");
const ports = @import("ports/effects.zig");

const EffectChain = effect_chain_mod.EffectChain;
const Distortion = distortion_mod.Distortion;
const ConvolverEffect = convolver_mod.Convolver;

/// Deinit callback for Distortion effect
fn distortion_deinit(allocator: std.mem.Allocator, instance: *anyopaque) void {
    const dist = @as(*Distortion, @ptrCast(@alignCast(instance)));
    allocator.destroy(dist);
}

/// Deinit callback for Convolver effect
fn convolver_deinit(allocator: std.mem.Allocator, instance: *anyopaque) void {
    var conv = @as(*ConvolverEffect, @ptrCast(@alignCast(instance)));
    conv.deinit();
    allocator.destroy(conv);
}

/// Configuration for an effect loaded from JSON
pub const EffectConfig = struct {
    id: []const u8,
    effect_type: []const u8,
    parameters: std.StringHashMap(f32),

    pub fn deinit(self: *EffectConfig) void {
        self.parameters.deinit();
    }
};

/// Configuration for the entire effect chain
pub const ChainConfig = struct {
    effects: []EffectConfig,

    pub fn deinit(self: *ChainConfig, allocator: std.mem.Allocator) void {
        for (self.effects) |*effect| {
            effect.deinit();
        }
        allocator.free(self.effects);
    }
};

/// Parse JSON effect chain configuration
pub fn parseChainConfig(allocator: std.mem.Allocator, json_str: []const u8) !ChainConfig {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value;

    if (root != .object) {
        return error.InvalidJsonFormat;
    }

    const effects_array = root.object.get("effects") orelse return error.MissingEffectsArray;

    if (effects_array != .array) {
        return error.InvalidEffectsArray;
    }

    var effects = try allocator.alloc(EffectConfig, effects_array.array.items.len);

    for (effects_array.array.items, 0..) |effect_value, i| {
        if (effect_value != .object) {
            return error.InvalidEffectObject;
        }

        const effect_obj = effect_value.object;

        const id = effect_obj.get("id") orelse return error.MissingEffectId;
        if (id != .string) {
            return error.InvalidEffectId;
        }

        const effect_type = effect_obj.get("type") orelse return error.MissingEffectType;
        if (effect_type != .string) {
            return error.InvalidEffectType;
        }

        var parameters = std.StringHashMap(f32).init(allocator);

        if (effect_obj.get("parameters")) |params_value| {
            if (params_value == .object) {
                var params_iter = params_value.object.iterator();
                while (params_iter.next()) |entry| {
                    if (entry.value_ptr.* == .float) {
                        try parameters.put(entry.key_ptr.*, @floatCast(entry.value_ptr.*.float));
                    } else if (entry.value_ptr.* == .integer) {
                        try parameters.put(entry.key_ptr.*, @floatFromInt(entry.value_ptr.*.integer));
                    }
                }
            }
        }

        effects[i] = .{
            .id = try allocator.dupe(u8, id.string),
            .effect_type = try allocator.dupe(u8, effect_type.string),
            .parameters = parameters,
        };
    }

    return .{
        .effects = effects,
    };
}

/// Initialize effect chain from JSON configuration
pub fn initChainFromJson(
    allocator: std.mem.Allocator,
    json_str: []const u8,
) !EffectChain {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) {
        return error.InvalidJsonFormat;
    }

    const effects_array = root.object.get("effects") orelse return error.MissingEffectsArray;
    if (effects_array != .array) {
        return error.InvalidEffectsArray;
    }

    var chain = EffectChain.init(allocator);

    for (effects_array.array.items) |effect_value| {
        if (effect_value != .object) {
            return error.InvalidEffectObject;
        }

        const effect_obj = effect_value.object;

        const id = effect_obj.get("id") orelse return error.MissingEffectId;
        if (id != .string) {
            return error.InvalidEffectId;
        }

        const effect_type = effect_obj.get("type") orelse return error.MissingEffectType;
        if (effect_type != .string) {
            return error.InvalidEffectType;
        }

        // Copy strings to ensure they live longer than the JSON object
        const effect_id = try allocator.dupe(u8, id.string);
        const type_str = try allocator.dupe(u8, effect_type.string);

        if (std.mem.eql(u8, type_str, "distortion")) {
            // Create distortion effect (heap-allocated)
            var dist = try allocator.create(Distortion);
            dist.* = Distortion.init();

            // Apply parameters from JSON
            if (effect_obj.get("parameters")) |params_value| {
                if (params_value == .object) {
                    var params_iter = params_value.object.iterator();
                    while (params_iter.next()) |entry| {
                        if (entry.value_ptr.* == .float) {
                            _ = dist.setParameter(entry.key_ptr.*, @floatCast(entry.value_ptr.*.float));
                        } else if (entry.value_ptr.* == .integer) {
                            _ = dist.setParameter(entry.key_ptr.*, @floatFromInt(entry.value_ptr.*.integer));
                        }
                    }
                }
            }

            try chain.addEffect_with_deinit(
                effect_id,
                &distortion_mod.distortion_descriptor,
                @ptrCast(dist),
                @ptrCast(&Distortion.processBuffer),
                distortion_deinit,
            );
        } else if (std.mem.eql(u8, type_str, "convolver")) {
            // Create convolver effect (heap-allocated)
            // First, try to get the IR path from parameters
            var ir_path: ?[]const u8 = null;
            if (effect_obj.get("parameters")) |params_value| {
                if (params_value == .object) {
                    if (params_value.object.get("ir_path")) |ir_path_value| {
                        if (ir_path_value == .string) {
                            ir_path = try allocator.dupe(u8, ir_path_value.string);
                        }
                    }
                }
            }

            if (ir_path == null) {
                std.debug.print("Error: Convolver effect '{s}' missing required parameter 'ir_path'\n", .{effect_id});
                allocator.free(effect_id);
                allocator.free(type_str);
                return error.MissingIRPath;
            }

            var conv = try allocator.create(ConvolverEffect);
            conv.* = try ConvolverEffect.initFromFile(allocator, ir_path.?);
            allocator.free(ir_path.?);

            // Apply other parameters from JSON (like dry_wet)
            if (effect_obj.get("parameters")) |params_value| {
                if (params_value == .object) {
                    var params_iter = params_value.object.iterator();
                    while (params_iter.next()) |entry| {
                        if (!std.mem.eql(u8, entry.key_ptr.*, "ir_path")) {
                            if (entry.value_ptr.* == .float) {
                                _ = conv.setParameter(entry.key_ptr.*, @floatCast(entry.value_ptr.*.float));
                            } else if (entry.value_ptr.* == .integer) {
                                _ = conv.setParameter(entry.key_ptr.*, @floatFromInt(entry.value_ptr.*.integer));
                            }
                        }
                    }
                }
            }

            try chain.addEffect_with_deinit(
                effect_id,
                &convolver_mod.convolver_descriptor,
                @ptrCast(conv),
                @ptrCast(&ConvolverEffect.processBuffer),
                convolver_deinit,
            );
        } else {
            std.debug.print("Warning: Unknown effect type '{s}'\n", .{type_str});
            allocator.free(effect_id);
        }

        allocator.free(type_str);
    }

    return chain;
}

/// Print effect chain configuration
pub fn printChainConfig(chain: *const EffectChain) !void {
    std.debug.print("\n╔════════════════════════════════════════╗\n", .{});
    std.debug.print("║         Effect Chain Configuration      ║\n", .{});
    std.debug.print("╚════════════════════════════════════════╝\n\n", .{});

    std.debug.print("Total Effects: {d}\n\n", .{chain.effectCount()});

    for (0..chain.effectCount()) |i| {
        if (chain.slots[i]) |slot| {
            std.debug.print("[{d}] {s} (ID: {s})\n", .{ i + 1, slot.descriptor.name, slot.effect_id });
            std.debug.print("    Status: {s}\n", .{if (slot.enabled) "Enabled" else "Disabled"});
            std.debug.print("    Parameters:\n", .{});

            for (slot.descriptor.available_parameters) |param| {
                const value = slot.parameters.get(param.name) orelse param.default_value;
                std.debug.print("      - {s}: {d:.4} (range: {d:.2}-{d:.2})\n", .{
                    param.name,
                    value,
                    param.min_value,
                    param.max_value,
                });
            }
            std.debug.print("\n", .{});
        }
    }
}
