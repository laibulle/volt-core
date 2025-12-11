const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== WilsonFuzz KiCAD Component Parser ===\n\n", .{});

    var file = try std.fs.cwd().openFile("samples/kicad/WilsonFuzz.kicad_pcb", .{});
    defer file.close();

    const stat = try file.stat();
    std.debug.print("File size: {} bytes\n", .{stat.size});

    const content = try file.readToEndAlloc(allocator, 2 * 1024 * 1024);
    defer allocator.free(content);

    // Just do simple scanning
    var footprint_count: usize = 0;
    var pos: usize = 0;

    std.debug.print("Scanning for components...\n\n", .{});

    while (std.mem.indexOf(u8, content[pos..], "(footprint")) |idx| {
        footprint_count += 1;
        pos += idx + 10;

        // Skip to next footprint or end
        if (std.mem.indexOf(u8, content[pos..], "(footprint")) |next_idx| {
            pos += next_idx;
        } else {
            break;
        }
    }

    std.debug.print("Total footprints found: {}\n\n", .{footprint_count});

    // Now do a smarter pass to extract references and values
    std.debug.print("Extracting components...\n\n", .{});

    pos = 0;
    var r_count: usize = 0;
    var c_count: usize = 0;
    var q_count: usize = 0;
    var d_count: usize = 0;
    var l_count: usize = 0;
    var j_count: usize = 0;
    var h_count: usize = 0;

    while (std.mem.indexOf(u8, content[pos..], "(footprint")) |idx| {
        pos += idx;

        // Find the end of this footprint
        var depth: i32 = 1;
        var search_pos = pos + 10;
        while (search_pos < content.len and depth > 0) {
            if (content[search_pos] == '(') depth += 1;
            if (content[search_pos] == ')') depth -= 1;
            search_pos += 1;
        }

        const footprint_end = search_pos;
        const footprint_content = content[pos..footprint_end];

        // Extract reference
        var ref: [32]u8 = undefined;
        var ref_len: usize = 0;
        if (std.mem.indexOf(u8, footprint_content, "\"Reference\"")) |ref_marker| {
            var search = ref_marker + 11;
            while (search < footprint_content.len and footprint_content[search] != '"') {
                search += 1;
            }
            search += 1; // skip opening quote
            const ref_start = search;
            while (search < footprint_content.len and footprint_content[search] != '"') {
                search += 1;
            }
            ref_len = search - ref_start;
            if (ref_len < 32) {
                @memcpy(ref[0..ref_len], footprint_content[ref_start..search]);
            }
        }

        // Extract value
        var value: [64]u8 = undefined;
        var value_len: usize = 0;
        if (std.mem.indexOf(u8, footprint_content, "\"Value\"")) |val_marker| {
            var search = val_marker + 7;
            while (search < footprint_content.len and footprint_content[search] != '"') {
                search += 1;
            }
            search += 1; // skip opening quote
            const val_start = search;
            while (search < footprint_content.len and footprint_content[search] != '"') {
                search += 1;
            }
            value_len = search - val_start;
            if (value_len < 64) {
                @memcpy(value[0..value_len], footprint_content[val_start..search]);
            }
        }

        // Count by first char
        if (ref_len > 0) {
            switch (ref[0]) {
                'R' => r_count += 1,
                'C' => c_count += 1,
                'Q' => q_count += 1,
                'D' => d_count += 1,
                'L' => l_count += 1,
                'J' => j_count += 1,
                'H' => h_count += 1,
                else => {},
            }

            // Print for debugging
            if (r_count + c_count + q_count + d_count <= 20) {
                if (value_len > 0) {
                    std.debug.print("  {s} = {s}\n", .{ ref[0..ref_len], value[0..value_len] });
                } else {
                    std.debug.print("  {s}\n", .{ref[0..ref_len]});
                }
            }
        }

        pos = footprint_end;
    }

    std.debug.print("\n--- Component Summary ---\n", .{});
    std.debug.print("Resistors:      {}\n", .{r_count});
    std.debug.print("Capacitors:     {}\n", .{c_count});
    std.debug.print("Transistors:    {}\n", .{q_count});
    std.debug.print("Diodes:         {}\n", .{d_count});
    std.debug.print("LEDs:           {}\n", .{l_count});
    std.debug.print("Connectors:     {}\n", .{j_count});
    std.debug.print("Mounting Holes: {}\n", .{h_count});

    const total = r_count + c_count + q_count + d_count + l_count + j_count + h_count;
    std.debug.print("Total:          {}\n\n", .{total});

    // Analyze circuit characteristics
    std.debug.print("--- Circuit Analysis ---\n", .{});
    if (q_count >= 2) {
        std.debug.print("✓ Multi-transistor circuit (fuzz/distortion likely)\n", .{});
    }
    if (c_count >= 5) {
        std.debug.print("✓ Heavy capacitor usage (likely audio coupling/filtering)\n", .{});
    }
    if (r_count >= 10) {
        std.debug.print("✓ Complex resistor network\n", .{});
    }

    std.debug.print("\n✅ Parser test completed!\n\n", .{});
}
