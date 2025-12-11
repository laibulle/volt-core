const std = @import("std");
const circuit_format = @import("circuit_format.zig");

const InternalCircuit = circuit_format.InternalCircuit;
const RuntimeComponent = circuit_format.RuntimeComponent;
const RuntimeNode = circuit_format.RuntimeNode;
const ComponentKind = circuit_format.ComponentKind;

/// Serialize a circuit to JSON format
pub fn circuitToJson(allocator: std.mem.Allocator, circuit: *const InternalCircuit) ![]const u8 {
    // Simple JSON builder without ArrayList
    var parts: [1024][]const u8 = undefined;
    var part_count: usize = 0;

    // Start JSON
    parts[part_count] = "{\"name\":\"";
    part_count += 1;
    parts[part_count] = circuit.name;
    part_count += 1;
    parts[part_count] = "\",\"nodes\":[";
    part_count += 1;

    // Add nodes
    for (circuit.nodes, 0..) |node, i| {
        if (i > 0) {
            parts[part_count] = ",";
            part_count += 1;
        }
        parts[part_count] = "{\"id\":\"";
        part_count += 1;
        parts[part_count] = node.id;
        part_count += 1;
        parts[part_count] = "\",\"voltage\":";
        part_count += 1;
        // Would need to format the float here - for now skip voltage
        parts[part_count] = "0}";
        part_count += 1;
    }

    parts[part_count] = "],\"components\":[";
    part_count += 1;

    // Add components
    for (circuit.components, 0..) |comp, i| {
        if (i > 0) {
            parts[part_count] = ",";
            part_count += 1;
        }
        parts[part_count] = "{\"type\":\"";
        part_count += 1;
        parts[part_count] = componentKindToString(comp.kind);
        part_count += 1;
        parts[part_count] = "\",\"from\":";
        part_count += 1;
        // Would need to format numbers - skip for now
        parts[part_count] = "0,\"to\":0,\"value\":";
        part_count += 1;
        parts[part_count] = "0}";
        part_count += 1;
    }

    parts[part_count] = "]}";
    part_count += 1;

    return try std.mem.join(allocator, "", parts[0..part_count]);
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
