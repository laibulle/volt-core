const std = @import("std");
const volt_core = @import("volt_core");

/// Parse a component value string (e.g., "10k", "100n") to a float
fn parseComponentValue(value_str: []const u8) !f32 {
    var buf: [64]u8 = undefined;

    // Convert to lowercase for easier processing
    for (value_str, 0..) |c, i| {
        if (i < buf.len) {
            buf[i] = std.ascii.toLower(c);
        }
    }

    const lower = std.mem.trim(u8, buf[0..value_str.len], " ");

    // Parse numeric prefix
    var num_end: usize = 0;
    while (num_end < lower.len and (std.ascii.isDigit(lower[num_end]) or lower[num_end] == '.')) {
        num_end += 1;
    }

    if (num_end == 0) return 1.0;

    const num_part = lower[0..num_end];
    const base_value = try std.fmt.parseFloat(f32, num_part);

    // Parse multiplier suffix
    if (num_end >= lower.len) return base_value;

    const multiplier: f32 = switch (lower[num_end]) {
        'p' => 1e-12,
        'n' => 1e-9,
        'u' => 1e-6,
        'm' => 1e-3,
        'k' => 1e3,
        'g' => 1e9,
        else => 1.0,
    };

    return base_value * multiplier;
}

/// Parse a KiCAD file and save intermediate circuit format as JSON
fn handleParseCommand(allocator: std.mem.Allocator, cli_args: volt_core.cli.CliArgs) !void {
    const kicad_file = cli_args.kicad_file orelse {
        std.debug.print("Error: KiCAD file path required\n", .{});
        return volt_core.cli.CliError.MissingArgumentValue;
    };

    const output_file = cli_args.output_file orelse {
        std.debug.print("Error: Output JSON file path required\n", .{});
        return volt_core.cli.CliError.MissingArgumentValue;
    };

    std.debug.print("Parsing KiCAD file: {s}\n", .{kicad_file});

    // Load KiCAD file
    const file = std.fs.cwd().openFile(kicad_file, .{}) catch |err| {
        std.debug.print("Error opening KiCAD file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    // For now, create a simple circuit without deep parsing
    // The circuit format is initialized but empty
    var circuit = try volt_core.analog.circuit_format.InternalCircuit.init(allocator, "parsed_circuit", 0, 0);
    defer circuit.deinit();

    std.debug.print("  Created circuit structure\n", .{});

    // Convert to JSON
    const json = try volt_core.analog.circuit_json.circuitToJson(allocator, &circuit);
    defer allocator.free(json);

    // Write JSON to output file
    const out_file = try std.fs.cwd().createFile(output_file, .{});
    defer out_file.close();

    try out_file.writeAll(json);

    std.debug.print("✅ Saved intermediate format to: {s}\n", .{output_file});
    std.debug.print("   File size: {d} bytes\n", .{json.len});
}

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse CLI arguments
    const cli_args = volt_core.cli.parse(allocator, args) catch |err| {
        std.debug.print("Failed to parse arguments: {}\n", .{err});
        return err;
    };

    // Handle parse command
    if (cli_args.command == .parse) {
        return try handleParseCommand(allocator, cli_args);
    }

    // Handle sample command
    if (cli_args.command == .sample) {
        const sample_path = cli_args.sample_name orelse {
            std.debug.print("Error: Sample file path required\n", .{});
            return volt_core.cli.CliError.MissingArgumentValue;
        };

        // Validate that chain configuration is provided
        if (cli_args.chain_config_file == null) {
            volt_core.cli.printMissingChainError();
            return volt_core.cli.CliError.MissingChainConfiguration;
        }

        std.debug.print("Volt Core - Sample Test Player\n", .{});
        std.debug.print("================================\n\n", .{});

        // Load effect chain configuration (required)
        std.debug.print("Loading effect chain from: {s}\n", .{cli_args.chain_config_file.?});

        const file = std.fs.cwd().openFile(cli_args.chain_config_file.?, .{}) catch |err| {
            std.debug.print("Error opening chain config file: {}\n", .{err});
            return err;
        };
        defer file.close();

        const json_content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(json_content);

        var chain = volt_core.chain_config.initChainFromJson(allocator, json_content) catch |err| {
            std.debug.print("Error parsing chain config: {}\n", .{err});
            return err;
        };
        defer chain.deinit();

        try volt_core.chain_config.printChainConfig(&chain);

        // Load and process sample
        const loader = volt_core.wav_loader.WAVLoader.init(allocator);
        std.debug.print("Loading sample: {s}\n", .{sample_path});

        var audio_buffer = loader.loadFile(sample_path) catch |err| {
            std.debug.print("Error loading sample file: {}\n", .{err});
            return err;
        };
        defer audio_buffer.deinit(allocator);

        std.debug.print("✓ Loaded: {d} samples at {d}Hz ({d} channels)\n", .{
            audio_buffer.samples.len / audio_buffer.channel_count,
            audio_buffer.sample_rate,
            audio_buffer.channel_count,
        });

        // Apply configured effect chain
        std.debug.print("✓ Applying effect chain ({d} effects)...\n", .{chain.effectCount()});
        chain.processBuffer(&audio_buffer);

        // Play the processed audio
        var player = try volt_core.audio_player.AudioPlayer.init(allocator);
        defer player.deinit();

        std.debug.print("✓ Starting playback...\n\n", .{});
        try player.playBuffer(
            audio_buffer.samples.ptr,
            audio_buffer.samples.len / audio_buffer.channel_count,
            audio_buffer.sample_rate,
            audio_buffer.channel_count,
        );

        std.debug.print("✓ Playback complete!\n", .{});
        return;
    }

    // Only run command reaches here
    std.debug.print("Volt Core - Real-time Guitar Effects Player\n", .{});
    std.debug.print("============================================\n\n", .{});

    // Validate that chain configuration is provided
    if (cli_args.chain_config_file == null) {
        volt_core.cli.printMissingChainError();
        return volt_core.cli.CliError.MissingChainConfiguration;
    }

    // Load effect chain configuration (required)
    std.debug.print("Loading effect chain from: {s}\n", .{cli_args.chain_config_file.?});

    const file = std.fs.cwd().openFile(cli_args.chain_config_file.?, .{}) catch |err| {
        std.debug.print("Error opening chain config file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const json_content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(json_content);

    var chain = volt_core.chain_config.initChainFromJson(allocator, json_content) catch |err| {
        std.debug.print("Error parsing chain config: {}\n", .{err});
        return err;
    };
    defer chain.deinit();

    try volt_core.chain_config.printChainConfig(&chain);

    // Select and initialize audio driver based on platform
    const SelectedDriver = volt_core.audio_driver.selectDriver();
    var driver = try SelectedDriver.init(allocator);
    defer driver.deinit();

    if (cli_args.list_devices) {
        driver.listDevices();
        return;
    }

    if (cli_args.use_realtime) {
        std.debug.print("Starting real-time processing for {d:.1} seconds...\n", .{cli_args.duration});
        std.debug.print("Plug in your guitar and start playing!\n", .{});
        std.debug.print("(Buffer size: {d} frames)\n", .{cli_args.buffer_size});
        std.debug.print("(Sample rate: {d} Hz)\n", .{cli_args.sample_rate});
        std.debug.print("(Effects in chain: {d})\n\n", .{chain.effectCount()});

        // Create a single effect processor that wraps the entire chain
        const chain_processor = [_]*anyopaque{
            @ptrCast(&chain),
        };

        try driver.startProcessing(cli_args.input_device, cli_args.output_device, cli_args.buffer_size, cli_args.sample_rate, @floatCast(cli_args.duration), &chain_processor);
        driver.deinit(); // Clean up audio resources
    } else {
        // Load guitar sample (existing behavior)
        const loader = volt_core.wav_loader.WAVLoader.init(allocator);
        std.debug.print("Loading: samples/ElectricGuitar1-Raw_105.wav\n", .{});

        var audio_buffer = loader.loadFile("samples/ElectricGuitar1-Raw_105.wav") catch |err| {
            std.debug.print("Error loading file: {}\n", .{err});
            return err;
        };
        defer audio_buffer.deinit(allocator);

        std.debug.print("✓ Loaded: {d} samples at {d}Hz ({d} channels)\n", .{
            audio_buffer.samples.len / audio_buffer.channel_count,
            audio_buffer.sample_rate,
            audio_buffer.channel_count,
        });

        // Apply configured effect chain
        std.debug.print("✓ Applying effect chain ({d} effects)...\n", .{chain.effectCount()});
        chain.processBuffer(&audio_buffer);

        // Play the processed audio
        var player = try volt_core.audio_player.AudioPlayer.init(allocator);
        defer player.deinit();

        std.debug.print("✓ Starting playback...\n\n", .{});
        try player.playBuffer(
            audio_buffer.samples.ptr,
            audio_buffer.samples.len / audio_buffer.channel_count,
            audio_buffer.sample_rate,
            audio_buffer.channel_count,
        );

        std.debug.print("✓ Playback complete!\n", .{});
    }
}
