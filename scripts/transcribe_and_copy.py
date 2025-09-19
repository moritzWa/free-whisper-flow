#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "websockets<13",
#   "certifi>=2024.7.4",
# ]
# ///

import argparse
import asyncio
import json
import os
import ssl
import sys
import subprocess
from typing import Optional

import websockets
import certifi

DEEGRAM_API_URL = "wss://api.deepgram.com/v1/listen"


def read_api_key(cli_key: Optional[str]) -> str:
    key = cli_key or os.getenv("DEEPGRAM_API_KEY")
    if not key:
        print("DEEPGRAM_API_KEY not set and --api-key not provided", file=sys.stderr)
        sys.exit(2)
    return key


async def transcribe_stream(api_key: str) -> str:
    uri = (
        f"{DEEGRAM_API_URL}?model=nova-2&smart_format=true"
        "&encoding=linear16&sample_rate=48000"
    )

    final_transcript_parts = []

    ssl_context = ssl.create_default_context(cafile=certifi.where())

    async with websockets.connect(
        uri,
        extra_headers={"Authorization": f"Token {api_key}"},
        ssl=ssl_context,
    ) as ws:

        async def sender(ws):
            """Send audio data from stdin to the websocket."""
            try:
                while True:
                    data = await asyncio.get_event_loop().run_in_executor(
                        None, sys.stdin.buffer.read, 4096
                    )
                    if not data:
                        break
                    await ws.send(data)
                await ws.send(json.dumps({"type": "CloseStream"}))
            except Exception as e:
                print(f"Error in sender: {e}", file=sys.stderr)
            print("Sender finished.", file=sys.stderr)

        async def receiver(ws):
            """Receive and process transcripts from the websocket."""
            nonlocal final_transcript_parts
            try:
                async for msg_str in ws:
                    msg = json.loads(msg_str)
                    if msg.get("type") == "SpeechFinal":
                         # The old API used this, new one uses is_final. Keeping for some compatibility.
                        transcript = (
                            msg.get("channel", {})
                            .get("alternatives", [{}])[0]
                            .get("transcript", "")
                        )
                        if transcript:
                           final_transcript_parts.append(transcript)
                    elif msg.get("is_final"):
                        transcript = (
                            msg.get("channel", {})
                            .get("alternatives", [{}])[0]
                            .get("transcript", "")
                        )
                        if transcript:
                           final_transcript_parts.append(transcript)

            except Exception as e:
                print(f"Error in receiver: {e}", file=sys.stderr)
            print("Receiver finished.", file=sys.stderr)

        await asyncio.gather(sender(ws), receiver(ws))

    return " ".join(final_transcript_parts)


def copy_to_clipboard(text: str) -> None:
    try:
        subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)
    except Exception as e:
        print(f"Failed to copy to clipboard: {e}", file=sys.stderr)


async def main() -> int:
    parser = argparse.ArgumentParser(
        description="Transcribe an audio stream with Deepgram and copy to clipboard"
    )
    parser.add_argument(
        "--api-key", dest="api_key", help="Deepgram API key (or set DEEPGRAM_API_KEY)"
    )
    args = parser.parse_args()

    try:
        key = read_api_key(args.api_key)
        transcript = await transcribe_stream(key)
        if not transcript:
            print("No transcript returned", file=sys.stderr)
            return 1
        copy_to_clipboard(transcript)
        print(json.dumps({"ok": True, "transcript": transcript}))
        return 0
    except websockets.exceptions.ConnectionClosedError as e:
        print(f"Connection closed: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
