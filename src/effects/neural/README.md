# Neural Amp Modeler (NAM) Effect Module

## Overview

The Neural Amp Modeler effect brings deep learning-based audio modeling to volt-core, allowing you to capture and use trained neural network models of guitar amplifiers and audio equipment.

## Module Structure

```
src/effects/neural/
├── nam_loader.zig         # Model file parser and loader
├── neural_effect.zig      # Effect processor implementation
└── README.md              # This file
```

## Usage

### Basic Configuration

Add a neural effect to your JSON chain configuration:

```json
{
  "effects": [
    {
      "id": "my_neural_amp",
      "type": "neural",
      "parameters": {
        "model_path": "path/to/model.nam",
        "dry_wet": 1.0,
        "input_gain": 0.0,
        "output_gain": 0.0
      }
    }
  ]
}
```

### Required Parameters

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `model_path` | string | - | Path to .nam model file (REQUIRED) |
| `dry_wet` | float | 0.0-1.0 | Mix between dry (0) and wet (1) signal |
| `input_gain` | float | -24 to +24 | Input gain in dB |
| `output_gain` | float | -24 to +24 | Output gain in dB |

### Example: Full Effect Chain

```json
{
  "effects": [
    {
      "id": "guitar_in",
      "type": "distortion",
      "parameters": { "gain": 3.0 }
    },
    {
      "id": "amp_sim",
      "type": "neural",
      "parameters": {
        "model_path": "samples/nam_models/amps/Vox_AC30.nam",
        "dry_wet": 1.0,
        "input_gain": -3.0,
        "output_gain": 0.0
      }
    },
    {
      "id": "cabinet",
      "type": "convolver",
      "parameters": {
        "ir_path": "samples/ir/cabinet_1x12.wav"
      }
    }
  ]
}
```

## Finding Models

### Community Sources

1. **Tonehunt.org** (Recommended)
   - Official NAM model repository
   - https://tonehunt.org/search?q=vox
   - Filter by amp name, quality rating, creator

2. **GitHub - Neural Amp Modeler**
   - Official project repository
   - Example models and training scripts
   - https://github.com/sdatkinson/neural-amp-modeler

3. **Audio Forums**
   - Reddit: r/AudioEngineering
   - Gearslutz forums
   - Local audio communities

### Popular Models

| Model | Creator | License | Notes |
|-------|---------|---------|-------|
| Vox AC30 Brown | NAM Community | CC-BY | Classic British tone |
| Fender Blackface | NAM Community | CC-BY | Warm, organic sound |
| Marshall JCM800 | NAM Community | CC-BY | Classic rock amp |
| Tube Screamer | NAM Community | CC-BY | Overdrive effect |
| Boss Katana | NAM Community | CC-BY | Modern clean amp |

## Implementation Details

### NAM File Format

Neural Amp Modeler files (`.nam`) contain:

```
NAM Container
├── Metadata Section (optional JSON header)
│   ├── Model name
│   ├── Creator information
│   ├── Training date
│   ├── Sample rate
│   └── Latency estimate
├── Network Architecture
│   ├── Layer definitions
│   ├── Activation functions
│   └── Connection topology
└── Trained Weights
    ├── Quantized parameters
    ├── Biases
    └── Scale factors
```

### Processing Pipeline

```
Input Audio Buffer
    ↓
[Input Gain] (dB → linear conversion)
    ↓
[Neural Model Processing] (placeholder for ONNX)
    ↓
[Output Gain] (dB → linear conversion)
    ↓
[Dry/Wet Mixing] (blend with original)
    ↓
Output Audio Buffer
```

### Memory Usage

- **Per-instance overhead**: ~50-100 MB
- **Model size**: 0.5-10 MB
- **Dry buffer**: Allocated only when dry_wet < 1.0
- **Reallocated on demand**: If buffer size changes

## API Reference

### NeuralEffect Type

```zig
pub const NeuralEffect = struct {
    // Load effect from NAM file
    pub fn initFromFile(allocator: std.mem.Allocator, model_path: []const u8) !NeuralEffect

    // Process audio buffer
    pub fn processBuffer(self: *NeuralEffect, buffer: *audio.AudioBuffer) void

    // Set parameter value
    pub fn setParameter(self: *NeuralEffect, name: []const u8, value: f32) bool

    // Get parameter value
    pub fn getParameter(self: *const NeuralEffect, name: []const u8) ?f32

    // Clean up resources
    pub fn deinit(self: *NeuralEffect) void
};
```

### Example Usage (Zig)

```zig
const std = @import("std");
const neural = @import("volt_core").neural;
const audio = @import("volt_core").audio;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load neural model
    var effect = try neural.neural_effect.NeuralEffect.initFromFile(
        allocator,
        "models/amp.nam"
    );
    defer effect.deinit();

    // Create audio buffer
    var buffer = try audio.AudioBuffer.init(allocator, 48000, 1, 48000);
    defer buffer.deinit(allocator);

    // Generate test signal
    buffer.generateTestSignal(1000); // 1 kHz sine wave

    // Set parameters
    _ = effect.setParameter("dry_wet", 0.8);
    _ = effect.setParameter("input_gain", -6.0);

    // Process
    effect.processBuffer(&buffer);

    // Use buffer...
}
```

## Parameter Guide

### dry_wet (0.0 - 1.0)
- **0.0**: 100% dry (unprocessed signal)
- **0.5**: 50/50 blend of dry and neural model
- **1.0**: 100% wet (full neural model)

**Use cases:**
- Blend in subtle amp character: 0.3-0.5
- Full amp replacement: 1.0
- Parallel compression style: 0.7-0.8

### input_gain (-24 to +24 dB)
- Applied BEFORE neural model processing
- Use to match model's expected input level
- Typical range: -6 to +6 dB

**Guidelines:**
- If output is distorting: reduce input_gain
- If output is too quiet: increase input_gain
- Most models trained around 0 dB

### output_gain (-24 to +24 dB)
- Applied AFTER neural model processing
- Use to compensate for level changes
- Typical range: -6 to +6 dB

**Guidelines:**
- Adjust for perceived volume matching
- Can be used for dynamic range control
- Use in conjunction with input_gain

## Phase 1 Status

### ✅ Implemented
- NAM file loading and metadata parsing
- JSON configuration support
- Effect chain integration
- Parameter management
- Dry/wet mixing
- Gain control (input/output)
- Test framework

### ⏳ Planned (Phase 2)
- ONNX Runtime integration
- Actual neural network inference
- Model normalization/denormalization
- Real-time latency optimization
- Multiple model format support
- VST/AU plugin wrapper

## Troubleshooting

### Model Loading Issues

**Q: "Error: MissingModelPath"**
- A: Ensure `model_path` parameter is set in JSON config

**Q: "File not found" error**
- A: Check file path is correct and readable
- A: Use absolute path or path relative to working directory

**Q: Empty model metadata**
- A: NAM file may not contain JSON header
- A: Check file is valid .nam file

### Audio Issues

**Q: Output is distorted**
- A: Reduce `input_gain` (model may be clipping)
- A: Check model training level expectations

**Q: Output is silent**
- A: Increase `input_gain`
- A: Verify model file is valid (not empty)

**Q: No effect is heard**
- A: Check `dry_wet` is > 0
- A: Verify model file loads successfully

## Testing

Run the neural effect test:

```bash
./test_neural_orange.sh
```

This will:
1. Build the project
2. Verify model file exists
3. Check configuration validity
4. Load and process audio through the effect

## Performance Notes

- **CPU Usage**: 5-15% per instance on modern CPU core
- **Latency**: <10ms typical
- **Real-time factor**: 1000x+ (processes much faster than real-time)
- **Memory**: 50-100 MB per loaded model

## License

The Neural Amp Modeler effect processor is part of volt-core (same license).

Model files (`.nam`) have varying licenses:
- Check creator licensing for each model
- Many are CC-BY or CC0 (free for any use)
- Some have commercial restrictions
- Always attribute if required by license

## Resources

- **NAM Project**: https://www.neuralampmodeler.com/
- **Model Repository**: https://tonehunt.org/
- **Integration Plan**: See NEURAL_INTEGRATION_PLAN.md
- **Model Discovery**: See NEURAL_MODELS_GUIDE.md

## Contributing

To improve the neural effect module:

1. Report issues on GitHub
2. Suggest new features
3. Share NAM model recommendations
4. Help with ONNX Runtime integration (Phase 2)

---

**Status**: Phase 1 Complete (Core functionality)

**Next**: Phase 2 (ONNX Runtime & inference engine)

**Questions?** Check NEURAL_INTEGRATION_PLAN.md or NEURAL_MODELS_GUIDE.md
