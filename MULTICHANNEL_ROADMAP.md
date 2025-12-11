# Multi-Channel WaveNet Implementation Roadmap

## Current State
- Single-channel inference (scalar input → scalar through all layers → scalar output)
- Per-sample processing works correctly for single output
- Weight indexing properly maps to layer configurations

## Multi-Channel Challenge

### Problem Statement
NAM WaveNet models use multi-channel layers:
```
Input: 1 channel
↓
Layer 0: 1 → 16 channels (6 dilations × 2 kernel = 12 weights per output channel)
↓
Layer 1: 16 → 8 channels (expects 16 input channels)
↓
Output: Depends on layer configuration (likely 1-8 channels)
```

### Current Limitation
We pass a scalar through all layers:
```zig
var processed = sample * gain * loudness;
for (layers) |layer| {
    processed = try processLayer(processed);  // ← Only one value!
}
output[i] = processed;
```

### Required Changes

#### 1. Inference Loop Refactoring
Need to track all channels at each layer:
```zig
// Pseudo-code
var layer_inputs = [1]f32 { sample };
for (layers, 0..) |layer, layer_idx| {
    var layer_outputs = [layer.channels]f32;
    for (0..layer.channels) |out_ch| {
        layer_outputs[out_ch] = try processLayer(..., out_ch);
    }
    layer_inputs = layer_outputs;  // Next layer's input
}
output[i] = layer_inputs[0];  // or average/mix all outputs
```

#### 2. ProcessLayer Signature Change
Current:
```zig
fn processLayer(layer_idx: usize, input: f32, layer: LayerConfig) f32
```

Needed:
```zig
fn processLayer(
    layer_idx: usize,
    layer_input_channels: []f32,  // All channels from prev layer
    output_channel: usize,         // Which output channel to compute
    layer: LayerConfig
) f32
```

#### 3. Weight Index Calculation
Current weight indexing assumes single output:
```zig
weight_idx = layer_offset + (dil_idx * kernel * channels) + (k * channels)
```

Needs to include:
- Which output channel
- Which input channel
- Proper multi-dimensional array indexing

#### 4. History Buffer Expansion
Current:
```zig
self.layer_histories.?[layer_idx] = []f32  // Single history
```

Needed:
```zig
self.layer_histories.?[layer_idx] = [][]f32  // [out_channel][history]
// AND also track input histories for looking up previous layer outputs
```

## Implementation Strategy

### Phase 1: Layer Output Buffers ✅
- Create `LayerOutput` struct to hold per-channel outputs
- Modify inference loop to allocate intermediate buffers

### Phase 2: Multi-Channel History (In Progress)
- Replace `layer_histories: ?[][]f32` with `LayerHistory` array
- Each `LayerHistory` maintains `[channels][history_len]` buffer
- Update shift operations to work per-channel

### Phase 3: Process Layer Refactor
- Change signature to accept input channels array
- Iterate over output channels
- For each output channel, iterate over input channels + dilations + kernels
- Proper 3D weight indexing: `[layer][out_ch * in_ch + in_ch][dil_kernel]`

### Phase 4: Integration & Testing
- Verify output quality with multi-channel models
- Test audio characteristics against reference implementations
- Performance profiling

## Weight Memory Layout in NAM Files

Assuming weights are stored as:
```
For each layer:
  For each dilation:
    For each output channel:
      For each kernel position:
        For each input channel:
          weight_value
```

Or flattened as:
```
layer_offset + 
(dilation_idx * kernel_size * output_channels * input_channels) +
(output_channel_idx * kernel_size * input_channels) +
(kernel_idx * input_channels) +
input_channel_idx
```

**Need to verify**: Actual layout from NAM file format documentation

## Testing Approach

1. **Unit Tests**: Test `processLayer` with known weights and inputs
2. **Model Validation**: Compare against neural-network reference implementation
3. **Audio Quality**: Measure ESR (Error-to-Signal Ratio) against expected values
4. **Multi-Model Testing**: Try with different NAM models

## Backward Compatibility

Maintain current single-channel interface while supporting multi-channel internally:
```zig
// Users still call:
try engine.infer(input_samples, output_samples);

// But internally it handles multi-channel flow and mixes output
```

## Key Decisions Made

1. **Keep wrapper interface simple**: Single input/output channels from user perspective
2. **Use intermediate buffers**: Don't try to fuse operations, keep it modular
3. **Lazy implementation**: Add multi-channel support when output quality validation requires it

## Related Files to Modify

1. `src/effects/neural/onnx_inference.zig`
   - `WaveNetInference` struct
   - `loadModel()` function
   - `infer()` main inference loop
   - `processLayer()` function

2. `src/effects/neural/nam_parser.zig`
   - May need to understand weight layout better

3. `src/effects/neural/neural_effect.zig`
   - Might need adjustment for multi-channel handling

## References & Notes

- **Receptive Field**: Max dilation × kernel size determines how far back we look
- **Causal Constraint**: Can only use samples from current and past time steps
- **Channel Count**: Determined by layer configuration in NAM file
- **Weight Sharing**: Different layers have different channel counts; weights aren't shared between layers
