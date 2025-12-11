const std = @import("std");
const volt_core = @import("volt_core");

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

    // Validate that chain configuration is provided
    if (cli_args.chain_config_file == null) {
        volt_core.cli.printMissingChainError();
        return volt_core.cli.CliError.MissingChainConfiguration;
    }

    std.debug.print("Volt Core - Real-time Guitar Effects Player\n", .{});
    std.debug.print("============================================\n\n", .{});

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

        // Load impulse response (cabinet simulation)
        const ir_loader = volt_core.ir_loader.IRLoader.init(allocator);
        std.debug.print("Loading: samples/ir/CelestionVintage30/44.1kHz/200ms/Cenzo CelestionV30Mix.wav\n", .{});

        var ir_buffer = ir_loader.loadFile("samples/ir/CelestionVintage30/44.1kHz/200ms/Cenzo CelestionV30Mix.wav") catch |err| {
            std.debug.print("Error loading IR: {}\n", .{err});
            return err;
        };
        defer ir_buffer.deinit(allocator);

        std.debug.print("✓ Loaded IR: {d} samples\n", .{ir_buffer.samples.len});

        // Apply convolver (cabinet emulation)
        var convolver = try volt_core.effects.Convolver.init(allocator, ir_buffer);
        defer convolver.deinit();

        std.debug.print("✓ Applying cabinet convolution...\n", .{});
        convolver.processBuffer(&audio_buffer);

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
