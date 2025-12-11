#!/bin/bash
# Test script for Neural Amp Modeler integration

set -e

echo "════════════════════════════════════════════════════════════════"
echo "Neural Amp Modeler - Orange Amp Test"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Build the project
echo "[1/4] Building volt-core..."
zig build

echo ""
echo "[2/4] Checking NAM model file..."
MODEL_FILE="samples/neural/Orange Amp_ Flat EQ, Gain 6, AKG 414 + sm57.nam"
if [ -f "$MODEL_FILE" ]; then
    FILE_SIZE=$(stat -f%z "$MODEL_FILE")
    echo "✓ Found model: $MODEL_FILE"
    echo "  File size: $((FILE_SIZE / 1024)) KB"
else
    echo "✗ Model file not found: $MODEL_FILE"
    exit 1
fi

echo ""
echo "[3/4] Checking JSON configuration..."
CONFIG_FILE="config/neural_orange_amp.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "✓ Found config: $CONFIG_FILE"
    echo ""
    echo "Configuration content:"
    cat "$CONFIG_FILE"
else
    echo "✗ Config file not found: $CONFIG_FILE"
    exit 1
fi

echo ""
echo "[4/4] Testing neural effect loading..."
# Create a simple test to load the chain configuration
./zig-out/bin/volt_core --chain "$CONFIG_FILE" 2>&1 | head -50

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Test Complete!"
echo "════════════════════════════════════════════════════════════════"
