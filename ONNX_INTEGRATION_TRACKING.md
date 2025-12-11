# ONNX Runtime Integration Progress

## Summary
Implementing proper neural amp modeling using ONNX Runtime for inference on trained NAM models.

## Completed Tasks
- [x] ONNX Runtime 1.22.2 installed via Homebrew on macOS
- [x] Build system updated (build.zig) to link ONNX Runtime library
- [x] Include paths configured for both macOS and Linux
- [x] Created `onnx_inference.zig` module skeleton
- [x] Created `nam_parser.zig` module skeleton  
- [x] Updated `neural_effect.zig` to initialize ONNX engine
- [x] Code compiles and runs without errors
- [x] Git tracking initiated with commit

## In Progress Tasks
1. **Full ONNX C API Bindings** (Medium complexity)
   - Current: Basic module structure
   - Needed: Complete ONNX Runtime C API wrapper
   - Reference: `/opt/homebrew/opt/onnxruntime/include/onnxruntime_c_api.h`
   - Approach: Create minimal C bindings for model loading and inference

2. **NAM JSON Parser** (Medium complexity)
   - Current: Placeholder
   - Needed: Parse NAM JSON to extract:
     - Model metadata (name, gain, loudness, sample_rate)
     - Neural network architecture (layers, activation functions)
     - Model weights and biases
     - Input/output normalization parameters

3. **ONNX Model Loading** (Complex)
   - Current: Placeholder
   - Needed: Load ONNX model from NAM file
   - Challenge: NAM files are JSON, ONNX expects binary model format
   - Solution: Extract embedded ONNX model or convert to ONNX format

## Pending Tasks
- [ ] Implement full ONNX session creation with proper error handling
- [ ] Create tensor input/output wrappers for audio data
- [ ] Implement inference pipeline with batch processing
- [ ] Handle model input/output normalization
- [ ] Add support for different sample rates (resample if needed)
- [ ] Performance optimization (cache sessions, avoid allocations)
- [ ] Error handling and fallback to pass-through on inference failure
- [ ] Support for multiple NAM model formats and architectures

## Technical Details

### ONNX Runtime Paths (macOS)
- Library: `/opt/homebrew/opt/onnxruntime/lib/libonnxruntime.dylib`
- Headers: `/opt/homebrew/opt/onnxruntime/include/`
- Include `onnxruntime_c_api.h` for C bindings

### NAM File Format
- Format: JSON with embedded neural network data
- Contains:
  - `metadata`: Model info (name, creator, date, gear_type, tone_type)
  - `training`: Training parameters and settings
  - `model`: Serialized neural network weights

### Current Flow
1. `initFromFile()` loads NAM metadata and initializes ONNX engine
2. `processNeuralModel()` calls ONNX inference (currently pass-through)
3. `deinit()` cleans up ONNX resources

### Next Implementation Step
Create minimal ONNX C bindings for:
```zig
const c = @cImport({
    @cInclude("onnxruntime_c_api.h");
});

// Create environment
c.OrtCreateEnv(...)

// Create session
c.OrtCreateSession(...)

// Run inference
c.OrtRun(...)
```

## Files Modified
- `build.zig` - Added ONNX Runtime linking
- `src/effects/neural/neural_effect.zig` - Integrated ONNX initialization
- `src/effects/neural/onnx_inference.zig` - NEW: ONNX engine wrapper
- `src/effects/neural/nam_parser.zig` - NEW: NAM parser (placeholder)

## Testing Status
- ✅ Builds successfully
- ✅ Runs without crashing
- ✅ Currently pass-through (no actual processing)
- ❌ No actual neural inference yet

## Notes
- The implementation is honest about current limitations
- Placeholder ONNX inference uses pass-through while infrastructure is built
- This prevents fake/artificial DSP tricks from fooling users
- Focus is on proper foundation for future real inference
