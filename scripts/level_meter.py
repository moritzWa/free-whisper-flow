#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///

"""Reads raw PCM s16le mono 16kHz from stdin and writes RMS level to a temp file."""

import math
import struct
import sys

CHUNK_SAMPLES = 1600  # 100ms at 16kHz
LEVEL_FILE = "/tmp/fwf_level.txt"

def rms(samples):
    if not samples:
        return 0.0
    sum_sq = sum(s * s for s in samples)
    return math.sqrt(sum_sq / len(samples))

def main():
    try:
        while True:
            raw = sys.stdin.buffer.read(CHUNK_SAMPLES * 2)  # 2 bytes per sample
            if not raw:
                break
            n_samples = len(raw) // 2
            samples = struct.unpack(f"<{n_samples}h", raw[:n_samples * 2])
            level = rms(samples) / 32768.0  # normalize to 0.0-1.0
            with open(LEVEL_FILE, "w") as f:
                f.write(f"{level:.4f}")
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    # Clean up
    try:
        import os
        os.unlink(LEVEL_FILE)
    except OSError:
        pass

if __name__ == "__main__":
    main()
