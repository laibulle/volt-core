# Ports Architecture

This folder contains the **port interfaces** (contracts) that define how different components of the system interact.

## What is a Port?

In hexagonal/ports-and-adapters architecture:
- **Ports** = Interfaces/contracts (defined here)
- **Adapters** = Concrete implementations (in `src/drivers/`, `src/effects/`, etc.)

## Available Ports

### Audio Driver Port (`audio_driver.zig`)

Defines the interface for audio backend implementations.

**Implementations:**
- `src/drivers/coreaudio_graph_driver.zig` - Native macOS CoreAudio (recommended)
- `src/drivers/portaudio_driver.zig` - Cross-platform PortAudio (legacy)

**Interface:**
```zig
pub const AudioDriver = struct {
    vtable: *const VTable,
    context: *anyopaque,
    
    // Methods:
    init(allocator, DriverType) -> AudioDriver
    listDevices() -> void
    startProcessing(...) -> !void
    stopProcessing() -> void
    deinit() -> void
}
```

**Usage:**
```zig
const driver_port = @import("ports/audio_driver.zig");
var driver = try driver_port.AudioDriver.init(allocator, CoreAudioGraphDriver);
driver.listDevices();
try driver.startProcessing(input_dev, output_dev, buffer_size, sample_rate, duration, effects);
```

### Effects Port (`effects.zig`)

Defines interfaces for audio effect processors.

**Interfaces:**
- `EffectProcessor` - Single-sample processing interface
- `AudioBuffer` - Multi-channel buffer for batch processing

**Implementations:**
- `src/effects/distortions/distortion.zig` - Soft-clipping distortion
- `src/effects/convolution/convolution.zig` - Convolution reverb/cabinet simulation

**Usage:**
```zig
const effects_port = @import("ports/effects.zig");

// Single sample processing
const output = effect.process(input_sample);

// Buffer processing
var buffer = effects_port.AudioBuffer{
    .samples = audio_data,
    .channel_count = 2,
    .sample_rate = 48000,
};
```

## Design Principles

1. **Dependency Inversion**: High-level code depends on interfaces, not implementations
2. **Testability**: Ports can be mocked for unit tests
3. **Flexibility**: Easy to add new implementations without changing core logic
4. **Documentation**: Ports serve as the source of truth for component contracts

## Adding a New Port

1. Create new file in `src/ports/` (e.g., `midi_controller.zig`)
2. Define the interface with clear documentation
3. Implement adapters in appropriate folders (e.g., `src/midi/`)
4. Update this README with the new port documentation

## Adding a New Adapter

1. Find the relevant port interface in this folder
2. Create implementation in appropriate folder:
   - Audio drivers → `src/drivers/`
   - Effects → `src/effects/`
   - MIDI → `src/midi/` (future)
3. Implement all required vtable functions
4. Register in main.zig or factory

## Example: Adding a New Audio Driver

```zig
// src/drivers/jack_driver.zig
const driver_port = @import("../ports/audio_driver.zig");

pub const JackDriver = struct {
    allocator: std.mem.Allocator,
    // ... driver-specific state
    
    pub fn init(allocator: std.mem.Allocator) !*driver_port.AudioDriver {
        // Implementation
    }
    
    fn listDevices(driver: *driver_port.AudioDriver) void {
        // Implementation
    }
    
    // ... implement remaining vtable functions
};
```

## Notes

- Keep ports stable - breaking changes affect all adapters
- Ports should be minimal - only essential methods
- Document expected behavior and error conditions
- Consider async/callback patterns for real-time operations
