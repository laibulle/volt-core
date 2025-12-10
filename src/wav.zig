const std = @import("std");
const audio = @import("audio.zig");

pub const WAVWriter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WAVWriter {
        return WAVWriter{
            .allocator = allocator,
        };
    }

    pub fn writeBuffer(_: WAVWriter, filename: []const u8, buffer: *const audio.AudioBuffer) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        const sample_count = buffer.samples.len / buffer.channel_count;
        const bytes_per_sample = 2; // 16-bit
        const data_size = sample_count * buffer.channel_count * bytes_per_sample;
        const file_size = 36 + data_size;

        // Write RIFF header
        try file.writeAll("RIFF");
        var le_buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &le_buffer, @as(u32, @intCast(file_size)), .little);
        try file.writeAll(&le_buffer);
        try file.writeAll("WAVE");

        // fmt sub-chunk
        try file.writeAll("fmt ");
        std.mem.writeInt(u32, &le_buffer, 16, .little);
        try file.writeAll(&le_buffer);
        
        var short_buffer: [2]u8 = undefined;
        std.mem.writeInt(u16, &short_buffer, 1, .little); // audio format
        try file.writeAll(&short_buffer);
        
        std.mem.writeInt(u16, &short_buffer, @as(u16, @intCast(buffer.channel_count)), .little);
        try file.writeAll(&short_buffer);
        
        std.mem.writeInt(u32, &le_buffer, buffer.sample_rate, .little);
        try file.writeAll(&le_buffer);
        
        const byte_rate = buffer.sample_rate * buffer.channel_count * bytes_per_sample;
        std.mem.writeInt(u32, &le_buffer, @as(u32, @intCast(byte_rate)), .little);
        try file.writeAll(&le_buffer);
        
        const block_align = buffer.channel_count * bytes_per_sample;
        std.mem.writeInt(u16, &short_buffer, @as(u16, @intCast(block_align)), .little);
        try file.writeAll(&short_buffer);
        
        std.mem.writeInt(u16, &short_buffer, 16, .little); // bits per sample
        try file.writeAll(&short_buffer);

        // data sub-chunk
        try file.writeAll("data");
        std.mem.writeInt(u32, &le_buffer, @as(u32, @intCast(data_size)), .little);
        try file.writeAll(&le_buffer);

        // Write audio data
        for (buffer.samples) |sample| {
            var clamped = sample;
            if (clamped > 1.0) clamped = 1.0;
            if (clamped < -1.0) clamped = -1.0;
            
            const int_sample = @as(i16, @intFromFloat(clamped * 32767.0));
            std.mem.writeInt(i16, &short_buffer, int_sample, .little);
            try file.writeAll(&short_buffer);
        }
    }
};
