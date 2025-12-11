# WaveNet Neural Network Implementation for NAM Models

## Overview
Neural Amp Modeler (NAM) files contain WaveNet-based models that perform audio modeling through dilated causal convolutions.

## WaveNet Architecture (From NAM Analysis)

### Structure
```
Input (audio sample) → Layer 1 → Layer 2 → Output (processed sample)

Where each layer contains:
- Dilated causal convolution
- Activation function (Tanh)
- Residual connections (optional)
- Gating mechanism (optional)
```

### From JCM 800.nam Example
```
Layer 1:
  - input_size: 1 (mono audio)
  - channels: 16
  - kernel_size: 3
  - dilations: [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]
  - activation: Tanh

Layer 2:
  - input_size: 16 (output of layer 1)
  - channels: 8
  - kernel_size: 3
  - dilations: [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]
  - activation: Tanh
```

## Key Inference Concepts

### Dilated Convolution
Process: `output[i] = activation(sum(weight[j] * input[i - dilation * j]))`
- **Receptive field**: Grows exponentially with dilation
- **Causal**: Only uses past samples (no future information)
- **Efficient**: Processes one sample at a time

### Implementation Options

#### Option A: Sample-by-sample Processing (Real-time Friendly)
```zig
pub fn processAudioSampleByS ample(self: *WaveNetInference, input: f32) f32 {
    var output = input;
    // For each layer
    for (self.layers) |layer| {
        output = layer.process(output);
    }
    return output;
}
```

**Pros:**
- Can handle real-time audio streaming
- Memory efficient (stateful)
- No buffering needed

**Cons:**
- Requires maintaining history buffer per layer
- More complex state management
- Multiple calls overhead

#### Option B: Block Processing
```zig
pub fn processAudioBlock(self: *WaveNetInference, input: []f32, output: []f32) void {
    // Process entire block at once
    for (input, 0..) |sample, i| {
        output[i] = self.processSample(sample);
    }
}
```

**Pros:**
- Simpler implementation
- Better cache locality
- Cleaner state management

**Cons:**
- Not ideal for very long blocks
- Memory usage proportional to block size

### Weights Layout
- Model has one flattened array of weights
- Weights are stored in specific order: typically layer by layer
- Need to parse configuration to know weight indices for each layer

### Implementation Steps

1. **State Management**
   - Allocate history buffer for each layer (size = max_dilation * kernel_size)
   - Initialize with zeros

2. **Layer Processing**
   - For each time step:
     - Apply dilated convolution across all dilations
     - Apply activation function
     - Update history

3. **Audio Normalization**
   - Apply input gain before network
   - Apply output gain after network
   - Handle loudness normalization if needed

## Simplified First Implementation

For the prototype, focus on:
1. Single sample processing
2. Assume 1-channel audio (mono)
3. Use pre-parsed weights from NAM JSON
4. Simple Tanh activation
5. No gating or residual connections yet

```zig
pub const WaveNetInference = struct {
    allocator: std.mem.Allocator,
    model: nam_parser.NAMModel,
    
    // State buffers for each layer
    layer_histories: [][]f32,
    
    pub fn init(allocator, model) !WaveNetInference
    pub fn processSample(self, input: f32) f32
    pub fn processBlock(self, input: []f32, output: []f32) void
    pub fn deinit(self)
}
```

## Quick Validation Ideas
1. Process known signal (sine wave)
2. Check output is not all zeros
3. Verify gain/loudness applied correctly
4. Compare against expected output range

## Limitations of Initial Implementation
- Single input/output channel only
- No proper weight distribution/buffering
- No residual connections
- No gating
- Simplified state management
- Block processing only (not streaming-safe initially)

## Future Optimizations
- SIMD for convolution operations
- Parallel layer processing
- Multi-channel support
- Streaming state management
- Proper weight precomputation
- Fast approximations for Tanh
