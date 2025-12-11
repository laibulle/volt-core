const std = @import("std");

/// CLI argument parsing errors
pub const CliError = error{
    MissingChainConfiguration,
    InvalidSampleRate,
    InvalidIntegerArgument,
    InvalidFloatArgument,
    MissingArgumentValue,
    InvalidArgumentValue,
};

/// Command type
pub const Command = enum {
    run, // Run effect chain (default)
    parse, // Parse KiCAD file to intermediate format
    sample, // Test with sample audio files
};

/// Parsed CLI arguments
pub const CliArgs = struct {
    command: Command = .run,
    use_realtime: bool = false,
    list_devices: bool = false,
    duration: f32 = -1.0, // -1 means infinite
    input_device: i32 = -1, // -1 means use default
    output_device: i32 = -1, // -1 means use default
    buffer_size: u32 = 128,
    sample_rate: u32 = 44100,
    chain_config_file: ?[]const u8 = null,
    kicad_file: ?[]const u8 = null, // For parse command
    output_file: ?[]const u8 = null, // For parse command
    sample_name: ?[]const u8 = null, // For sample command
};

/// Supported sample rates
const SUPPORTED_SAMPLE_RATES = [_]u32{ 44100, 48000, 88200, 96000, 192000 };

pub fn printHelp() void {
    std.debug.print("Volt Core - Guitar Effects Processor\n", .{});
    std.debug.print("Usage: volt_core <command> [options]\n\n", .{});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  run <options>                      Run effect chain with real-time or sample input\n", .{});
    std.debug.print("  sample <path> <chain_config>       Test with sample audio file\n", .{});
    std.debug.print("  parse <kicad_file> <output.json>   Parse KiCAD file to intermediate JSON format\n\n", .{});
    std.debug.print("Run command options:\n", .{});
    std.debug.print("  --chain, -c <file>                 Load effect chain from JSON config file (REQUIRED)\n", .{});
    std.debug.print("  --list-devices, -ld                List available audio devices\n", .{});
    std.debug.print("  --realtime, -rt                    Use real-time input (guitar input)\n", .{});
    std.debug.print("  --input-device <id>                Input device ID (default: system default)\n", .{});
    std.debug.print("  --output-device <id>               Output device ID (default: system default)\n", .{});
    std.debug.print("  --buffer-size, -bs <frames>        Audio buffer size in frames (default: 128)\n", .{});
    std.debug.print("  --sample-rate, -sr <hz>            Sample rate in Hz (default: 44100)\n", .{});
    std.debug.print("                                     Supported: 44100, 48000, 88200, 96000, 192000\n", .{});
    std.debug.print("  --duration, -d <seconds>           Duration for realtime mode (default: infinite, press Ctrl+C to stop)\n", .{});
    std.debug.print("  --help, -h                         Show this help message\n\n", .{});
    std.debug.print("Examples:\n", .{});
    std.debug.print("  volt_core run --chain config/neural_orange_amp.json --realtime\n", .{});
    std.debug.print("  volt_core sample samples/ElectricGuitar1-Raw_105.wav config/neural_orange_amp.json\n", .{});
    std.debug.print("  volt_core parse samples/circuit.kicad config/output.json\n", .{});
}

/// Print error message for missing chain configuration
pub fn printMissingChainError() void {
    std.debug.print("Error: Chain configuration is required. Use --chain or -c to specify a JSON config file.\n", .{});
    std.debug.print("Available configs in config/ directory:\n", .{});
    std.debug.print("  - chain_single_distortion.json\n", .{});
    std.debug.print("  - chain_dual_distortion.json\n", .{});
    std.debug.print("  - chain_three_stage.json\n", .{});
}

/// Print error message for invalid sample rate
pub fn printInvalidSampleRateError(rate: u32) void {
    std.debug.print("Error: Invalid sample rate {d} Hz\n", .{rate});
    std.debug.print("Supported rates: ", .{});
    for (SUPPORTED_SAMPLE_RATES, 0..) |supported_rate, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("{d}", .{supported_rate});
    }
    std.debug.print("\n", .{});
}

/// Check if sample rate is supported
fn isSampleRateSupported(rate: u32) bool {
    for (SUPPORTED_SAMPLE_RATES) |supported_rate| {
        if (rate == supported_rate) return true;
    }
    return false;
}

/// Parse command line arguments
pub fn parse(_: std.mem.Allocator, args: []const []const u8) !CliArgs {
    var cli_args: CliArgs = .{};

    if (args.len < 2) {
        printHelp();
        std.process.exit(1);
    }

    // Check for help flag first
    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        printHelp();
        std.process.exit(0);
    }

    // Check for parse command
    if (std.mem.eql(u8, args[1], "parse")) {
        if (args.len < 4) {
            std.debug.print("Error: parse command requires input and output files\n", .{});
            std.debug.print("Usage: volt_core parse <kicad_file> <output.json>\n", .{});
            return CliError.MissingArgumentValue;
        }
        cli_args.command = .parse;
        cli_args.kicad_file = args[2];
        cli_args.output_file = args[3];
        return cli_args;
    }

    // Check for sample command
    if (std.mem.eql(u8, args[1], "sample")) {
        if (args.len < 4) {
            std.debug.print("Error: sample command requires sample file path and chain config file\n", .{});
            std.debug.print("Usage: volt_core sample <sample_path> <chain_config.json>\n\n", .{});
            std.debug.print("Examples:\n", .{});
            std.debug.print("  volt_core sample samples/ElectricGuitar1-Raw_105.wav config/neural_orange_amp.json\n", .{});
            std.debug.print("  volt_core sample samples/ElectricGuitar1-Raw_105.wav config/chain_single_distortion.json\n", .{});
            return CliError.MissingArgumentValue;
        }
        cli_args.command = .sample;
        cli_args.sample_name = args[2]; // Use as file path directly
        cli_args.chain_config_file = args[3];
        return cli_args;
    }

    // Check for run command
    if (std.mem.eql(u8, args[1], "run")) {
        cli_args.command = .run;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--realtime") or std.mem.eql(u8, args[i], "-rt")) {
                cli_args.use_realtime = true;
            } else if (std.mem.eql(u8, args[i], "--list-devices") or std.mem.eql(u8, args[i], "-ld")) {
                cli_args.list_devices = true;
            } else if (std.mem.eql(u8, args[i], "--duration") or std.mem.eql(u8, args[i], "-d")) {
                if (i + 1 < args.len) {
                    cli_args.duration = std.fmt.parseFloat(f32, args[i + 1]) catch |err| {
                        std.debug.print("Error: Failed to parse duration: {}\n", .{err});
                        return CliError.InvalidFloatArgument;
                    };
                    i += 1;
                } else {
                    std.debug.print("Error: --duration requires a value\n", .{});
                    return CliError.MissingArgumentValue;
                }
            } else if (std.mem.eql(u8, args[i], "--input-device")) {
                if (i + 1 < args.len) {
                    cli_args.input_device = std.fmt.parseInt(i32, args[i + 1], 10) catch |err| {
                        std.debug.print("Error: Failed to parse input device ID: {}\n", .{err});
                        return CliError.InvalidIntegerArgument;
                    };
                    i += 1;
                } else {
                    std.debug.print("Error: --input-device requires a value\n", .{});
                    return CliError.MissingArgumentValue;
                }
            } else if (std.mem.eql(u8, args[i], "--output-device")) {
                if (i + 1 < args.len) {
                    cli_args.output_device = std.fmt.parseInt(i32, args[i + 1], 10) catch |err| {
                        std.debug.print("Error: Failed to parse output device ID: {}\n", .{err});
                        return CliError.InvalidIntegerArgument;
                    };
                    i += 1;
                } else {
                    std.debug.print("Error: --output-device requires a value\n", .{});
                    return CliError.MissingArgumentValue;
                }
            } else if (std.mem.eql(u8, args[i], "--buffer-size") or std.mem.eql(u8, args[i], "-bs")) {
                if (i + 1 < args.len) {
                    cli_args.buffer_size = std.fmt.parseUnsigned(u32, args[i + 1], 10) catch |err| {
                        std.debug.print("Error: Failed to parse buffer size: {}\n", .{err});
                        return CliError.InvalidIntegerArgument;
                    };
                    i += 1;
                } else {
                    std.debug.print("Error: --buffer-size requires a value\n", .{});
                    return CliError.MissingArgumentValue;
                }
            } else if (std.mem.eql(u8, args[i], "--sample-rate") or std.mem.eql(u8, args[i], "-sr")) {
                if (i + 1 < args.len) {
                    const requested_rate = std.fmt.parseUnsigned(u32, args[i + 1], 10) catch |err| {
                        std.debug.print("Error: Failed to parse sample rate: {}\n", .{err});
                        return CliError.InvalidIntegerArgument;
                    };

                    if (!isSampleRateSupported(requested_rate)) {
                        printInvalidSampleRateError(requested_rate);
                        return CliError.InvalidSampleRate;
                    }
                    cli_args.sample_rate = requested_rate;
                    i += 1;
                } else {
                    std.debug.print("Error: --sample-rate requires a value\n", .{});
                    return CliError.MissingArgumentValue;
                }
            } else if (std.mem.eql(u8, args[i], "--chain") or std.mem.eql(u8, args[i], "-c")) {
                if (i + 1 < args.len) {
                    cli_args.chain_config_file = args[i + 1];
                    i += 1;
                } else {
                    std.debug.print("Error: --chain requires a file path\n", .{});
                    return CliError.MissingArgumentValue;
                }
            } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
                printHelp();
                std.process.exit(0);
            } else {
                std.debug.print("Error: Unknown argument '{s}'\n", .{args[i]});
                std.debug.print("Use --help for usage information\n", .{});
                return CliError.InvalidArgumentValue;
            }
        }
        return cli_args;
    }

    // Unknown command
    std.debug.print("Error: Unknown command '{s}'\n\n", .{args[1]});
    printHelp();
    return CliError.InvalidArgumentValue;
}
