#!/usr/bin/env bash
set -euo pipefail

# Benchmark script for the free-whisper-flow transcription pipeline.
#
# This script simulates the exact command that Hammerspoon runs, but uses
# a pre-recorded audio file instead of the live microphone. This allows for
# consistent, repeatable performance measurements of the entire end-to-end
# transcription process (ffmpeg encoding -> python -> deepgram -> result).

# --- Configuration ---
AUDIO_FILE="eval_data/test.m4a"
NUM_RUNS=5
# ---------------------

# Ensure the audio file exists
if [[ ! -f "$AUDIO_FILE" ]]; then
    echo "❌ Error: Audio file not found at '$AUDIO_FILE'"
    echo "Please add a test audio file to the 'eval_data' directory."
    exit 1
fi

# Load the Deepgram API key from the .env file
if [[ ! -f ".env" ]]; then
    echo "❌ Error: .env file not found. Please run the installer to create one."
    exit 1
fi
source .env
if [[ -z "$DEEPGRAM_API_KEY" ]]; then
    echo "❌ Error: DEEPGRAM_API_KEY not found in .env file."
    exit 1
fi

# Locate the Python script and uv runner
PYTHON_SCRIPT="scripts/transcribe_and_copy.py"
UV_PATH="/opt/homebrew/bin/uv" # Assumes Homebrew default path

echo "🎙️  Starting benchmark for free-whisper-flow..."
echo "================================================"
echo "Audio File:   $AUDIO_FILE"
echo "Number of Runs: $NUM_RUNS"
echo "------------------------------------------------"

total_time=0

# Run the benchmark loop
for i in $(seq 1 $NUM_RUNS); do
    echo -n "Running iteration $i of $NUM_RUNS... "

    # Use the `time` command and capture the "real" time output.
    # The pipeline is constructed to be identical to the one in init.lua
    start_time=$(gdate +%s.%N)

    ffmpeg -nostdin -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a pcm_s16le -f s16le - | \
    "$UV_PATH" run --no-project "$PYTHON_SCRIPT" --api-key "$DEEPGRAM_API_KEY"

    end_time=$(gdate +%s.%N)
    run_time=$(echo "$end_time - $start_time" | bc)
    
    echo "Completed in ${run_time}s"
    total_time=$(echo "$total_time + $run_time" | bc)
done

# Calculate and display the average time
average_time=$(echo "scale=3; $total_time / $NUM_RUNS" | bc)
echo "------------------------------------------------"
echo "✅ Benchmark Complete"
echo "Average time over $NUM_RUNS runs: ${average_time}s"
echo "================================================"
        