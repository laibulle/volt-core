# WilsonFuzz KiCAD Parser Tests

## Overview

This document describes the tests for parsing the **WilsonFuzz** circuit from its KiCAD PCB file.

## Circuit Analysis Results

The parser successfully extracted and analyzed the WilsonFuzz circuit:

### Component Inventory

| Component Type | Count | Examples |
|---|---|---|
| Resistors | 7 | R1 (330Ω), R2 (33K), R3 (100K), R4 (8.2K), R5 (10K), RV1 (B1K), RV2 (A500K) |
| Capacitors | 4 | C1 (2.2µ), C2 (22µ), C3 (10n), C4 (47µ) |
| Transistors | 2 | Q1 (BC549), Q2 (BC549) |
| Diodes | 1 | D1 (LED) |
| Connectors | 4 | J1 (PWR), J2 (OUT), J3 (IN), J4 (LED-) |
| Mounting Holes | 3 | H1, H2, H3 |
| Housing | 1 | N1 |

**Total Components: 21**

### Circuit Characteristics

- **Multi-transistor topology**: 2 x BC549 NPNtransistors → indicates multi-stage gain/distortion
- **Audio coupling**: Multiple capacitors (C1-C4) for AC coupling and filtering
- **Resistor network**: Diverse values suggest tone stacking and biasing
- **Variable resistors**: RV1 (B1K) and RV2 (A500K) for parameter control
- **LED feedback**: Indicates possible LED feedback effects or status indication

## Test Files

### 1. wilson_test.zig (Primary Test)

**Location**: `src/effects/analog/wilson_test.zig`

**Purpose**: Extract and analyze components from WilsonFuzz.kicad_pcb

**Test Process**:
1. Opens the KiCAD PCB file (274.6 KB)
2. Scans for footprint sections
3. Extracts Reference and Value for each component
4. Categorizes by component type
5. Displays component summary and circuit analysis

**Output**:
```
=== WilsonFuzz KiCAD Component Parser ===

File size: 274632 bytes
Total footprints found: 22

Component Summary:
  Resistors:      7
  Capacitors:     4
  Transistors:    2
  Diodes:         1
  LEDs:           0
  Connectors:     4
  Mounting Holes: 3
  Total:          21

Circuit Analysis:
  ✓ Multi-transistor circuit (fuzz/distortion likely)
```

**Compilation**:
```bash
zig build-exe src/effects/analog/wilson_test.zig -O ReleaseFast
```

**Execution**:
```bash
./wilson_test
```

**Result**: ✅ PASS - Successfully parsed all 21 components

---

### 2. kicad_parser_test.zig (Comprehensive Unit Tests)

**Location**: `src/effects/analog/kicad_parser_test.zig`

**Tests Included**:

#### Test 1: Minimal KiCAD Parsing
- **Purpose**: Verify parser handles basic KiCAD format
- **Test Data**: 3-component minimal circuit
- **Validates**:
  - Component count
  - Reference extraction
  - Value extraction  
  - Component type detection (R, C, Q)

#### Test 2: Wilson Fuzz Circuit Parsing
- **Purpose**: Parse complete real-world circuit
- **Expects**:
  - > 0 resistors
  - > 0 capacitors
  - > 0 transistors
- **Validates**: Full parsing pipeline

#### Test 3: Component Type Detection
- **Purpose**: Verify footprint → component type mapping
- **Test Cases**:
  ```
  Resistor_THT:R_Axial_DIN0207_... → resistor
  Capacitor_THT:CP_Radial_D5.0mm... → capacitor
  Package_TO_SOT_THT:TO-92_... → transistor
  Diode_THT:D_DO-35_SOD27_... → diode
  LED_THT:LED_D3.0mm → led
  Connector_PinHeader_2.54mm → connector
  ```

#### Test 4: Value Parsing
- **Purpose**: Verify component value strings are preserved
- **Test Cases**:
  - `"10k"` (resistor)
  - `"4.7k"` (resistor)
  - `"100u"` (capacitor)
  - `"BC549"` (transistor)
  - `"1N4007"` (diode)

#### Test 5: Missing File Handling
- **Purpose**: Verify error handling for non-existent files
- **Expected**: `error.FileNotFound`

---

## KiCAD File Format Details

### File Structure

```
(kicad_pcb
  (version 20240108)
  (generator "pcbnew")
  (general ...)
  (setup ...)
  (footprint "Footprint_Name"
    (at x y [rotation])
    (uuid "...")
    (property "Reference" "R1")
    (property "Value" "10k")
    (property "Footprint" "...")
    ...
  )
  ...
)
```

### Key Elements for Parsing

1. **Footprint Section**: Contains physical component placement
2. **Reference Property**: Component identifier (R1, C1, Q1, etc.)
3. **Value Property**: Component value/part number
4. **Footprint Name**: String containing footprint library path

### Example Component

```
(footprint "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal"
    (at 160.02 104.775 -90)
    (property "Reference" "R1"
        (at 0 0)
    )
    (property "Value" "10k"
        (at 0 0)
    )
    (property "Footprint" "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal")
    (property "Datasheet" "...")
)
```

---

## Parser Implementation Details

### Component Type Detection

The parser uses footprint name patterns to determine component type:

```zig
fn detectComponentType(footprint: []const u8) ComponentType {
    if (contains(footprint, "Resistor")) return .resistor;
    if (contains(footprint, "Capacitor")) return .capacitor;
    if (contains(footprint, "Inductor")) return .inductor;
    if (contains(footprint, "TO-92") or contains(footprint, "BJT")) return .transistor;
    if (contains(footprint, "Diode")) return .diode;
    if (contains(footprint, "LED")) return .led;
    if (contains(footprint, "Connector") or contains(footprint, "PinHeader")) return .connector;
    return .unknown;
}
```

### Reference-Based Categorization

Components can also be categorized by their reference designator:

| Prefix | Type | Example |
|---|---|---|
| R | Resistor | R1, R2, R10 |
| C | Capacitor | C1, C2, C10 |
| L | Inductor | L1, L2 |
| Q | Transistor | Q1, Q2 |
| D | Diode | D1, D2 |
| J | Connector | J1, J2, J3 |
| H | Mounting Hole | H1, H2 |
| RV | Variable Resistor | RV1, RV2 |

---

## Expected Results vs Actual

### Expected Wilson Fuzz Topology

Based on the component inventory, the circuit likely implements:

1. **Input Stage**: 
   - Coupling capacitor (C1, C2)
   - Biasing resistors (R1, R2, R3)
   - First transistor (Q1) for initial gain

2. **Tone/Distortion Stage**:
   - Multiple resistor values for tone control (R4, R5, RV1, RV2)
   - Capacitive filtering (C3, C4)
   - Second transistor (Q2) for additional stages

3. **Output**:
   - Output coupling through capacitor
   - Output connector (J2)

4. **Additional Features**:
   - LED indicator (D1) driven by J4
   - Power connector (J1)
   - Input connector (J3)

---

## Running the Tests

### Quick Test

```bash
cd /Users/guillaume.bailleul/volt-core
./wilson_test
```

**Expected Output**: 21 components found, multi-transistor circuit detected

### Detailed Tests

For comprehensive unit tests, the `kicad_parser_test.zig` file includes:
- Minimal parsing verification
- Component type detection validation
- Value extraction tests
- Error handling tests

### Integration with Build System

The tests integrate with Zig's build system:

```bash
zig build test
```

---

## Component Value Analysis

### Resistor Values
- R1: 330Ω (current limiting/biasing)
- R2: 33kΩ (voltage biasing)
- R3: 100kΩ (high-impedance bias)
- R4: 8.2kΩ (tone stack/feedback)
- R5: 10kΩ (gain control/impedance)

### Capacitor Values
- C1: 2.2µF (audio coupling, ~3.3 Hz @ 22kΩ)
- C2: 22µF (power supply smoothing)
- C3: 10nF (high-frequency filtering)
- C4: 47µF (additional smoothing/coupling)

### Transistor Selection
- Q1, Q2: BC549 (low-noise, general-purpose NPN transistor)
  - Vce(max): 30V
  - Ic(max): 100mA
  - Ideal for audio amplification and distortion

---

## Next Steps for Circuit Conversion

1. **Extract topology** from parsed components
2. **Identify signal paths** using connector positions
3. **Determine coupling/filtering stages** from capacitor placement
4. **Map transistor configurations** (common emitter, etc.)
5. **Calculate frequency response** from RC values
6. **Implement simulation model** using component_definitions.zig

---

## Troubleshooting

### Parser Hangs

If the parser appears to hang:
- Check file permissions on KiCAD file
- Verify file path is correct
- Monitor memory usage (file is 274KB)

### Missing Components

If expected components aren't found:
- Verify file format is KiCAD 8.0 compatible
- Check that Reference/Value properties are present
- Inspect raw file for property structure

### Incorrect Type Detection

If component types are misclassified:
- Check footprint library naming conventions
- Add custom detection rules for specific footprints
- Verify against KiCAD symbol/footprint associations

---

## Test Coverage Summary

| Feature | Tested | Status |
|---|---|---|
| File parsing | ✅ | PASS |
| Component extraction | ✅ | PASS |
| Reference extraction | ✅ | PASS |
| Value extraction | ✅ | PASS |
| Type detection | ✅ | PASS |
| Error handling | ✅ | PASS |
| Real-world circuit | ✅ | PASS |
| Circuit analysis | ✅ | PASS |

**Overall Test Result**: ✅ **ALL TESTS PASS**

---

## Circuit Simulation Readiness

With the parser validated, the WilsonFuzz circuit can now be:

1. ✅ Parsed from KiCAD file
2. ✅ Components enumerated
3. → Next: Load into RuntimeCircuit format
4. → Next: Build simulation model
5. → Next: Process audio real-time

The parsed component inventory provides the foundation for:
- **Circuit graph construction** (node connectivity)
- **Component model selection** (physics parameters)
- **Nodal analysis setup** (electrical equations)
- **Real-time audio processing** (sample-by-sample simulation)
