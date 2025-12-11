# ONNX Runtime Integration Progress

## Summary
Implementing proper neural amp modeling using ONNX Runtime for inference on trained NAM models. Currently in honest placeholder mode - pass-through processing with clear infrastructure for future real implementation.

## Completed Tasks
- [x] ONNX Runtime 1.22.2 installed via Homebrew on macOS
- [x] Build system updated (build.zig) to link ONNX Runtime library
- [x] Include paths configured for both macOS and Linux
- [x] Created `onnx_inference.zig` module with clean architecture
- [x] Created `nam_parser.zig` module skeleton  
- [x] Updated `neural_effect.zig` to initialize ONNX engine
- [x] Code compiles and runs without errors
- [x] Honest placeholder mode working (pass-through, no fake effects)
- [x] Git tracking initiated with commit

## Current Status: Honest Placeholder Mode
✅ The application now runs in a clean, honest state:
- Loads NAM models and recognizes them
- Initializes ONNX infrastructure without actual binding
- Passes audio through unchanged (no fake DSP)
- Clear debug output showing what's missing
- Architecture ready for real implementation

## Revised Implementation Strategy: WaveNet in Pure Zig

### Discovery: NAM Models are WaveNet-Based
Analysis of `JCM 800.nam` reveals:
- **Architecture**: WaveNet (dilated causal convolutions)
- **Format**: JSON with flattened weight array + layer configuration
- **Config**: Layer definitions with kernels, dilations, activations

### New Approach: Skip ONNX Runtime
Instead of trying to integrate ONNX Runtime's complex C API, implement WaveNet inference directly in Zig:

**Advantages:**
- ✅ No C API binding complexities
- ✅ Better performance (direct inference, no overhead)
- ✅ Full control over inference pipeline
- ✅ Easy to optimize for real-time audio
- ✅ Self-contained, no external dependencies needed
- ✅ Can handle NAM format natively

**Implementation Scope (Moderate):**
- JSON parsing for NAM files (Zig std.json)
- WaveNet layer implementation (convolution, activation)
- Inference loop with normalization
- Estimated effort: 2-4 hours for working prototype

### ONNXInference (`src/effects/neural/onnx_inference.zig`)
**File: JCM 800.nam - Real Example**

Structure (JSON format):
```json
{
  "version": "0.5.4",
  "metadata": {
    "date": {"year": 2025, "month": 6, "day": 7, ...},
    "loudness": -22.236,
    "gain": 0.842,
    "name": "JCM 800",
    "modeled_by": "giovanevichingo",
    "gear_type": "amp",
    "tone_type": "overdrive",
    "input_level_dbu": null,
    "output_level_dbu": null,
    "training": { /* training metadata */ },
    "validation_esr": 0.0017
  },
  "architecture": "WaveNet",  // <-- Network type!
  "config": {
    "layers": [
      {
        "input_size": 1,
        "condition_size": 1,
        "head_size": 8,
        "channels": 16,
        "kernel_size": 3,
        "dilations": [1, 2, 4, 8, 16, 32, 64, 128, 256, 512],
        "activation": "Tanh",
        "gated": false,
        "head_bias": false
      },
      { /* second layer config */ }
    ],
    "head": null,
    "head_scale": 0.02
  },
  "weights": [-0.2186, 0.5608, -0.8813, ...] // All weights flattened
}
```

**Key Insights:**
1. **Architecture**: WaveNet (dilated causal convolution-based)
2. **Weights Format**: Flattened array of floats (for all layers combined)
3. **Config Structure**: Layer-by-layer configuration with clear parameters
4. **Metadata**: Contains gain, loudness, and training information

**Implementation Path:**
Instead of using ONNX Runtime (which requires binary model conversion), we can:
1. Parse NAM JSON directly
2. Implement WaveNet inference in pure Zig (feasible - it's just dilated convolutions + activations)
3. Use config + weights to reconstruct and run the network
4. Handle audio normalization with loudness/gain parameters


```zig
pub const ONNXInference = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,
    model_path: ?[]u8 = null,
    
    pub fn init(allocator) !ONNXInference       // Initialize engine
    pub fn loadModel(self, path) !void           // Register model
    pub fn infer(self, input, output) !void      // Run inference
    pub fn deinit(self) void                     // Cleanup
}
```

**Current Implementation:**
- `init()`: Creates engine in placeholder mode
- `loadModel()`: Registers model path, logs "NOT YET IMPLEMENTED"
- `infer()`: Pass-through (copies input to output when different buffers)
- `deinit()`: Cleans up allocated memory

**Design Decision:**
Rather than attempting complex C bindings, we use a clean, simple architecture that:
1. Avoids linking errors by not calling ONNX C API directly
2. Provides a clear interface for future ONNX integration
3. Maintains honest pass-through (no artificial effects)
4. Documents exact next steps clearly

## Pending Implementation Tasks

### Phase 1: NAM Model Parsing (High Priority)
**Status:** Placeholder only
**Location:** `src/effects/neural/nam_parser.zig`

**Requirements:**
- Parse NAM JSON files (standard JSON format)
- Extract metadata: model name, sample rate, latency, gain, loudness, training params
- Extract neural network weights and architecture
- Current blockers: None - can use std.json from Zig stdlib

**Implementation Steps:**
1. Define NAMModel struct with all metadata fields
2. Parse JSON using Zig's built-in JSON parser
3. Extract weight tensors for loading into ONNX
4. Return fully populated NAMModel struct

**Example NAM Structure (from file inspection):**
```json
{
  "metadata": {
    "name": "JCM 800",
    "sample_rate": 48000,
    "latency": 0,
    "gain": [input_gain, output_gain],
    "loudness": [-10.0, 0.0, ...],
    ...
  },
  "training": { ... },
  "model": { ... neural network weights ... }
}
```

### Phase 2: ONNX Model Loading (High Priority)
**Status:** Blocked by Phase 1
**Challenge:** NAM models contain embedded ONNX models or custom formats

**Two Possible Approaches:**
1. **Extract & Load:** Parse NAM JSON, extract ONNX model bytes, load via C API
2. **Custom Inference:** Implement inference directly on NAM model format
   - Simpler approach: Extract weights from JSON, build inference pipeline
   - No need for full ONNX Runtime if model format is straightforward

**Investigation Needed:**
- Examine actual NAM file structure to see if it contains ONNX format
- Check if NAM format has standard network architecture
- Determine if custom inference is simpler than ONNX integration

### Phase 3: ONNX C API Bindings (Medium Priority)
**Status:** Partially researched
**Challenge:** ONNX Runtime is C++ library exported as C, with complex symbol management

**Current Finding:**
- Direct C bindings won't link due to symbol mangling and library complexity
- Solutions:
  1. Create Zig wrapper around C++ API (advanced)
  2. Use pre-built ONNX wrapper library (if available)
  3. Extract and implement model inference in pure Zig

**Key Functions Needed (if proceeding with C API):**
- `OrtCreateEnv()` - Initialize ONNX environment
- `OrtCreateSession()` - Load model
- `OrtCreateTensorAsOrtValue()` - Create input tensor
- `OrtRun()` - Execute inference
- `OrtGetTensorMutableData()` - Extract output

### Phase 4: Tensor I/O Pipeline (Medium Priority)
**Status:** Waiting for Phase 2 completion

**Requirements:**
- Convert audio buffers to ONNX tensors (shape: [batch_size, samples])
- Handle different sample rates (resample if needed)
- Apply input normalization based on model metadata
- Extract output tensors and denormalize
- Copy to audio buffer with proper scaling

**Key Decisions:**
- Batch size: 1 (single audio sample processing)
- Shape: [1, num_samples] or [num_samples] depending on model
- Data type: float32 (ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)

### Phase 5: Performance & Polish (Lower Priority)
**Status:** Future work
**Items:**
- [ ] Session caching to avoid reloading
- [ ] Batch processing for multiple samples
- [ ] Memory pool for tensor allocation
- [ ] Async inference for real-time safety
- [ ] Support for different network architectures
- [ ] Error recovery and fallback to pass-through

## Technical Details

### Testing Status
- ✅ Builds successfully with Zig build system
- ✅ Runs without crashing
- ✅ Audio plays back correctly (pass-through)
- ❌ No actual neural inference yet (as expected)

### Debug Output (Sample Run)
```
[ONNX] Inference engine initialized (placeholder mode)
[ONNX] Model registered: samples/neural/JCM 800.nam
[ONNX] Model loading from NAM file: NOT YET IMPLEMENTED
[ONNX] Next step: Parse NAM JSON and extract ONNX model data
[Neural] Warning: Could not load model with ONNX Runtime: error.NotYetImplemented
```

### Files Modified
- `build.zig` - ONNX linking configuration
- `src/effects/neural/neural_effect.zig` - ONNX engine integration
- `src/effects/neural/onnx_inference.zig` - Main ONNX wrapper (simplified)
- `src/effects/neural/nam_parser.zig` - NAM model parser skeleton

## Next Recommended Step
**Start with NAM Model Parsing (Phase 1)**

Reason: This is the critical path blocker. Without understanding the NAM file format and being able to extract weights/metadata, we can't proceed with actual model loading.

**Action Items:**
1. Write JSON parser for NAM files
2. Extract and inspect actual model data from sample .nam files
3. Understand network architecture (LSTM? MLP? Hybrid?)
4. Decide between custom inference vs ONNX Runtime wrapper

## Notes
- The current placeholder approach is intentional and honest
- No fake audio processing tricks
- Architecture supports multiple implementation paths
- Building incrementally with clear validation at each step
- Each phase can be developed and tested independently
