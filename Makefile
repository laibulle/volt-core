run-sample:
	zig build run

run-rt-portaudio:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32

run-rt:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32 --sample-rate 44100

run-list-devices:
	zig build run -- --list-devices

test:
	zig build test

build:
	zig build

clean:
	rm -rf zig-cache zig-out

.PHONY: run-sample run-rt-portaudio run-rt run-list-devices test build clean
