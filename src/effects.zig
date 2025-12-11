const std = @import("std");
const audio = @import("audio.zig");

pub const distortion = @import("effects/distortions/distortion.zig");
pub const Distortion = distortion.Distortion;

pub const convolver = @import("effects/convolver/convolver.zig");
pub const Convolver = convolver.Convolver;

pub const convolver_effect = @import("effects/convolver/convolver_effect.zig");
pub const ConvolverEffect = convolver_effect.Convolver;

/// Effect chain for processing audio through multiple effects
pub const EffectChain = struct {
    effects: std.ArrayList(*const anyopaque),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EffectChain {
        return EffectChain{
            .effects = std.ArrayList(*const anyopaque).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EffectChain) void {
        self.effects.deinit();
    }

    pub fn addDistortion(self: *EffectChain, distortion_effect: *const Distortion) !void {
        try self.effects.append(@ptrCast(distortion_effect));
    }
};
