const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== WilsonFuzz KiCAD Parser Test ===\n\n", .{});

    var file = try std.fs.cwd().openFile("samples/kicad/WilsonFuzz.kicad_pcb", .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Count footprints
    var count: usize = 0;
    var pos: usize = 0;
    var components = std.ArrayList(struct { reference: []const u8, value: []const u8 }).init(allocator);
    defer components.deinit();

    std.debug.print("Scanning file for components...\n", .{});

    while (pos < content.len) {
        // Find next footprint
        pos = std.mem.indexOf(u8, content[pos..], "(footprint") orelse break;
        pos += 10; // skip "(footprint"
        count += 1;

        // Skip to property section
        const property_start = pos;
        const property_section = content[property_start .. std.mem.indexOf(u8, content[property_start..], "\n\t)") orelse content.len];

        // Find Reference
        var ref: ?[]const u8 = null;
        var val: ?[]const u8 = null;

        var line_pos: usize = 0;
        while (line_pos < property_section.len) {
            const line_end = std.mem.indexOf(u8, property_section[line_pos..], "\n") orelse property_section.len - line_pos;
            const line = property_section[line_pos .. line_pos + line_end];

            if (std.mem.indexOf(u8, line, "\"Reference\"") != null) {
                if (std.mem.indexOf(u8, line, "\"Reference\"")) |ref_marker| {
                    const after_ref = line[ref_marker + 11 ..];
                    if (std.mem.indexOf(u8, after_ref, "\"")) |q1| {
                        const str_start = q1 + 1;
                        if (str_start < after_ref.len) {
                            if (std.mem.indexOf(u8, after_ref[str_start..], "\"")) |q2| {
                                ref = try allocator.dupe(u8, after_ref[str_start .. str_start + q2]);
                            }
                        }
                    }
                }
            }

            if (std.mem.indexOf(u8, line, "\"Value\"") != null) {
                if (std.mem.indexOf(u8, line, "\"Value\"")) |val_marker| {
                    const after_val = line[val_marker + 7 ..];
                    if (std.mem.indexOf(u8, after_val, "\"")) |q1| {
                        const str_start = q1 + 1;
                        if (str_start < after_val.len) {
                            if (std.mem.indexOf(u8, after_val[str_start..], "\"")) |q2| {
                                val = try allocator.dupe(u8, after_val[str_start .. str_start + q2]);
                            }
                        }
                    }
                }
            }

            line_pos += line_end + 1;
        }

        if (ref != null and val != null) {
            try components.append(.{ .reference = ref.?, .value = val.? });
        }

        pos += property_section.len + 1;
    }

    std.debug.print("\nTotal components found: {}\n\n", .{count});

    // Group by reference prefix
    var resistor_count: usize = 0;
    var capacitor_count: usize = 0;
    var transistor_count: usize = 0;
    var diode_count: usize = 0;
    var led_count: usize = 0;
    var connector_count: usize = 0;
    var mounting_hole_count: usize = 0;
    var other_count: usize = 0;

    for (components.items) |comp| {
        const first_char = if (comp.reference.len > 0) comp.reference[0] else '?';
        switch (first_char) {
            'R' => resistor_count += 1,
            'C' => capacitor_count += 1,
            'Q' => transistor_count += 1,
            'D' => diode_count += 1,
            'L' => led_count += 1,
            'J' => connector_count += 1,
            'H' => mounting_hole_count += 1,
            else => other_count += 1,
        }
    }

    std.debug.print("Component Breakdown:\n", .{});
    std.debug.print("  Resistors:      {}\n", .{resistor_count});
    std.debug.print("  Capacitors:     {}\n", .{capacitor_count});
    std.debug.print("  Transistors:    {}\n", .{transistor_count});
    std.debug.print("  Diodes:         {}\n", .{diode_count});
    std.debug.print("  LEDs:           {}\n", .{led_count});
    std.debug.print("  Connectors:     {}\n", .{connector_count});
    std.debug.print("  Mounting Holes: {}\n", .{mounting_hole_count});
    std.debug.print("  Other:          {}\n", .{other_count});

    std.debug.print("\n--- First 30 Components ---\n", .{});
    const limit = @min(30, components.items.len);
    for (components.items[0..limit]) |comp| {
        std.debug.print("  {s:4s} = {s}\n", .{ comp.reference, comp.value });
    }

    std.debug.print("\n--- Specific Component Tests ---\n", .{});
    var found_tests = [_]struct { ref: []const u8, value: []const u8, found: bool }{
        .{ .ref = "Q2", .value = "BC549", .found = false },
        .{ .ref = "C1", .value = "", .found = false },
        .{ .ref = "R1", .value = "", .found = false },
        .{ .ref = "L1", .value = "", .found = false },
    };

    for (components.items) |comp| {
        for (&found_tests) |*test_case| {
            if (std.mem.eql(u8, comp.reference, test_case.ref)) {
                test_case.found = true;
            }
        }
    }

    for (found_tests) |t| {
        if (t.found) {
            std.debug.print("  ✓ Found component {s}\n", .{t.ref});
        } else {
            std.debug.print("  ✗ Component {s} not found\n", .{t.ref});
        }
    }

    std.debug.print("\n✅ Parser test completed!\n\n", .{});
}
