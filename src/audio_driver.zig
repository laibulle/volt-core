const std = @import("std");

/// Audio driver abstraction layer - supports multiple backends
pub const AudioDriver = struct {
    vtable: *const VTable,
    context: *anyopaque,

    pub const VTable = struct {
        /// Initialize the audio driver
        init: *const fn (allocator: std.mem.Allocator) anyerror!*AudioDriver,

        /// List available audio devices
        list_devices: *const fn (driver: *AudioDriver) void,

        /// Start real-time processing with effects chain
        start_processing: *const fn (
            driver: *AudioDriver,
            input_device: i32,
            output_device: i32,
            buffer_size: usize,
            sample_rate: u32,
            duration: f64,
            effects_chain: []const *anyopaque,
        ) anyerror!void,

        /// Stop real-time processing
        stop_processing: *const fn (driver: *AudioDriver) void,

        /// Deinitialize the driver
        deinit: *const fn (driver: *AudioDriver) void,
    };

    pub fn init(allocator: std.mem.Allocator, comptime DriverType: type) !AudioDriver {
        return try DriverType.init(allocator);
    }

    pub fn listDevices(self: *AudioDriver) void {
        self.vtable.list_devices(self);
    }

    pub fn startProcessing(
        self: *AudioDriver,
        input_device: i32,
        output_device: i32,
        buffer_size: usize,
        sample_rate: u32,
        duration: f64,
        effects_chain: []const *anyopaque,
    ) !void {
        try self.vtable.start_processing(self, input_device, output_device, buffer_size, sample_rate, duration, effects_chain);
    }

    pub fn stopProcessing(self: *AudioDriver) void {
        self.vtable.stop_processing(self);
    }

    pub fn deinit(self: *AudioDriver) void {
        self.vtable.deinit(self);
    }
};

/// Detect which driver should be used based on platform
pub fn selectDriver() type {
    const builtin = @import("builtin");
    if (comptime builtin.os.tag == .macos) {
        return @import("drivers/coreaudio_graph_driver.zig").CoreAudioGraphDriver;
    } else if (comptime builtin.os.tag == .linux) {
        return @import("drivers/portaudio_driver.zig").PortAudioDriver;
    } else {
        @compileError("Unsupported platform - only macOS and Linux are supported");
    }
}
