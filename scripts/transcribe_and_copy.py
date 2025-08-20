#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
import subprocess
from typing import Optional

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

    with open(path, "rb") as f:
        data = f.read()

    params = {
        "model": "nova-2",
        "smart_format": "true",
    }
    url = f"{DEEGRAM_API_URL}?{urllib.parse.urlencode(params)}"

    req = urllib.request.Request(url, method="POST")
    req.add_header("Authorization", f"Token {api_key}")
    # Assume m4a; Deepgram will handle common codecs. Adjust if you change format.
    req.add_header("Content-Type", "audio/m4a")

    with urllib.request.urlopen(req, data=data, timeout=600) as resp:
        payload = json.loads(resp.read().decode("utf-8"))

    transcript = (
        payload.get("results", {})
        .get("channels", [{}])[0]
        .get("alternatives", [{}])[0]
        .get("transcript", "")
    )
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
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="ignore")
        print(f"HTTP error: {e.code} {e.reason} {body}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
