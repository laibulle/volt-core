const std = @import("std");
const ports = @import("../ports/effects.zig");

/// Effect slot that holds an effect instance with its metadata and parameters
pub const EffectSlot = struct {
    /// Effect type identifier
    effect_id: []const u8,

    /// Effect descriptor (metadata)
    descriptor: *const ports.EffectDescriptor,

    /// Effect instance data (opaque pointer)
    instance: *anyopaque,

    /// Process function for this effect
    process_fn: *const fn (self: *anyopaque, input: f32) f32,

    /// Current parameter values indexed by parameter name
    parameters: std.StringHashMap(f32),

    /// Enable/disable flag
    enabled: bool = true,

    /// Initialize an effect slot
    pub fn init(
        allocator: std.mem.Allocator,
        effect_id: []const u8,
        descriptor: *const ports.EffectDescriptor,
        instance: *anyopaque,
        process_fn: *const fn (self: *anyopaque, input: f32) f32,
    ) !EffectSlot {
        var slot = EffectSlot{
            .effect_id = effect_id,
            .descriptor = descriptor,
            .instance = instance,
            .process_fn = process_fn,
            .parameters = std.StringHashMap(f32).init(allocator),
        };

        // Initialize with default parameter values
        for (descriptor.available_parameters) |param| {
            try slot.parameters.put(param.name, param.default_value);
        }

        return slot;
    }

    /// Deinitialize the effect slot
    pub fn deinit(self: *EffectSlot) void {
        self.parameters.deinit();
    }

    /// Set a parameter value
    pub fn setParameter(self: *EffectSlot, name: []const u8, value: f32) !bool {
        // Find the parameter descriptor
        for (self.descriptor.available_parameters) |param| {
            if (std.mem.eql(u8, param.name, name)) {
                // Clamp value to valid range
                const clamped = param.clamp(value);
                try self.parameters.put(name, clamped);
                return true;
            }
        }
        return false;
    }

    /// Get a parameter value
    pub fn getParameter(self: *const EffectSlot, name: []const u8) ?f32 {
        return self.parameters.get(name);
    }

    /// Get all parameters as an array of Parameter structs
    pub fn getParametersArray(self: *const EffectSlot, allocator: std.mem.Allocator) ![]ports.Parameter {
        var params = try allocator.alloc(ports.Parameter, self.descriptor.available_parameters.len);
        var i: usize = 0;
        for (self.descriptor.available_parameters) |param| {
            params[i] = .{
                .name = param.name,
                .value = self.parameters.get(param.name) orelse param.default_value,
            };
            i += 1;
        }
        return params;
    }

    /// Process audio through this effect
    pub fn process(self: *const EffectSlot, input: f32) f32 {
        if (!self.enabled) return input;
        return self.process_fn(self.instance, input);
    }

    /// Enable/disable the effect
    pub fn setEnabled(self: *EffectSlot, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Check if effect is enabled
    pub fn isEnabled(self: *const EffectSlot) bool {
        return self.enabled;
    }
};

/// Effect chain that manages multiple effects in sequence
pub const EffectChain = struct {
    /// List of effect slots
    slots: std.ArrayList(EffectSlot),

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    /// Initialize effect chain
    pub fn init(allocator: std.mem.Allocator) EffectChain {
        return EffectChain{
            .slots = std.ArrayList(EffectSlot).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize effect chain and all effects
    pub fn deinit(self: *EffectChain) void {
        for (self.slots.items) |*slot| {
            slot.deinit();
        }
        self.slots.deinit();
    }

    /// Add an effect to the chain
    pub fn addEffect(
        self: *EffectChain,
        effect_id: []const u8,
        descriptor: *const ports.EffectDescriptor,
        instance: *anyopaque,
        process_fn: *const fn (self: *anyopaque, input: f32) f32,
    ) !void {
        const slot = try EffectSlot.init(
            self.allocator,
            effect_id,
            descriptor,
            instance,
            process_fn,
        );
        try self.slots.append(slot);
    }

    /// Remove an effect at specific index
    pub fn removeEffect(self: *EffectChain, index: usize) bool {
        if (index >= self.slots.items.len) return false;
        var slot = self.slots.orderedRemove(index);
        slot.deinit();
        return true;
    }

    /// Get number of effects in chain
    pub fn effectCount(self: *const EffectChain) usize {
        return self.slots.items.len;
    }

    /// Get effect at index
    pub fn getEffect(self: *EffectChain, index: usize) ?*EffectSlot {
        if (index >= self.slots.items.len) return null;
        return &self.slots.items[index];
    }

    /// Get effect by ID
    pub fn getEffectById(self: *EffectChain, effect_id: []const u8) ?*EffectSlot {
        for (self.slots.items) |*slot| {
            if (std.mem.eql(u8, slot.effect_id, effect_id)) {
                return slot;
            }
        }
        return null;
    }

    /// Set parameter on specific effect
    pub fn setEffectParameter(
        self: *EffectChain,
        effect_index: usize,
        param_name: []const u8,
        value: f32,
    ) !bool {
        if (effect_index >= self.slots.items.len) return false;
        return try self.slots.items[effect_index].setParameter(param_name, value);
    }

    /// Get parameter from specific effect
    pub fn getEffectParameter(
        self: *const EffectChain,
        effect_index: usize,
        param_name: []const u8,
    ) ?f32 {
        if (effect_index >= self.slots.items.len) return null;
        return self.slots.items[effect_index].getParameter(param_name);
    }

    /// Set parameter on effect by ID
    pub fn setEffectParameterById(
        self: *EffectChain,
        effect_id: []const u8,
        param_name: []const u8,
        value: f32,
    ) !bool {
        if (self.getEffectById(effect_id)) |slot| {
            return try slot.setParameter(param_name, value);
        }
        return false;
    }

    /// Enable/disable effect at index
    pub fn setEffectEnabled(self: *EffectChain, index: usize, enabled: bool) bool {
        if (index >= self.slots.items.len) return false;
        self.slots.items[index].setEnabled(enabled);
        return true;
    }

    /// Enable/disable effect by ID
    pub fn setEffectEnabledById(self: *EffectChain, effect_id: []const u8, enabled: bool) bool {
        if (self.getEffectById(effect_id)) |slot| {
            slot.setEnabled(enabled);
            return true;
        }
        return false;
    }

    /// Process audio through entire effect chain
    pub fn process(self: *const EffectChain, input: f32) f32 {
        var output = input;
        for (self.slots.items) |slot| {
            output = slot.process(output);
        }
        return output;
    }

    /// Get list of all effects metadata
    pub fn getEffectsInfo(self: *const EffectChain, allocator: std.mem.Allocator) ![]EffectInfo {
        var infos = try allocator.alloc(EffectInfo, self.slots.items.len);
        for (self.slots.items, 0..) |slot, i| {
            var params = try allocator.alloc(ports.Parameter, slot.descriptor.available_parameters.len);
            for (slot.descriptor.available_parameters, 0..) |param, j| {
                params[j] = .{
                    .name = param.name,
                    .value = slot.parameters.get(param.name) orelse param.default_value,
                };
            }
            infos[i] = .{
                .effect_id = slot.effect_id,
                .name = slot.descriptor.name,
                .enabled = slot.enabled,
                .parameters = params,
            };
        }
        return infos;
    }
};

/// Effect information structure for queries
pub const EffectInfo = struct {
    effect_id: []const u8,
    name: []const u8,
    enabled: bool,
    parameters: []ports.Parameter,

    pub fn deinit(self: *EffectInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.parameters);
    }
};
