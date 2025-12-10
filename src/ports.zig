// Volt Core - Port Interfaces
// Convenience re-exports for all port interfaces

pub const audio_driver = @import("ports/audio_driver.zig");
pub const effects = @import("ports/effects.zig");
pub const device_manager = @import("ports/device_manager.zig");

// Direct type exports for convenience
pub const AudioDriver = audio_driver.AudioDriver;
pub const EffectProcessor = effects.EffectProcessor;
pub const AudioBuffer = effects.AudioBuffer;
pub const DeviceManager = device_manager.DeviceManager;
pub const DeviceInfo = device_manager.DeviceInfo;
