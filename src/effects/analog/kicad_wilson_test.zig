const std = @import("std");

// Minimal KiCAD parser test
// This file demonstrates parsing the WilsonFuzz circuit

const KiCADTokenizer = struct {
    content: []const u8,
    pos: usize = 0,

    fn peek(self: *const KiCADTokenizer) ?u8 {
        if (self.pos >= self.content.len) return null;
        return self.content[self.pos];
    }

    fn advance(self: *KiCADTokenizer) void {
        if (self.pos < self.content.len) self.pos += 1;
    }

    fn skipWhitespace(self: *KiCADTokenizer) void {
        while (self.peek()) |ch| {
            if (ch == ' ' or ch == '\n' or ch == '\r' or ch == '\t') {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn readString(self: *KiCADTokenizer, allocator: std.mem.Allocator) !?[]u8 {
        self.skipWhitespace();

        if (self.peek() != '"') return null;
        self.advance(); // skip opening quote

        var result = std.ArrayList(u8).init(allocator);
        while (self.peek()) |ch| {
            if (ch == '"') {
                self.advance(); // skip closing quote
                return result.items;
            }
            try result.append(ch);
            self.advance();
        }
        return null;
    }

    fn readSymbol(self: *KiCADTokenizer, allocator: std.mem.Allocator) !?[]u8 {
        self.skipWhitespace();

        const start = self.pos;
        while (self.peek()) |ch| {
            if (ch == ' ' or ch == '\n' or ch == ')' or ch == '(' or ch == '\t' or ch == '\r') {
                if (self.pos > start) {
                    return allocator.dupe(u8, self.content[start..self.pos]);
                }
                return null;
            }
            self.advance();
        }

        if (self.pos > start) {
            return allocator.dupe(u8, self.content[start..self.pos]);
        }
        return null;
    }
};

const Component = struct {
    reference: []const u8,
    value: []const u8,
    footprint: []const u8,
};

const ComponentList = struct {
    items: []Component,
    len: usize,
    capacity: usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, capacity: usize) !ComponentList {
        const items = try allocator.alloc(Component, capacity);
        return .{
            .items = items,
            .len = 0,
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    fn append(self: *ComponentList, comp: Component) !void {
        if (self.len >= self.capacity) return error.NoSpace;
        self.items[self.len] = comp;
        self.len += 1;
    }

    fn deinit(self: *ComponentList) void {
        self.allocator.free(self.items);
    }

    fn slice(self: ComponentList) []Component {
        return self.items[0..self.len];
    }
};

pub fn parseWilsonFuzz(allocator: std.mem.Allocator, file_path: []const u8) ![]Component {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var components = try ComponentList.init(allocator, 1000);
    defer components.deinit();

    var pos: usize = 0;
    while (pos < content.len) {
        // Find next footprint
        pos = std.mem.indexOf(u8, content[pos..], "(footprint") orelse break;
        pos += 10; // skip "(footprint"

        // Skip whitespace
        while (pos < content.len and (content[pos] == ' ' or content[pos] == '\n' or content[pos] == '\t')) {
            pos += 1;
        }

        // Read footprint string
        if (pos < content.len and content[pos] == '"') {
            pos += 1;
            const footprint_start = pos;
            while (pos < content.len and content[pos] != '"') {
                pos += 1;
            }
            const footprint = content[footprint_start..pos];
            pos += 1; // skip closing quote

            // Now search for Reference and Value properties
            var ref: ?[]const u8 = null;
            var val: ?[]const u8 = null;

            // Find the end of this footprint block (next closing paren at depth 0)
            const footprint_end = std.mem.indexOf(u8, content[pos..], "\n\t)") orelse content.len;

            const footprint_block = content[pos .. pos + footprint_end];

            // Look for Reference property
            if (std.mem.indexOf(u8, footprint_block, "\"Reference\"")) |ref_pos| {
                var ref_search_pos = ref_pos + 11;
                while (ref_search_pos < footprint_block.len and footprint_block[ref_search_pos] != '"') {
                    ref_search_pos += 1;
                }
                if (ref_search_pos < footprint_block.len) {
                    ref_search_pos += 1;
                    const ref_start = ref_search_pos;
                    while (ref_search_pos < footprint_block.len and footprint_block[ref_search_pos] != '"') {
                        ref_search_pos += 1;
                    }
                    ref = try allocator.dupe(u8, footprint_block[ref_start..ref_search_pos]);
                }
            }

            // Look for Value property
            if (std.mem.indexOf(u8, footprint_block, "\"Value\"")) |val_pos| {
                var val_search_pos = val_pos + 7;
                while (val_search_pos < footprint_block.len and footprint_block[val_search_pos] != '"') {
                    val_search_pos += 1;
                }
                if (val_search_pos < footprint_block.len) {
                    val_search_pos += 1;
                    const val_start = val_search_pos;
                    while (val_search_pos < footprint_block.len and footprint_block[val_search_pos] != '"') {
                        val_search_pos += 1;
                    }
                    val = try allocator.dupe(u8, footprint_block[val_start..val_search_pos]);
                }
            }

            if (ref != null and val != null) {
                try components.append(.{
                    .reference = ref.?,
                    .value = val.?,
                    .footprint = try allocator.dupe(u8, footprint),
                });
            }

            pos += footprint_end;
        } else {
            pos += 1;
        }
    }

    return components.slice();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== WilsonFuzz KiCAD Parser Test ===\n", .{});

    const components = try parseWilsonFuzz(allocator, "samples/kicad/WilsonFuzz.kicad_pcb");
    defer {
        for (components) |c| {
            allocator.free(c.reference);
            allocator.free(c.value);
            allocator.free(c.footprint);
        }
    }

    std.debug.print("\nTotal components found: {}\n", .{components.len});

    // Count by type
    var resistor_count: usize = 0;
    var capacitor_count: usize = 0;
    var transistor_count: usize = 0;
    var diode_count: usize = 0;
    var led_count: usize = 0;
    var connector_count: usize = 0;
    var other_count: usize = 0;

    for (components) |comp| {
        if (std.mem.indexOf(u8, comp.footprint, "Resistor") != null) {
            resistor_count += 1;
        } else if (std.mem.indexOf(u8, comp.footprint, "Capacitor") != null) {
            capacitor_count += 1;
        } else if (std.mem.indexOf(u8, comp.footprint, "TO-92") != null or
            std.mem.indexOf(u8, comp.footprint, "BJT") != null or
            std.mem.indexOf(u8, comp.value, "BC") != null)
        {
            transistor_count += 1;
        } else if (std.mem.indexOf(u8, comp.footprint, "Diode") != null) {
            diode_count += 1;
        } else if (std.mem.indexOf(u8, comp.footprint, "LED") != null) {
            led_count += 1;
        } else if (std.mem.indexOf(u8, comp.footprint, "Connector") != null or
            std.mem.indexOf(u8, comp.footprint, "PinHeader") != null)
        {
            connector_count += 1;
        } else {
            other_count += 1;
        }
    }

    std.debug.print("\nComponent Breakdown:\n", .{});
    std.debug.print("  Resistors:  {}\n", .{resistor_count});
    std.debug.print("  Capacitors: {}\n", .{capacitor_count});
    std.debug.print("  Transistors: {}\n", .{transistor_count});
    std.debug.print("  Diodes:     {}\n", .{diode_count});
    std.debug.print("  LEDs:       {}\n", .{led_count});
    std.debug.print("  Connectors: {}\n", .{connector_count});
    std.debug.print("  Other:      {}\n", .{other_count});

    std.debug.print("\n--- First 20 Components ---\n", .{});
    for (components[0..@min(20, components.len)]) |comp| {
        const type_name = if (std.mem.indexOf(u8, comp.footprint, "Resistor") != null) "R" else if (std.mem.indexOf(u8, comp.footprint, "Capacitor") != null) "C" else if (std.mem.indexOf(u8, comp.footprint, "TO-92") != null or std.mem.indexOf(u8, comp.value, "BC") != null) "Q" else if (std.mem.indexOf(u8, comp.footprint, "LED") != null) "D" else if (std.mem.indexOf(u8, comp.footprint, "Connector") != null or std.mem.indexOf(u8, comp.footprint, "PinHeader") != null) "J" else "?";
        std.debug.print("  {s}: {s} = {s}\n", .{ comp.reference, comp.value, type_name });
    }

    // Test specific expectations
    std.debug.print("\n--- Validation Tests ---\n", .{});

    var found_q2 = false;
    var found_c1 = false;
    var found_r1 = false;

    for (components) |comp| {
        if (std.mem.eql(u8, comp.reference, "Q2") and std.mem.eql(u8, comp.value, "BC549")) {
            found_q2 = true;
            std.debug.print("  ✓ Found Q2 (BC549 transistor)\n", .{});
        }
        if (std.mem.eql(u8, comp.reference, "C1")) {
            found_c1 = true;
            std.debug.print("  ✓ Found C1 (capacitor value: {s})\n", .{comp.value});
        }
        if (std.mem.eql(u8, comp.reference, "R1")) {
            found_r1 = true;
            std.debug.print("  ✓ Found R1 (resistor value: {s})\n", .{comp.value});
        }
    }

    if (!found_q2) std.debug.print("  ✗ Q2 not found\n", .{});
    if (!found_c1) std.debug.print("  ✗ C1 not found\n", .{});
    if (!found_r1) std.debug.print("  ✗ R1 not found\n", .{});

    std.debug.print("\n✅ Test completed!\n\n", .{});
}
