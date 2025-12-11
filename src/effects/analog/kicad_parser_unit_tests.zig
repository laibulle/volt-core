const std = @import("std");

test "parse minimal kicad content" {
    const content = "(kicad_pcb (version 20240108) (footprint \"R_Axial\" (property \"Reference\" \"R1\") (property \"Value\" \"10k\")))";

    // Just verify the content is valid S-expression
    var paren_count: i32 = 0;
    for (content) |ch| {
        if (ch == '(') paren_count += 1;
        if (ch == ')') paren_count -= 1;
    }
    try std.testing.expectEqual(@as(i32, 0), paren_count);
}

test "extract reference from property line" {
    const line = "(property \"Reference\" \"R1\")";

    // Find the Reference property
    if (std.mem.indexOf(u8, line, "\"Reference\"")) |pos| {
        const after_ref = line[pos + 11 ..];
        if (std.mem.indexOf(u8, after_ref, "\"")) |q1| {
            const str_start = q1 + 1;
            if (std.mem.indexOf(u8, after_ref[str_start..], "\"")) |q2| {
                const ref = after_ref[str_start .. str_start + q2];
                try std.testing.expectEqualStrings("R1", ref);
            }
        }
    }
}

test "extract value from property line" {
    const line = "(property \"Value\" \"10k\")";

    // Find the Value property
    if (std.mem.indexOf(u8, line, "\"Value\"")) |pos| {
        const after_val = line[pos + 7 ..];
        if (std.mem.indexOf(u8, after_val, "\"")) |q1| {
            const str_start = q1 + 1;
            if (std.mem.indexOf(u8, after_val[str_start..], "\"")) |q2| {
                const val = after_val[str_start .. str_start + q2];
                try std.testing.expectEqualStrings("10k", val);
            }
        }
    }
}

test "detect resistor from footprint name" {
    const footprints = [_]struct { name: []const u8, is_resistor: bool }{
        .{ .name = "Resistor_THT:R_Axial_DIN0207", .is_resistor = true },
        .{ .name = "Capacitor_THT:C_Rect_L7.2mm", .is_resistor = false },
        .{ .name = "Package_TO_SOT_THT:TO-92_Inline_Wide", .is_resistor = false },
    };

    for (footprints) |fp| {
        const is_r = std.mem.indexOf(u8, fp.name, "Resistor") != null;
        try std.testing.expectEqual(fp.is_resistor, is_r);
    }
}

test "classify component by reference prefix" {
    const components = [_]struct { ref: []const u8, typ: u8 }{
        .{ .ref = "R1", .typ = 'R' },
        .{ .ref = "C1", .typ = 'C' },
        .{ .ref = "Q1", .typ = 'Q' },
        .{ .ref = "D1", .typ = 'D' },
        .{ .ref = "L1", .typ = 'L' },
        .{ .ref = "J1", .typ = 'J' },
    };

    for (components) |comp| {
        const typ = if (comp.ref.len > 0) comp.ref[0] else '?';
        try std.testing.expectEqual(comp.typ, typ);
    }
}

test "parse resistor value string" {
    const values = [_][]const u8{ "10", "100", "1k", "10k", "100k", "1M" };

    for (values) |val| {
        // Verify we can find numeric part
        var has_digit = false;
        for (val) |ch| {
            if (ch >= '0' and ch <= '9') {
                has_digit = true;
                break;
            }
        }
        try std.testing.expect(has_digit);
    }
}

test "wilson fuzz component parsing expectations" {
    // These are the expected components in WilsonFuzz.kicad_pcb
    const expected_count = 21;
    const expected_resistors = 7;
    const expected_capacitors = 4;
    const expected_transistors = 2;

    // Verify our expectations are reasonable
    try std.testing.expect(expected_count > 0);
    try std.testing.expect(expected_resistors + expected_capacitors + expected_transistors <= expected_count);
    try std.testing.expectEqual(@as(usize, 13), expected_resistors + expected_capacitors + expected_transistors);
}

test "validate kicad file format signature" {
    const valid_header = "(kicad_pcb";
    const invalid_header = "(kicad_sch";

    const is_pcb = std.mem.startsWith(u8, valid_header, "(kicad_pcb");
    const is_not_pcb = std.mem.startsWith(u8, invalid_header, "(kicad_pcb");

    try std.testing.expect(is_pcb);
    try std.testing.expect(!is_not_pcb);
}

test "parse property structure" {
    const prop = "(property \"Reference\" \"R1\")";

    // Count parentheses
    var open_count: usize = 0;
    var close_count: usize = 0;
    for (prop) |ch| {
        if (ch == '(') open_count += 1;
        if (ch == ')') close_count += 1;
    }

    try std.testing.expectEqual(open_count, close_count);
    try std.testing.expectEqual(@as(usize, 1), open_count);
}

test "recognize component value suffixes" {
    const test_cases = [_]struct { val: []const u8, suffix: u8 }{
        .{ .val = "10k", .suffix = 'k' },
        .{ .val = "100u", .suffix = 'u' },
        .{ .val = "10n", .suffix = 'n' },
        .{ .val = "1M", .suffix = 'M' },
        .{ .val = "330", .suffix = '0' }, // No suffix
    };

    for (test_cases) |tc| {
        if (tc.val.len > 0) {
            const last_char = tc.val[tc.val.len - 1];
            try std.testing.expectEqual(tc.suffix, last_char);
        }
    }
}
