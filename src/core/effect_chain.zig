const std = @import("std");
const ports = @import("../ports/effects.zig");
const audio = @import("../audio.zig");

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

    /// Optional buffer process function (for effects that need full buffer at once)
    process_buffer_fn: ?*const fn (self: *anyopaque, buffer: *audio.AudioBuffer) void = null,

    /// Optional deinit function for the effect instance
    deinit_fn: ?*const fn (allocator: std.mem.Allocator, instance: *anyopaque) void = null,

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
        return init_with_deinit(allocator, effect_id, descriptor, instance, process_fn, null);
    }

    /// Initialize an effect slot with optional deinit callback
    pub fn init_with_deinit(
        allocator: std.mem.Allocator,
        effect_id: []const u8,
        descriptor: *const ports.EffectDescriptor,
        instance: *anyopaque,
        process_fn: *const fn (self: *anyopaque, input: f32) f32,
        deinit_fn: ?*const fn (allocator: std.mem.Allocator, instance: *anyopaque) void,
    ) !EffectSlot {
        return init_with_buffer_fn(allocator, effect_id, descriptor, instance, process_fn, null, deinit_fn);
    }

    /// Initialize an effect slot with optional buffer process function
    pub fn init_with_buffer_fn(
        allocator: std.mem.Allocator,
        effect_id: []const u8,
        descriptor: *const ports.EffectDescriptor,
        instance: *anyopaque,
        process_fn: *const fn (self: *anyopaque, input: f32) f32,
        process_buffer_fn: ?*const fn (self: *anyopaque, buffer: *audio.AudioBuffer) void,
        deinit_fn: ?*const fn (allocator: std.mem.Allocator, instance: *anyopaque) void,
    ) !EffectSlot {
        var slot = EffectSlot{
            .effect_id = effect_id,
            .descriptor = descriptor,
            .instance = instance,
            .process_fn = process_fn,
            .process_buffer_fn = process_buffer_fn,
            .deinit_fn = deinit_fn,
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
    /// Maximum number of effects in the chain
    const MAX_EFFECTS = 16;

    /// List of effect slots
    slots: [MAX_EFFECTS]?EffectSlot = [_]?EffectSlot{null} ** MAX_EFFECTS,

    /// Current number of effects
    effect_count: usize = 0,

    /// Allocator for memory management
    allocator: std.mem.Allocator,

    /// Initialize effect chain
    pub fn init(allocator: std.mem.Allocator) EffectChain {
        return EffectChain{
            .allocator = allocator,
        };
    }

    /// Deinitialize effect chain and all effects
    pub fn deinit(self: *EffectChain) void {
        for (0..self.effect_count) |i| {
            if (self.slots[i]) |*slot| {
                // Free the effect ID string
                self.allocator.free(slot.effect_id);
                // Call deinit callback if present
                if (slot.deinit_fn) |fn_ptr| {
                    fn_ptr(self.allocator, slot.instance);
                }
                // Deinit parameters map
                slot.deinit();
            }
        }
    }

    /// Add an effect to the chain
    pub fn addEffect(
        self: *EffectChain,
        effect_id: []const u8,
        descriptor: *const ports.EffectDescriptor,
        instance: *anyopaque,
        process_fn: *const fn (self: *anyopaque, input: f32) f32,
    ) !void {
        return self.addEffect_with_deinit(effect_id, descriptor, instance, process_fn, null);
    }

    /// Add an effect to the chain with optional deinit callback
    pub fn addEffect_with_deinit(
        self: *EffectChain,
        effect_id: []const u8,
        descriptor: *const ports.EffectDescriptor,
        instance: *anyopaque,
        process_fn: *const fn (self: *anyopaque, input: f32) f32,
        deinit_fn: ?*const fn (allocator: std.mem.Allocator, instance: *anyopaque) void,
    ) !void {
        return self.addEffect_with_buffer_fn(effect_id, descriptor, instance, process_fn, null, deinit_fn);
    }

    /// Add an effect with optional buffer process function
    pub fn addEffect_with_buffer_fn(
        self: *EffectChain,
        effect_id: []const u8,
        descriptor: *const ports.EffectDescriptor,
        instance: *anyopaque,
        process_fn: *const fn (self: *anyopaque, input: f32) f32,
        process_buffer_fn: ?*const fn (self: *anyopaque, buffer: *audio.AudioBuffer) void,
        deinit_fn: ?*const fn (allocator: std.mem.Allocator, instance: *anyopaque) void,
    ) !void {
        if (self.effect_count >= MAX_EFFECTS) {
            return error.ChainFull;
        }

        const slot = try EffectSlot.init_with_buffer_fn(
            self.allocator,
            effect_id,
            descriptor,
            instance,
            process_fn,
            process_buffer_fn,
            deinit_fn,
        );
        self.slots[self.effect_count] = slot;
        self.effect_count += 1;
    }

    /// Remove an effect at specific index
    pub fn removeEffect(self: *EffectChain, index: usize) bool {
        if (index >= self.effect_count) return false;
        if (self.slots[index]) |*slot| {
            slot.deinit();
        }
        // Shift remaining effects
        for (index..self.effect_count - 1) |i| {
            self.slots[i] = self.slots[i + 1];
        }
        self.slots[self.effect_count - 1] = null;
        self.effect_count -= 1;
        return true;
    }

    /// Get number of effects in chain
    pub fn effectCount(self: *const EffectChain) usize {
        return self.effect_count;
    }

    /// Get effect at index
    pub fn getEffect(self: *EffectChain, index: usize) ?*EffectSlot {
        if (index >= self.effect_count) return null;
        if (self.slots[index]) |*slot| {
            return slot;
        }
        return null;
    }

    /// Get effect by ID
    pub fn getEffectById(self: *EffectChain, effect_id: []const u8) ?*EffectSlot {
        for (0..self.effect_count) |i| {
            if (self.slots[i]) |*slot| {
                if (std.mem.eql(u8, slot.effect_id, effect_id)) {
                    return slot;
                }
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
        if (effect_index >= self.effect_count) return false;
        if (self.slots[effect_index]) |*slot| {
            return try slot.setParameter(param_name, value);
        }
        return false;
    }

    /// Get parameter from specific effect
    pub fn getEffectParameter(
        self: *const EffectChain,
        effect_index: usize,
        param_name: []const u8,
    ) ?f32 {
        if (effect_index >= self.effect_count) return null;
        if (self.slots[effect_index]) |slot| {
            return slot.getParameter(param_name);
        }
        return null;
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
        if (index >= self.effect_count) return false;
        if (self.slots[index]) |*slot| {
            slot.setEnabled(enabled);
            return true;
        }
        return false;
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
        for (0..self.effect_count) |i| {
            if (self.slots[i]) |slot| {
                output = slot.process(output);
            }
        }
        return output;
    }

    /// Process entire audio buffer through the effect chain
    pub fn processBuffer(self: *const EffectChain, buffer: *audio.AudioBuffer) void {
        // First pass: apply buffer-level effects (e.g., convolver)
        for (0..self.effect_count) |i| {
            if (self.slots[i]) |slot| {
                if (slot.process_buffer_fn) |process_buffer_fn| {
                    process_buffer_fn(slot.instance, buffer);
                }
            }
        }

        // Second pass: apply sample-level effects (e.g., distortion)
        const sample_count = buffer.samples.len / buffer.channel_count;
        for (0..sample_count) |i| {
            for (0..buffer.channel_count) |ch| {
                const sample_idx = i * buffer.channel_count + ch;
                var output = buffer.samples[sample_idx];

                for (0..self.effect_count) |j| {
                    if (self.slots[j]) |slot| {
                        // Skip effects that have their own buffer processing
                        if (slot.process_buffer_fn == null) {
                            output = slot.process(output);
                        }
                    }
                }

                buffer.samples[sample_idx] = output;
            }
        }
    }

    /// Get list of all effects metadata
    pub fn getEffectsInfo(self: *const EffectChain, allocator: std.mem.Allocator) ![]EffectInfo {
        var infos = try allocator.alloc(EffectInfo, self.effect_count);
        for (0..self.effect_count) |i| {
            if (self.slots[i]) |slot| {
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
