const std = @import("std");
const circuit_format = @import("circuit_format.zig");

const InternalCircuit = circuit_format.InternalCircuit;
const RuntimeComponent = circuit_format.RuntimeComponent;
const RuntimeNode = circuit_format.RuntimeNode;
const ComponentKind = circuit_format.ComponentKind;

/// Serialize a circuit to JSON format  - simplified stub
pub fn circuitToJson(allocator: std.mem.Allocator, circuit: *const InternalCircuit) ![]const u8 {
    _ = circuit;
    // Simplified implementation - returns valid empty JSON for now
    const json = "{\"name\": \"parsed_circuit\", \"nodes\": [], \"components\": []}";
    return try allocator.dupe(u8, json);
}

/// Convert ComponentKind to string
fn componentKindToString(kind: ComponentKind) []const u8 {
    return switch (kind) {
        .resistor => "resistor",
        .capacitor => "capacitor",
        .inductor => "inductor",
        .diode => "diode",
        .opamp => "opamp",
        .transistor => "transistor",
    };
}

/// Parse ComponentKind from string
pub fn stringToComponentKind(str: []const u8) ?ComponentKind {
    return if (std.mem.eql(u8, str, "resistor"))
        .resistor
    else if (std.mem.eql(u8, str, "capacitor"))
        .capacitor
    else if (std.mem.eql(u8, str, "inductor"))
        .inductor
    else if (std.mem.eql(u8, str, "diode"))
        .diode
    else if (std.mem.eql(u8, str, "opamp"))
        .opamp
    else if (std.mem.eql(u8, str, "transistor"))
        .transistor
    else
        null;
}
