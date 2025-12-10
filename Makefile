run-sample:
	zig build run

run-rt-portaudio:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32

run-rt:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32

run-list-devices:
	zig build run -- --list-devices