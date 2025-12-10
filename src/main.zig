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

    var use_realtime = false;
    var list_devices = false;
    var duration: f32 = -1.0; // -1 means infinite (run until Ctrl+C)
    var input_device: i32 = -1; // -1 means use default
    var output_device: i32 = -1; // -1 means use default
    var buffer_size: u32 = 128; // Default 128 frames
    var sample_rate: u32 = 44100; // Default 44.1kHz

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--realtime") or std.mem.eql(u8, args[i], "-rt")) {
            use_realtime = true;
        } else if (std.mem.eql(u8, args[i], "--list-devices") or std.mem.eql(u8, args[i], "-ld")) {
            list_devices = true;
        } else if (std.mem.eql(u8, args[i], "--duration") or std.mem.eql(u8, args[i], "-d")) {
            if (i + 1 < args.len) {
                duration = try std.fmt.parseFloat(f32, args[i + 1]);
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--input-device")) {
            if (i + 1 < args.len) {
                input_device = try std.fmt.parseInt(i32, args[i + 1], 10);
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--output-device")) {
            if (i + 1 < args.len) {
                output_device = try std.fmt.parseInt(i32, args[i + 1], 10);
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--buffer-size") or std.mem.eql(u8, args[i], "-bs")) {
            if (i + 1 < args.len) {
                buffer_size = try std.fmt.parseUnsigned(u32, args[i + 1], 10);
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--sample-rate") or std.mem.eql(u8, args[i], "-sr")) {
            if (i + 1 < args.len) {
                sample_rate = try std.fmt.parseUnsigned(u32, args[i + 1], 10);
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            std.debug.print("Volt Core - Guitar Effects Processor\n", .{});
            std.debug.print("Usage: volt_core [options]\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  --list-devices, -ld               List available audio devices\n", .{});
            std.debug.print("  --realtime, -rt                   Use real-time input (guitar input)\n", .{});
            std.debug.print("  --input-device <id>               Input device ID (default: system default)\n", .{});
            std.debug.print("  --output-device <id>              Output device ID (default: system default)\n", .{});
            std.debug.print("  --buffer-size, -bs <frames>       Audio buffer size in frames (default: 128)\n", .{});
            std.debug.print("  --sample-rate, -sr <hz>           Sample rate in Hz (default: 44100)\n", .{});
            std.debug.print("  --duration, -d <seconds>          Duration for realtime mode (default: infinite, press Ctrl+C to stop)\n", .{});
            std.debug.print("  --help, -h                        Show this help message\n", .{});
            return;
        }
    }

    std.debug.print("Volt Core - Real-time Guitar Effects Player\n", .{});
    std.debug.print("============================================\n\n", .{});

    // Select and initialize audio driver based on platform
    const SelectedDriver = volt_core.audio_driver.selectDriver();
    var driver = try SelectedDriver.init(allocator);
    defer driver.deinit();

    if (list_devices) {
        driver.listDevices();
        return;
    }

    if (use_realtime) {
        // Load IR for convolution
        const ir_loader = volt_core.ir_loader.IRLoader.init(allocator);
        std.debug.print("Loading: samples/ir/CelestionVintage30/44.1kHz/200ms/Cenzo CelestionV30Mix.wav\n", .{});

        var ir_buffer = ir_loader.loadFile("samples/ir/CelestionVintage30/44.1kHz/200ms/Cenzo CelestionV30Mix.wav") catch |err| {
            std.debug.print("Error loading IR: {}\n", .{err});
            return err;
        };
        defer ir_buffer.deinit(allocator);

        std.debug.print("✓ Loaded IR: {d} samples\n\n", .{ir_buffer.samples.len});

        // Setup effects
        var distortion = volt_core.effects.Distortion{
            .drive = 6.5,
            .tone = 0.8,
        };

        var convolver = try volt_core.effects.Convolver.init(allocator, ir_buffer);
        defer convolver.deinit();

        std.debug.print("Starting real-time processing for {d:.1} seconds...\n", .{duration});
        std.debug.print("Plug in your guitar and start playing!\n", .{});
        std.debug.print("(Distortion: drive={d:.1}, tone={d:.1})\n", .{ distortion.drive, distortion.tone });
        std.debug.print("(Cabinet: Celestion Vintage 30)\n", .{});
        std.debug.print("(Buffer size: {d} frames)\n", .{buffer_size});
        std.debug.print("(Sample rate: {d} Hz)\n\n", .{sample_rate});

        try driver.startProcessing(input_device, output_device, buffer_size, sample_rate, duration, &distortion, &convolver);
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

        // Apply distortion effect
        var distortion = volt_core.effects.Distortion{
            .drive = 6.5,
            .tone = 0.8,
        };

        std.debug.print("✓ Applying distortion (drive: {d:.1}, tone: {d:.1})\n", .{ distortion.drive, distortion.tone });
        distortion.processBuffer(&audio_buffer);

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
