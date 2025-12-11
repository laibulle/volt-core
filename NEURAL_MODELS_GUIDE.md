# Neural Amp Modeler - Model Discovery & Usage Guide

## Available NAM Model Sources

### 1. **Tonehunt.org** (Primary Community Repository)
- **URL**: https://tonehunt.org/
- **Description**: Official community hub for sharing NAM models
- **Search for Vox AC30**: https://tonehunt.org/search?q=vox+ac30
- **Notable AC30 models available**:
  - "Vox AC30 Brown" - Classic vintage tone
  - "Vox AC30 HW Miked" - Miked cabinet version
  - "Vox AC30 Clean" - Clean channel
  - "Vox AC30 Drive" - Driven tone
- **License**: Varies per model (check each one)
- **Download**: Direct .nam file download available

### 2. **GitHub - Neural Amp Modeler Project**
- **URL**: https://github.com/sdatkinson/neural-amp-modeler
- **Contents**: 
  - Official training scripts
  - Example models and datasets
  - Community contributions
- **Notable**: Some official demo models included

### 3. **NAM Project Official Site**
- **URL**: https://www.neuralampmodeler.com/
- **Resources**: 
  - Documentation
  - Model gallery
  - Training guides
- **Download section**: Links to models and tools

### 4. **Reddit & Audio Communities**
- **r/AudioEngineering**: Model sharing threads
- **GearSlutz**: Audio engineering forum with model links
- **Gearslutz Forum**: NAM discussion and model sharing

### 5. **Google Drive Collections**
- Various modelers share models via public Google Drive folders
- Search: "NAM models" + "google drive" or "vox ac30"

---

## How to Download & Prepare a Model

### Step 1: Find a Model
1. Go to https://tonehunt.org/
2. Search for "Vox AC30" or your amp of choice
3. Read description, check licensing, review ratings
4. Click download button

### Step 2: Organize Locally
```bash
# Create models directory in volt-core
mkdir -p samples/nam_models/amps
mkdir -p samples/nam_models/effects
mkdir -p samples/nam_models/cabinets

# Place downloaded .nam file
cp ~/Downloads/Vox_AC30_Brown.nam samples/nam_models/amps/
```

### Step 3: Create Test Configuration
```json
{
  "effects": [
    {
      "type": "neural",
      "enabled": true,
      "model": "samples/nam_models/amps/Vox_AC30_Brown.nam",
      "name": "Vox AC30 Brown",
      "sampleRate": 48000,
      "normalize": true
    }
  ]
}
```

### Step 4: Test in volt-core
```bash
# Test loading the model
./zig-out/bin/volt_core --effect neural --model samples/nam_models/amps/Vox_AC30_Brown.nam test.wav output.wav
```

---

## Recommended Models for Testing

### For Initial Development
1. **Vox AC30 Brown** ⭐⭐⭐⭐⭐
   - Classic, iconic tone
   - Good frequency range
   - Moderate compression/saturation
   - **Why**: Great for testing both clean and driven tones

2. **Boss Katana Clean** ⭐⭐⭐⭐
   - Simple, clean response
   - Good for baseline testing
   - Low-distortion reference

3. **Tube Screamer** ⭐⭐⭐⭐
   - Single effect model
   - High gain saturation
   - Good for testing nonlinearity

### For Production Use
1. **Fender Blackface** - Warm, organic tone
2. **Marshall JCM800** - Classic rock amp
3. **Peavey 5150** - High-gain modern amp
4. **Orange Dark Terror** - Compact tube amp

---

## Model Characteristics to Check

When evaluating a NAM model, check:

| Characteristic | Why It Matters | What to Look For |
|---|---|---|
| **Sample Rate** | Matching system requirements | 44.1k or 48k typical |
| **Latency** | Real-time performance | <10ms acceptable |
| **Input Level** | Signal clipping prevention | Normalized typically -12dB to 0dB |
| **File Size** | Memory footprint | 0.5-10 MB normal |
| **Quality** | Training data quality | Read creator notes |
| **License** | Legal usage rights | Check terms explicitly |

---

## Direct Download Examples (When Available)

### Finding Direct Links
Some models provide direct download links in Tonehunt descriptions:

```
Model: Vox AC30 Brown v1
Creator: [Creator Name]
Download: https://tonehunt.org/models/[id]/download

File info:
- Size: 2.4 MB
- Sample Rate: 48 kHz
- Latency: 6.2 ms
- Training Date: 2024
- License: CC-BY-4.0 (Check creator)
```

---

## Model Testing Strategy

### Phase 1: Load Test
```zig
// Test if model loads without errors
var nam = try NAMLoader.load("path/to/model.nam");
defer nam.deinit();

// Verify metadata
std.debug.print("Model: {s}\n", .{nam.metadata.name});
std.debug.print("Latency: {d} ms\n", .{nam.metadata.latency});
```

### Phase 2: Inference Test
```zig
// Test basic inference
var input_buffer: [512]f32 = undefined;
var output_buffer: [512]f32 = undefined;

try nam.process(&input_buffer, &output_buffer, 512);
// Check output isn't silent, NaN, or clipped
```

### Phase 3: Audio Quality Test
```bash
# Process test signal
ffmpeg -f lavfi -i "sine=1000:d=10" -ar 48000 test_signal.wav
volt_core --effect neural --model model.nam test_signal.wav output.wav

# Compare input/output
audacity test_signal.wav output.wav
```

### Phase 4: Integration Test
```bash
# Test in effect chain
volt_core --config config/neural_test.json input.wav output.wav

# Compare with bypass
volt_core --config config/no_neural.json input.wav output_noeffect.wav
```

---

## Creating a Test Suite

```bash
# Directory structure for testing
samples/nam_models/
├── amps/
│   ├── Vox_AC30_Brown.nam
│   ├── Fender_Blackface.nam
│   └── Marshall_JCM800.nam
├── effects/
│   ├── Tube_Screamer.nam
│   └── Boss_Compression.nam
└── cabinets/
    ├── 1x12_Celestion.nam
    └── 2x12_Greenback.nam

tests/
├── neural_load_test.zig
├── neural_inference_test.zig
├── neural_chain_test.zig
└── fixtures/
    ├── test_sine_1k.wav
    ├── test_guitar.wav
    └── expected_outputs/
```

---

## Tips for Working with NAM Models

### ✅ Best Practices
1. **Verify licensing** before distributing models
2. **Test latency** with your buffer size
3. **Check input levels** (models may have specific input expectations)
4. **Use normalized audio** (-6dB to 0dB typical range)
5. **Monitor CPU usage** in your audio callbacks
6. **Document model sources** for reproducibility

### ⚠️ Common Issues
| Issue | Cause | Solution |
|-------|-------|----------|
| Silent output | Model expects different input level | Adjust gain before effect |
| Distorted output | Input too hot | Reduce input level |
| Crackling/glitching | Buffer size mismatch | Verify ONNX buffer alignment |
| High CPU | Complex model + low buffer size | Increase buffer or use lighter model |
| Phase shift | Network latency | Document and compensate |

---

## Model Licensing Summary

### Common Licenses Encountered
- **CC0**: Public domain, use freely
- **CC-BY-4.0**: Attribute to creator, otherwise free use
- **CC-BY-NC-4.0**: Noncommercial use only
- **Proprietary**: Creator retains all rights
- **Custom**: Check terms explicitly

### Recommendation for volt-core
1. Start with **CC0** or **CC-BY** licensed models for testing
2. Document licensing clearly in model metadata
3. Include attribution in output files if required
4. Obtain explicit permission for proprietary models

---

## Next Steps for Integration

1. ✅ **Find & download a test model** (Vox AC30 recommended)
2. ⏳ **Create NAM loader module** (parse .nam file format)
3. ⏳ **Implement ONNX inference** (process audio)
4. ⏳ **Integrate with effect chain** (add to processing pipeline)
5. ⏳ **Test with real audio** (verify quality)

---

## Quick Start Command

Once you have a .nam file:

```bash
# Create samples directory
mkdir -p samples/nam_models/amps

# Place your downloaded model here
# Then in future: volt-core --effect neural --model samples/nam_models/amps/model.nam input.wav output.wav
```

---

**Last Updated**: December 2025  
**Status**: Ready for model acquisition & testing
