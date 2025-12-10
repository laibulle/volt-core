const std = @import("std");
const audio = @import("audio.zig");

pub const WAVWriter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WAVWriter {
        return WAVWriter{
            .allocator = allocator,
        };
    }

    pub fn writeBuffer(self: *const WAVWriter, filename: []const u8, buffer: *const audio.AudioBuffer) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        const writer = file.writer();
        
        // WAV header
        try writer.writeAll("RIFF");
        const sample_count = buffer.samples.len / buffer.channel_count;
        const bytes_per_sample = 2; // 16-bit
        const data_size = sample_count * buffer.channel_count * bytes_per_sample;
        const file_size = 36 + data_size;
        
        try writer.writeInt(u32, @as(u32, @intCast(file_size)), .little);
        try writer.writeAll("WAVE");
        
        // fmt sub-chunk
        try writer.writeAll("fmt ");
        try writer.writeInt(u32, 16, .little); // subchunk1 size
        try writer.writeInt(u16, 1, .little); // audio format (1 = PCM)
        try writer.writeInt(u16, @as(u16, @intCast(buffer.channel_count)), .little);
        try writer.writeInt(u32, buffer.sample_rate, .little);
        const byte_rate = buffer.sample_rate * buffer.channel_count * bytes_per_sample;
        try writer.writeInt(u32, @as(u32, @intCast(byte_rate)), .little);
        const block_align = buffer.channel_count * bytes_per_sample;
        try writer.writeInt(u16, @as(u16, @intCast(block_align)), .little);
        try writer.writeInt(u16, 16, .little); // bits per sample

        // data sub-chunk
        try writer.writeAll("data");
        try writer.writeInt(u32, @as(u32, @intCast(data_size)), .little);

        // Write audio data
        for (buffer.samples) |sample| {
            var clamped = sample;
            if (clamped > 1.0) clamped = 1.0;
            if (clamped < -1.0) clamped = -1.0;
            
            const int_sample = @as(i16, @intFromFloat(clamped * 32767.0));
            try writer.writeInt(i16, int_sample, .little);
        }
    }
};
