# Volt Core - AI Agent Documentation

## Project Overview

**Volt Core** is a multiplatform guitar multieffect application and plugin that provides professional-grade audio processing capabilities for musicians and producers.

### Key Features

- **Cross-Platform Support**: Runs natively on macOS, Windows, and Linux
- **VST Plugin**: Available as a VST plugin for seamless DAW integration
- **Effects Chaining**: Stack and route multiple effects with flexible signal flow
- **Neural Network IR Loading**: Load and apply impulse responses using neural network emulation
- **Real-time Audio Processing**: Low-latency processing for live performance and studio use

## Project Structure

```
volt-core/
├── build.zig              # Zig build configuration
├── build.zig.zon          # Zig package manifest
├── src/
│   ├── main.zig          # Application entry point
│   └── root.zig          # Core module definitions
```

## Technology Stack

- **Language**: Zig (modern systems programming language)
- **Build System**: Zig build system
- **Target Platforms**: macOS, Windows, Linux
- **Plugin Format**: VST (Virtual Studio Technology)

## Development Guidelines

### Building the Project

The project uses Zig's build system. Use `build.zig` to configure compilation targets and options.

### Module Organization

- `root.zig`: Core library definitions and exports
- `main.zig`: Application/plugin entry points

### Key Components to Implement/Extend

1. **Effect Processors**: Individual effect implementations (distortion, reverb, delay, etc.)
2. **Effects Chain Manager**: Orchestrates routing and signal flow between effects
3. **IR Loader**: Neural network-based impulse response processing
4. **Audio Buffer Management**: Real-time audio processing with minimal latency
5. **Platform Integration**: Native implementations for VST, macOS/Windows/Linux hosts
6. **User Interface**: Configuration and parameter controls for effects

## Audio Processing Architecture

The application follows a modular effects chain architecture:

```
Audio Input → Effect 1 → Effect 2 → ... → Effect N → Audio Output
                ↓         ↓              ↓
            Parameters, IR Data, Neural Network State
```

## Performance Considerations

- Real-time audio constraints require efficient DSP algorithms
- Memory management critical for embedded VST scenarios
- Cross-platform audio APIs (Core Audio, WASAPI, ALSA)
- Neural network inference must meet audio-thread latency budgets

## Future Development Areas

- Additional effect types (EQ, compression, modulation, etc.)
- VST3 plugin format support
- Preset management and UI framework
- Spectrum analysis and metering
- MIDI control integration
- Audio recording capabilities

## Notes

- Project is implemented in Zig for performance and safety
- Designed for both standalone application and plugin deployment
- Neural network IR emulation enables advanced amp/cab simulation
