run-sample:
	zig build run

run-rt-portaudio:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32

run-rt:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32 --sample-rate 44100

run-list-devices:
	zig build run -- --list-devices

test:
	@echo "Running effects port interface tests..."
	@zig test src/ports/effects_test.zig
	@echo ""
	@echo "✓ All port interface tests passed!"

test-all:
	@./test.sh

build:
	zig build

clean:
	rm -rf zig-cache zig-out

.PHONY: run-sample run-rt-portaudio run-rt run-list-devices test test-all build clean
