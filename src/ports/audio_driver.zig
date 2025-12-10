const std = @import("std");

/// Port: Audio Driver Interface
/// This defines the contract that all audio driver implementations must fulfill.
/// Implementations should be placed in src/drivers/ folder.
pub const AudioDriver = struct {
    vtable: *const VTable,
    context: *anyopaque,

    /// Virtual table defining the audio driver interface
    pub const VTable = struct {
        /// Initialize the audio driver
        /// Returns an AudioDriver instance ready for use
        init: *const fn (allocator: std.mem.Allocator) anyerror!*AudioDriver,

        /// List all available audio input/output devices
        /// Should print device information to stdout
        list_devices: *const fn (driver: *AudioDriver) void,

        /// Start real-time audio processing
        /// @param input_device - Input device index (-1 for default)
        /// @param output_device - Output device index (-1 for default)
        /// @param buffer_size - Buffer size in frames
        /// @param sample_rate - Sample rate in Hz (44100, 48000, 96000, etc.)
        /// @param duration - Processing duration in seconds (-1 for infinite)
        /// @param effects_chain - Array of effect processors to apply
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
        /// Should cleanup resources but keep driver initialized
        stop_processing: *const fn (driver: *AudioDriver) void,

        /// Deinitialize the driver and free all resources
        deinit: *const fn (driver: *AudioDriver) void,
    };

    /// Factory method to create a driver of specific type
    pub fn init(allocator: std.mem.Allocator, comptime DriverType: type) !AudioDriver {
        return try DriverType.init(allocator);
    }

    /// List available audio devices
    pub fn listDevices(self: *AudioDriver) void {
        self.vtable.list_devices(self);
    }

    /// Start real-time audio processing with effects chain
    pub fn startProcessing(
        self: *AudioDriver,
        input_device: i32,
        output_device: i32,
        buffer_size: usize,
        sample_rate: u32,
        duration: f64,
        effects_chain: []const *anyopaque,
    ) !void {
        try self.vtable.start_processing(
            self,
            input_device,
            output_device,
            buffer_size,
            sample_rate,
            duration,
            effects_chain,
        );
    }

    /// Stop audio processing
    pub fn stopProcessing(self: *AudioDriver) void {
        self.vtable.stop_processing(self);
    }

    /// Cleanup and free resources
    pub fn deinit(self: *AudioDriver) void {
        self.vtable.deinit(self);
    }
};
