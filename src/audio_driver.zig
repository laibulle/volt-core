// Re-export the audio driver port interface
// This maintains backward compatibility while moving to ports architecture
pub const AudioDriver = @import("ports/audio_driver.zig").AudioDriver;

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
