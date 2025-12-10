run-sample:
	zig build run

run-rt:
	zig build run -- -rt --input-device 2 --output-device 2

run-list-devices:
	zig build run -- --list-devices