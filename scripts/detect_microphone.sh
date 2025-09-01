#!/usr/bin/env bash
set -euo pipefail

# Auto-detect the default microphone device for macOS ffmpeg recording
# Returns the device index in format ":N" suitable for ffmpeg -i

# Get audio device list from ffmpeg (ignore exit code since ffmpeg returns error)
set +e
audio_devices=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A 50 "AVFoundation audio devices:" | grep "^\[" | grep -v "AVFoundation audio devices:")
set -e

# Look for common microphone patterns in order of preference
microphone_patterns=(
    "MacBook.*Microphone"
    "Built-in Microphone" 
    "Internal Microphone"
    "Default.*Microphone"
    "Microphone"
    "iPhone.*Microphone"
)

# Find first matching microphone
for pattern in "${microphone_patterns[@]}"; do
    device_line=$(echo "$audio_devices" | grep -i "$pattern" | head -1 || true)
    if [[ -n "$device_line" ]]; then
        # Extract device index from format: [AVFoundation indev @ 0x...] [4] MacBook Pro Microphone
        device_index=$(echo "$device_line" | grep -o '\[[0-9]\+\]' | grep -o '[0-9]\+' | head -1)
        if [[ -n "$device_index" ]]; then
            echo ":$device_index"
            exit 0
        fi
    fi
done

# Fallback: use first audio device that contains "Microphone"
fallback_device=$(echo "$audio_devices" | grep -i "microphone" | head -1 || true)
if [[ -n "$fallback_device" ]]; then
    device_index=$(echo "$fallback_device" | grep -o '\[[0-9]\+\]' | grep -o '[0-9]\+' | head -1)
    if [[ -n "$device_index" ]]; then
        echo ":$device_index"
        exit 0
    fi
fi

# No microphone found
echo "Error: No microphone device found" >&2
echo "Available audio devices:" >&2
echo "$audio_devices" >&2
exit 1