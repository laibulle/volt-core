const std = @import("std");

/// Port: Audio Device Manager Interface
/// Defines how to query and manage audio devices.
pub const DeviceInfo = struct {
    id: u32,
    name: []const u8,
    is_input: bool,
    is_output: bool,
    default_sample_rate: u32,
    channel_count: u32,
};

pub const DeviceManager = struct {
    /// List all available audio devices
    /// Returns a slice of DeviceInfo structs
    /// Caller is responsible for freeing the returned slice
    list_devices_fn: *const fn (allocator: std.mem.Allocator) anyerror![]DeviceInfo,

    /// Get default input device
    get_default_input_fn: *const fn () ?DeviceInfo,

    /// Get default output device
    get_default_output_fn: *const fn () ?DeviceInfo,

    pub fn listDevices(self: *const DeviceManager, allocator: std.mem.Allocator) ![]DeviceInfo {
        return try self.list_devices_fn(allocator);
    }

    pub fn getDefaultInput(self: *const DeviceManager) ?DeviceInfo {
        return self.get_default_input_fn();
    }

    pub fn getDefaultOutput(self: *const DeviceManager) ?DeviceInfo {
        return self.get_default_output_fn();
    }
};
