run-parse-kicad:
	rm -f samples/kicad/WilsonFuzz.json
	zig build run -- parse samples/kicad/WilsonFuzz.kicad_pcb samples/kicad/WilsonFuzz.json

run-sample-5150:
	zig build run -- sample samples/guitar/electric-guitar-chords-cheerful-chords_75bpm_C_major.wav config/neural_5150.json

run-sample-jcm800:
	zig build run -- sample samples/guitar/electric-guitar-chords-cheerful-chords_75bpm_C_major.wav config/neural_jcm_800.json

run-rt-portaudio:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32 --sample-rate 44100  --chain ./config/neural_orange_amp.json

run-rt:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32 --sample-rate 44100  --chain config/chain_three_stage.json


run-rt-neural:
	zig build run -- -rt --input-device 2 --output-device 2 --buffer-size 32 --sample-rate 44100  --chain ./config/neural_orange_amp.json

run-list-devices:
	zig build run -- --list-devices

test:
	zig build test-parser
	zig build test-wilson
	zig build test

build:
	zig build

clean:
	rm -rf zig-cache zig-out

.PHONY: run-sample run-rt-portaudio run-rt run-list-devices test build clean
