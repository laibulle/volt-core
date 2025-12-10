const std = @import("std");
const audio = @import("audio.zig");
const wav_loader_module = @import("wav_loader.zig");

pub const IRLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) IRLoader {
        return IRLoader{
            .allocator = allocator,
        };
    }

    pub fn loadFile(self: IRLoader, filepath: []const u8) !audio.AudioBuffer {
        const wav_loader = wav_loader_module.WAVLoader.init(self.allocator);
        return try wav_loader.loadFile(filepath);
    }
};
