# Neural Amp Modeler (NAM) Integration Plan

## Executive Summary

Neural Amp Modeler is an open-source deep learning technology that uses trained neural networks to capture and recreate the complex audio characteristics of guitar amplifiers and audio equipment. This document outlines the integration strategy for volt-core.

---

## 1. What is Neural Amp Modeler?

### Overview
- **Purpose**: Use deep learning to digitally model guitar amplifiers and audio equipment
- **Creator**: Steven Atkinson and community contributors
- **License**: Open-source (MIT or similar permissive licenses)
- **Core Capability**: Captures nonlinear audio behavior (saturation, compression, frequency-dependent effects) that traditional DSP struggles with

### Key Differentiators vs. Traditional Amp Modeling
| Feature | NAM | Traditional DSP |
|---------|-----|-----------------|
| Nonlinear modeling | Excellent | Limited |
| Model capture time | Minutes-hours | Weeks-months |
| Accuracy | High (trained to data) | Good (algorithmic) |
| CPU cost | Moderate-high | Low |
| Interpretability | "Black box" | Transparent |
| Flexibility | High (any device) | Limited to built-in models |

---

## 2. How Neural Amp Modeler Works

### Technology Stack

**Architecture:**
- Recurrent Neural Networks (RNNs) / Long Short-Term Memory (LSTM) networks
- Gated Recurrent Units (GRUs) for optimized inference
- Convolutional layers for feature extraction
- Hybrid approach: Neural network + traditional convolution

**Training Process:**
```
1. Record diverse input signals across frequency/amplitude range
2. Capture physical device output for each input
3. Train neural network to learn input → output mapping
4. Validate on held-out test data
5. Quantize for real-time inference (int8 weights, float32 activations)
6. Serialize to .nam format
```

**Inference Pipeline:**
```
Audio Input → Normalization → Neural Network → Denormalization → Audio Output
                             (trained weights)
```

### Performance Characteristics
- **Latency**: <10ms typical (real-time suitable)
- **Real-time factor**: 1000x-10000x faster than real-time
- **CPU usage**: 5-15% of modern CPU core per instance
- **Model size**: 0.5-10 MB per model
- **Memory overhead**: 50-100 MB per instance

---

## 3. File Formats & Model Structure

### Primary Format: `.nam` Files

**Structure:**
```
NAM Binary Archive
├── Metadata Section
│   ├── Version number
│   ├── Model name/description
│   ├── Creator/training info
│   ├── Creation date
│   └── Architecture type identifier
├── Normalization Parameters
│   ├── Input scale/offset
│   ├── Output scale/offset
│   └── Preprocessing information
├── Network Architecture
│   ├── Layer definitions
│   ├── Activation functions
│   ├── Connection topology
│   └── Layer sizes
├── Model Weights (Quantized)
│   ├── Layer parameters (int8/float32)
│   ├── Biases
│   └── Layer-specific configuration
└── Optional Sections
    ├── Training hyperparameters
    ├── Loss metrics
    └── Validation statistics
```

### Secondary Formats
- **ONNX** (.onnx): Open Neural Network Exchange (recommended for portability)
- **PyTorch** (.pt, .pth): Native training format
- **TensorFlow** (.pb, .h5): Alternative framework
- **JSON**: Architecture and metadata
- **WAV/MP3**: Training and example audio

### Technical Specifications
- **Input sample rate**: 44.1 kHz, 48 kHz (resampling supported)
- **Output sample rate**: Same as input
- **Precision**: Mixed precision (int8 weights, float32 compute)
- **Typical latency**: 0-20ms depending on buffer size
- **Real-time performance**: 1000x+ faster than real-time

---

## 4. Integration Strategy for volt-core

### Architecture Overview

```
Audio Input
    ↓
[Effect Chain Processing]
    ├─ Distortions
    ├─ Analog Circuits (existing)
    ├─ Neural Effect (NEW)
    │   ├─ Load .nam Model
    │   ├─ Normalize Input
    │   ├─ Run ONNX Inference
    │   └─ Denormalize Output
    └─ Convolver
    ↓
Audio Output
```

### Implementation Approach

#### Phase 1: Core Infrastructure (Foundation)
1. **Add ONNX Runtime dependency**
   - Link against ONNX Runtime C++ library
   - Add to `build.zig.zon`
   - Handle cross-platform (macOS/Linux/Windows)

2. **Create NAM loader module**
   - Parse .nam model files
   - Extract metadata, weights, architecture
   - Handle ONNX model format

3. **Build inference engine**
   - Audio buffer interface
   - Real-time processing callbacks
   - Sample rate handling
   - Latency management

#### Phase 2: Effect Integration (Feature)
1. **Create `neural_effect.zig` module**
   - Implement NeuralEffect struct with effect chain interface
   - Process method compatible with existing effect pipeline
   - Configuration parameters (model path, bypass, etc.)

2. **Update effect chain**
   - Register neural effect in effect chain
   - Add to JSON config schema
   - Support model hot-swapping

3. **JSON Configuration**
   - Extend chain config format to support neural effects
   - Example:
     ```json
     {
       "effects": [
         {
           "type": "neural",
           "enabled": true,
           "model": "models/amp_model.nam",
           "sampleRate": 48000,
           "normalize": true
         }
       ]
     }
     ```

#### Phase 3: Plugin Architecture (Distribution)
1. **VST/AU wrapper**
   - Use JUCE framework (optional, for plugin distribution)
   - Wrap neural effect for DAW integration

2. **Standalone application**
   - CLI support: `volt-core --effect neural --model path/to/model.nam input.wav output.wav`
   - Real-time processing in existing audio driver

### File Structure
```
src/effects/neural/
├── neural_effect.zig          # Main effect module
├── nam_loader.zig             # .nam file parser
├── onnx_inference.zig         # ONNX Runtime wrapper
├── neural_config.zig          # Configuration handling
├── neural_test.zig            # Unit tests
└── README.md                  # Documentation
```

---

## 5. Technical Requirements

### Dependencies

**For Inference (C++):**
- ONNX Runtime C++ (v1.16+)
  - Size: ~25 MB
  - Platforms: macOS, Linux, Windows, iOS, Android
  - No training libraries needed

**For Zig Integration:**
- Zig compiler bindings to ONNX Runtime C API
- C interop layer for model loading/inference

**Optional Dependencies:**
- `samples/neural/` directory for pre-trained models
- Test models for unit testing

### Memory & Performance

| Metric | Value |
|--------|-------|
| Per-instance memory | 50-100 MB |
| Model file size | 0.5-10 MB |
| CPU usage (single core) | 5-15% |
| Typical latency | 5-10 ms |
| Model load time | 50-500 ms |
| Inference time (48k sample) | 0.1-1 ms |

### Platform Support
- ✅ macOS (Intel & Apple Silicon)
- ✅ Linux
- ✅ Windows
- ⚠️ iOS/Android (requires ONNX Runtime Mobile)

---

## 6. Model Training & Distribution

### Training Workflow
```
Physical Amplifier
    ↓
[Audio Recording Setup]
├─ Record amplifier output with various inputs
├─ Capture clean signal, gain structure, frequency response
└─ Generate training dataset (1-10 GB)
    ↓
[NAM Training Script (Python)]
├─ Train neural network on input/output pairs
├─ Validate model on held-out data
├─ Quantize for inference
└─ Export to .nam format
    ↓
[Trained Model (.nam file)]
└─ Ready for distribution/integration
```

### Model Sources
- **Official NAM Models**: Available from NAM project (various amps)
- **Community Models**: Growing ecosystem of user-created models
- **Custom Models**: Train your own for proprietary designs
- **Licensing**: Variable per model (check creator terms)

### Example Models to Test With
- Tube amp models (vintage warmth)
- Solid-state models (high gain)
- Cabinet simulation models
- Pedal/effect models

---

## 7. Integration Roadmap

### Week 1-2: Research & Setup
- [ ] Evaluate ONNX Runtime integration
- [ ] Obtain sample .nam model files for testing
- [ ] Create Zig bindings to ONNX Runtime C API
- [ ] Set up build configuration

### Week 3-4: Core Implementation
- [ ] Implement NAM loader module
- [ ] Build ONNX inference engine
- [ ] Create audio buffer interface
- [ ] Unit tests for inference accuracy

### Week 5-6: Effect Integration
- [ ] Integrate with existing effect chain
- [ ] Extend JSON config format
- [ ] Add neural effect to effect selection menu
- [ ] Integration tests with other effects

### Week 7-8: Polish & Documentation
- [ ] Performance optimization
- [ ] Error handling & edge cases
- [ ] Documentation & examples
- [ ] Sample configurations
- [ ] Plugin wrapper (if distributing)

---

## 8. Licensing Considerations

### NAM Framework
- **License**: Open-source (MIT/permissive)
- **Attribution**: Required in derivative works
- **Commercial use**: Permitted
- **Redistribution**: Allowed with proper attribution

### Trained Models (.nam files)
- **Ownership**: Creator retains copyright
- **Licensing**: Varies per model (CC0, CC-BY, proprietary, etc.)
- **Amp manufacturers**: Gray legal area for unauthorized modeling
- **User models**: Creator-specific licensing

### volt-core Integration
- Document NAM as open-source dependency
- Include license attribution in releases
- Clearly mark model licensing on distributed models
- Allow users to provide their own models

---

## 9. Known Limitations & Mitigations

| Limitation | Impact | Mitigation |
|-----------|--------|-----------|
| Requires training data | Can't model devices without recordings | Focus on publicly available models initially |
| Black-box model | Hard to understand learned behavior | Document model specifications and A/B test results |
| Generalization limits | May not extrapolate beyond training | Recommend appropriate input levels/frequencies |
| CPU cost | Higher than traditional effects | Optimize quantization; offer quality presets |
| Phase shift | May introduce latency artifacts | Monitor phase coherence; document latency specs |
| Model interpretability | Can't tweak internal parameters | Provide model selection/blending instead |

---

## 10. Success Metrics

### Implementation Success
- ✅ Load and process .nam files in real-time (<10ms latency)
- ✅ Integrate seamlessly with existing effect chain
- ✅ CPU usage <20% on single modern CPU core
- ✅ Maintain audio quality with no artifacts

### User Success
- ✅ Easy model discovery and loading
- ✅ Transparent latency/performance characteristics
- ✅ Clear documentation on model usage
- ✅ Community contributions of custom models

### Integration Success
- ✅ No breaking changes to existing effects
- ✅ JSON configuration consistency
- ✅ Cross-platform compatibility verified
- ✅ Unit test coverage >85%

---

## 11. References & Resources

### Official Resources
- NAM Project: https://www.neuralampmodeler.com/
- GitHub: https://github.com/sdatkinson/neural-amp-modeler
- Documentation: NAM project wiki and community forums

### ONNX Runtime
- ONNX Runtime: https://onnxruntime.ai/
- C++ API Reference: https://onnxruntime.ai/docs/api/c/

### Community & Models
- Model sharing platforms (Tonehunt, etc.)
- Audio engineering forums
- GitHub communities

---

## 12. Next Steps

1. **Immediate**: Review this plan with team; gather feedback
2. **Week 1**: Obtain sample .nam model files; evaluate ONNX Runtime integration
3. **Week 2**: Create proof-of-concept (load model, run inference)
4. **Week 3-4**: Full implementation following roadmap
5. **Week 5+**: Integration, testing, documentation

---

## Appendix: Comparison with Existing Effects

### Current volt-core Effects
- **Analog**: Circuit simulation (physics-based)
- **Distortions**: Algorithmic distortion types
- **Convolver**: Impulse response convolution

### Neural Effect Advantages
| vs. Analog | vs. Distortions | vs. Convolver |
|-----------|-----------------|---------------|
| Captures nonlinearities that analog circuits miss | Models complex saturation and frequency response | Combines amplitude and frequency effects |
| Doesn't require circuit parameters | More flexible/less preset-based | Learns from real device behavior |
| One file = complete model | Flexible parameter tuning | Single model covers amp + cabinet + effects |

### Integration Value
- Complements existing effects (use together in chain)
- Provides high-fidelity amp/device modeling
- Expands volt-core capabilities to cutting-edge ML audio tech
- Appeals to engineers wanting neural modeling workflows

---

**Document Version**: 1.0  
**Date**: December 2025  
**Status**: Approved for Implementation
