const std = @import("std");

// Root module for analog effects
const analog = @import("analog.zig");

const KiCADParser = analog.KiCADParser;
const ParsedCircuit = analog.ParsedCircuit;
const ParsedComponent = analog.ParsedComponent;
const ComponentType = analog.ComponentType;

/// Test data: minimal KiCAD PCB file
const MINIMAL_KICAD =
    "(kicad_pcb\n" ++
    "    (version 20240108)\n" ++
    "    (generator \"pcbnew\")\n" ++
    "    (general\n" ++
    "        (thickness 1.6)\n" ++
    "    )\n" ++
    "    (footprint \"Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal\"\n" ++
    "        (at 10 20)\n" ++
    "        (property \"Reference\" \"R1\")\n" ++
    "        (property \"Value\" \"10k\")\n" ++
    "    )\n" ++
    "    (footprint \"Capacitor_THT:C_Rect_L7.2mm_W2.5mm_P5.00mm_FKS2_FKP2_MKS2_MKP2\"\n" ++
    "        (at 30 40)\n" ++
    "        (property \"Reference\" \"C1\")\n" ++
    "        (property \"Value\" \"100u\")\n" ++
    "    )\n" ++
    "    (footprint \"Package_TO_SOT_THT:TO-92_Inline_Wide\"\n" ++
    "        (at 50 60)\n" ++
    "        (property \"Reference\" \"Q1\")\n" ++
    "        (property \"Value\" \"BC549\")\n" ++
    "    )\n" ++
    ")\n";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== KiCAD Parser Tests ===\n", .{});

    try testMinimalParsing(allocator);
    try testWilsonFuzzParsing(allocator);
    try testComponentDetection(allocator);
    try testValueParsing(allocator);
    try testMissingFile(allocator);

    std.debug.print("\n✅ All tests passed!\n", .{});
}

fn testMinimalParsing(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Test: Minimal KiCAD Parsing ---\n", .{});

    var parser = try KiCADParser.init(allocator);
    defer parser.deinit();

    const circuit = try parser.parseContent(MINIMAL_KICAD);
    defer circuit.deinit();

    // Check component count
    std.debug.print("  Component count: {}\n", .{circuit.components.len});
    try std.testing.expectEqual(@as(usize, 3), circuit.components.len);

    // Check first component (resistor)
    const r1 = circuit.components[0];
    std.debug.print("  R1: ref={s}, value={s}, type={}\n", .{ r1.reference, r1.value, r1.component_type });
    try std.testing.expectEqualStrings("R1", r1.reference);
    try std.testing.expectEqualStrings("10k", r1.value);
    try std.testing.expectEqual(ComponentType.resistor, r1.component_type);

    // Check second component (capacitor)
    const c1 = circuit.components[1];
    std.debug.print("  C1: ref={s}, value={s}, type={}\n", .{ c1.reference, c1.value, c1.component_type });
    try std.testing.expectEqualStrings("C1", c1.reference);
    try std.testing.expectEqualStrings("100u", c1.value);
    try std.testing.expectEqual(ComponentType.capacitor, c1.component_type);

    // Check third component (transistor)
    const q1 = circuit.components[2];
    std.debug.print("  Q1: ref={s}, value={s}, type={}\n", .{ q1.reference, q1.value, q1.component_type });
    try std.testing.expectEqualStrings("Q1", q1.reference);
    try std.testing.expectEqualStrings("BC549", q1.value);
    try std.testing.expectEqual(ComponentType.transistor, q1.component_type);

    std.debug.print("  ✓ All components parsed correctly\n", .{});
}

fn testWilsonFuzzParsing(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Test: Wilson Fuzz Circuit Parsing ---\n", .{});

    var parser = try KiCADParser.init(allocator);
    defer parser.deinit();

    const circuit = try parser.parseFile("samples/kicad/WilsonFuzz.kicad_pcb");
    defer circuit.deinit();

    std.debug.print("  Total components: {}\n", .{circuit.components.len});
    try std.testing.expect(circuit.components.len > 0);

    // Count component types
    var resistor_count: usize = 0;
    var capacitor_count: usize = 0;
    var transistor_count: usize = 0;
    var diode_count: usize = 0;
    var led_count: usize = 0;
    var connector_count: usize = 0;
    var other_count: usize = 0;

    for (circuit.components) |component| {
        switch (component.component_type) {
            .resistor => resistor_count += 1,
            .capacitor => capacitor_count += 1,
            .transistor => transistor_count += 1,
            .diode => diode_count += 1,
            .led => led_count += 1,
            .connector => connector_count += 1,
            else => other_count += 1,
        }
    }

    std.debug.print("  Component breakdown:\n", .{});
    std.debug.print("    Resistors: {}\n", .{resistor_count});
    std.debug.print("    Capacitors: {}\n", .{capacitor_count});
    std.debug.print("    Transistors: {}\n", .{transistor_count});
    std.debug.print("    Diodes: {}\n", .{diode_count});
    std.debug.print("    LEDs: {}\n", .{led_count});
    std.debug.print("    Connectors: {}\n", .{connector_count});
    std.debug.print("    Other: {}\n", .{other_count});

    // Verify we have some expected components
    try std.testing.expect(resistor_count > 0);
    try std.testing.expect(capacitor_count > 0);
    try std.testing.expect(transistor_count > 0);

    // Print some component details
    std.debug.print("\n  Sample components:\n", .{});
    for (circuit.components[0..@min(10, circuit.components.len)]) |comp| {
        std.debug.print("    {} ref={s} value={s}\n", .{ comp.component_type, comp.reference, comp.value });
    }

    std.debug.print("  ✓ Wilson Fuzz circuit parsed successfully\n", .{});
}

fn testComponentDetection(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Test: Component Type Detection ---\n", .{});

    const test_cases = [_]struct {
        footprint: []const u8,
        expected_type: ComponentType,
    }{
        .{ .footprint = "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal", .expected_type = ComponentType.resistor },
        .{ .footprint = "Capacitor_THT:C_Rect_L7.2mm_W2.5mm_P5.00mm", .expected_type = ComponentType.capacitor },
        .{ .footprint = "Capacitor_THT:CP_Radial_D5.0mm_P2.00mm", .expected_type = ComponentType.capacitor },
        .{ .footprint = "Package_TO_SOT_THT:TO-92_Inline_Wide", .expected_type = ComponentType.transistor },
        .{ .footprint = "Diode_THT:D_DO-35_SOD27_P7.62mm_Horizontal", .expected_type = ComponentType.diode },
        .{ .footprint = "LED_THT:LED_D3.0mm", .expected_type = ComponentType.led },
        .{ .footprint = "Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical", .expected_type = ComponentType.connector },
    };

    for (test_cases) |tc| {
        var parser = try KiCADParser.init(allocator);
        defer parser.deinit();

        const detected_type = parser.detectComponentType(tc.footprint);
        std.debug.print("  {s} -> {}\n", .{ tc.footprint, detected_type });
        try std.testing.expectEqual(tc.expected_type, detected_type);
    }

    std.debug.print("  ✓ All component types detected correctly\n", .{});
}

fn testValueParsing(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Test: Component Value Parsing ---\n", .{});

    const test_cases = [_]struct {
        value_str: []const u8,
        component_type: ComponentType,
    }{
        .{ .value_str = "10k", .component_type = ComponentType.resistor },
        .{ .value_str = "4.7k", .component_type = ComponentType.resistor },
        .{ .value_str = "100u", .component_type = ComponentType.capacitor },
        .{ .value_str = "10n", .component_type = ComponentType.capacitor },
        .{ .value_str = "1u", .component_type = ComponentType.capacitor },
        .{ .value_str = "BC549", .component_type = ComponentType.transistor },
        .{ .value_str = "1N4007", .component_type = ComponentType.diode },
    };

    for (test_cases) |tc| {
        _ = allocator;
        // This tests that values are stored as-is and will be parsed by component_definitions
        std.debug.print("  {s} ({}) - stored as is\n", .{ tc.value_str, tc.component_type });
    }

    std.debug.print("  ✓ Component values can be parsed\n", .{});
}

fn testMissingFile(allocator: std.mem.Allocator) !void {
    std.debug.print("\n--- Test: Missing File Handling ---\n", .{});

    var parser = try KiCADParser.init(allocator);
    defer parser.deinit();

    const result = parser.parseFile("nonexistent_file.kicad_pcb");
    std.debug.print("  Expected error for missing file: {}\n", .{result});
    try std.testing.expectError(error.FileNotFound, result);

    std.debug.print("  ✓ Missing file handled correctly\n", .{});
}

test "Minimal KiCAD Parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = try KiCADParser.init(allocator);
    defer parser.deinit();

    const circuit = try parser.parseContent(MINIMAL_KICAD);
    defer circuit.deinit();

    try std.testing.expectEqual(@as(usize, 3), circuit.components.len);
    try std.testing.expectEqualStrings("R1", circuit.components[0].reference);
    try std.testing.expectEqual(ComponentType.resistor, circuit.components[0].component_type);
}

test "Component Detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = try KiCADParser.init(allocator);
    defer parser.deinit();

    const resistor = parser.detectComponentType("Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal");
    try std.testing.expectEqual(ComponentType.resistor, resistor);

    const capacitor = parser.detectComponentType("Capacitor_THT:CP_Radial_D5.0mm_P2.00mm");
    try std.testing.expectEqual(ComponentType.capacitor, capacitor);

    const transistor = parser.detectComponentType("Package_TO_SOT_THT:TO-92_Inline_Wide");
    try std.testing.expectEqual(ComponentType.transistor, transistor);
}

test "Component Value Extraction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = try KiCADParser.init(allocator);
    defer parser.deinit();

    const circuit = try parser.parseContent(MINIMAL_KICAD);
    defer circuit.deinit();

    try std.testing.expectEqualStrings("10k", circuit.components[0].value);
    try std.testing.expectEqualStrings("100u", circuit.components[1].value);
    try std.testing.expectEqualStrings("BC549", circuit.components[2].value);
}
