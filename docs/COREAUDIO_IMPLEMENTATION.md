# CoreAudio Implementation Guide

## Status
CoreAudio driver structure is in place but needs proper implementation. Currently using PortAudio as fallback for macOS.

## Why CoreAudio?
- **Native macOS**: Direct OS API, no abstraction overhead
- **Lower Latency**: ~1-2ms vs ~3-5ms with PortAudio
- **Better Integration**: Native System Audio preferences
- **ASIO-equivalent**: Professional audio interface control

## Implementation Challenges

### 1. Audio Unit Setup
The current implementation fails at audio unit property configuration:
- Error -10879: Invalid scope for property
- Error -10865: Invalid format or device

**Solution**: Use correct Audio Unit scope/element combinations:
```zig
// For DefaultOutput AudioUnit:
// - Output scope (0): Device audio output
// - Input scope (1): Input from device (if capturing)
// Must set properties in correct order
```

### 2. AudioStreamBasicDescription Format
Need to properly configure:
- Sample rate (44100 Hz)
- Format flags (LinearPCM, Float32, Interleaved)
- Channels (1 for mono guitar input)
- Bytes per sample/frame

### 3. Render Callback Registration
The callback needs:
- Correct function signature matching Apple's expectations
- Proper refcon (reference context) passing
- Safe access to effect chain from audio callback thread

### 4. Device Selection
Current implementation uses default I/O. For full device selection:
- Query available devices via AudioObjectID API
- Set input/output devices on Audio Unit
- Handle device changes/disconnections

## Next Steps

1. **Test with HAL (Hardware Abstraction Layer)**
   - Use `kAudioUnitSubType_HALOutput` for device control
   - Configure input/output separately

2. **Simplify Audio Unit Graph**
   - Start with output-only (monitoring)
   - Add input processing after

3. **Use AUGraph** (optional)
   - More complex but better for effect chains
   - Alternative: Direct Audio Unit with callbacks

4. **Reference Implementation**
   - Apple's "Audio Unit - Basic Usage" sample code
   - Recommended: Start with simple tone generator
   - Then add input processing

## Testing Checklist

- [ ] Audio Unit initializes without errors
- [ ] Render callback is invoked
- [ ] Input audio from microphone/Scarlett flows through
- [ ] Effects (distortion + convolution) apply
- [ ] Latency is measurably lower than PortAudio
- [ ] Device changes handled gracefully
- [ ] Volume/gain control working

## Files
- `src/drivers/coreaudio_driver.zig` - Current partial implementation
- `src/drivers/portaudio_driver.zig` - Working reference
- `src/audio_driver.zig` - Driver abstraction interface

## Resources
- [Apple Audio Unit Documentation](https://developer.apple.com/documentation/audiounit)
- [Core Audio Overview](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)
- [HAL Output Unit Documentation](https://developer.apple.com/documentation/audiounit/kaudounitsubtype_haloutput)
