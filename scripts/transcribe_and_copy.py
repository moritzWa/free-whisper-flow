#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "requests<3",
#   "certifi>=2024.7.4",
# ]
# ///

import argparse
import json
import os
import sys
import subprocess
from typing import Optional

import requests
import certifi

DEEGRAM_API_URL = "https://api.deepgram.com/v1/listen"


def read_api_key(cli_key: Optional[str]) -> str:
    key = cli_key or os.getenv("DEEPGRAM_API_KEY")
    if not key:
        print("DEEPGRAM_API_KEY not set and --api-key not provided", file=sys.stderr)
        sys.exit(2)
    return key


def transcribe_file(path: str, api_key: str) -> str:
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Audio file not found: {path}")

    file_size = os.path.getsize(path)

    if file_size < 1000:
        print(f"Audio file too small ({file_size} bytes), likely no audio content", file=sys.stderr)
        return ""

    with open(path, "rb") as f:
        data = f.read()

    headers = {
        "Authorization": f"Token {api_key}",
        "Content-Type": "audio/m4a",
    }
    params = {
        "model": "nova-2",
        "smart_format": "true",
    }


    r = requests.post(
        DEEGRAM_API_URL,
        headers=headers,
        params=params,
        data=data,
        timeout=600,
        verify=certifi.where(),
    )
    
    
    r.raise_for_status()
    payload = r.json()
    

    transcript = (
        payload.get("results", {})
        .get("channels", [{}])[0]
        .get("alternatives", [{}])[0]
        .get("transcript", "")
    )

    if not transcript:
        confidence = payload.get("results", {}).get("channels", [{}])[0].get("alternatives", [{}])[0].get("confidence", 0)
        print(f"No transcript returned (confidence: {confidence})", file=sys.stderr)

    return transcript or ""


def copy_to_clipboard(text: str) -> None:
    try:
        subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)
    except Exception as e:
        print(f"Failed to copy to clipboard: {e}", file=sys.stderr)


def write_sidecar_transcript(audio_path: str, transcript: str) -> str:
    base_dir = os.path.dirname(os.path.abspath(audio_path))
    out_dir = os.path.join(base_dir, "transcripts_tmp")
    os.makedirs(out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(audio_path))[0]
    out_path = os.path.join(out_dir, f"{stem}.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(transcript)
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Transcribe an audio file with Deepgram and copy to clipboard")
    parser.add_argument("audio_path", help="Path to recorded audio file")
    parser.add_argument("--api-key", dest="api_key", help="Deepgram API key (or set DEEPGRAM_API_KEY)")
    args = parser.parse_args()

    try:
        key = read_api_key(args.api_key)
        transcript = transcribe_file(args.audio_path, key)
        if not transcript:
            print("No transcript returned", file=sys.stderr)
            return 1
        sidecar = write_sidecar_transcript(args.audio_path, transcript)
        copy_to_clipboard(transcript)
        print(json.dumps({"ok": True, "transcript_file": sidecar}))
        return 0
    except requests.HTTPError as e:
        body = e.response.text if e.response is not None else ""
        print(f"HTTP error: {e} {body}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
