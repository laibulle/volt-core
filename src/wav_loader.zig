const std = @import("std");
const audio = @import("audio.zig");

pub const WAVLoader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WAVLoader {
        return WAVLoader{
            .allocator = allocator,
        };
    }

    pub fn loadFile(self: WAVLoader, filename: []const u8) !audio.AudioBuffer {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        var header: [12]u8 = undefined;
        _ = try file.readAll(&header);

        // Check RIFF header
        if (!std.mem.eql(u8, header[0..4], "RIFF")) {
            return error.InvalidWAVFile;
        }
        if (!std.mem.eql(u8, header[8..12], "WAVE")) {
            return error.InvalidWAVFile;
        }

        // Find fmt chunk
        var chunk_header: [8]u8 = undefined;
        var fmt_size: u32 = 0;
        var sample_rate: u32 = 0;
        var channel_count: u16 = 0;
        var bits_per_sample: u16 = 0;
        var data_size: u32 = 0;

        while (try file.readAll(&chunk_header) == 8) {
            const chunk_id = chunk_header[0..4];
            const chunk_len = std.mem.readInt(u32, chunk_header[4..8], .little);

            if (std.mem.eql(u8, chunk_id, "fmt ")) {
                fmt_size = chunk_len;
                var fmt_data: [16]u8 = undefined;
                _ = try file.readAll(fmt_data[0..@min(fmt_size, 16)]);

                const audio_format = std.mem.readInt(u16, fmt_data[0..2], .little);
                if (audio_format != 1) {
                    return error.UnsupportedAudioFormat;
                }

                channel_count = std.mem.readInt(u16, fmt_data[2..4], .little);
                sample_rate = std.mem.readInt(u32, fmt_data[4..8], .little);
                bits_per_sample = std.mem.readInt(u16, fmt_data[14..16], .little);

                if (fmt_size > 16) {
                    var skip_buf: [256]u8 = undefined;
                    _ = try file.readAll(skip_buf[0..@min(fmt_size - 16, skip_buf.len)]);
                }
            } else if (std.mem.eql(u8, chunk_id, "data")) {
                data_size = chunk_len;
                break;
            } else {
                var skip_buf: [4096]u8 = undefined;
                var remaining = chunk_len;
                while (remaining > 0) {
                    const to_read = @min(remaining, skip_buf.len);
                    _ = try file.readAll(skip_buf[0..to_read]);
                    remaining -= to_read;
                }
            }
        }

        if (sample_rate == 0 or channel_count == 0) {
            return error.InvalidWAVFormat;
        }

        // Calculate sample count
        const bytes_per_sample = bits_per_sample / 8;
        const sample_count = data_size / (channel_count * bytes_per_sample);

        var buffer = try audio.AudioBuffer.init(self.allocator, sample_count, channel_count, sample_rate);

        // Read audio data
        if (bits_per_sample == 16) {
            var sample_i: usize = 0;
            var sample_buf: [2]u8 = undefined;
            var read_count: usize = 0;

            while (sample_i < sample_count * channel_count) {
                read_count = file.read(&sample_buf) catch break;
                if (read_count < 2) break;

                const int_sample = std.mem.readInt(i16, &sample_buf, .little);
                const f_sample = @as(f32, @floatFromInt(int_sample)) / 32768.0;
                buffer.samples[sample_i] = f_sample;
                sample_i += 1;
            }
        } else if (bits_per_sample == 24) {
            var sample_i: usize = 0;
            var sample_buf: [3]u8 = undefined;
            var read_count: usize = 0;

            while (sample_i < sample_count * channel_count) {
                read_count = file.read(&sample_buf) catch break;
                if (read_count < 3) break;

                // Convert 24-bit little-endian to 32-bit signed integer
                var int_sample: i32 = @as(i32, sample_buf[0]) | 
                                      (@as(i32, sample_buf[1]) << 8) | 
                                      (@as(i32, sample_buf[2]) << 16);
                
                // Sign extend if MSB is set (bit 23)
                if (int_sample & 0x800000 != 0) {
                    int_sample = @as(i32, @bitCast(@as(u32, @bitCast(int_sample)) | 0xFF000000));
                }
                
                const f_sample = @as(f32, @floatFromInt(int_sample)) / 8388608.0;
                buffer.samples[sample_i] = f_sample;
                sample_i += 1;
            }
        }

        return buffer;
    }
};

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
