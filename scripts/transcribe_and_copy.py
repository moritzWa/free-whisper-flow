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
    has_started_transcribing = False
    warning_sent = False

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

        async def receiver(ws, monitor_task: asyncio.Task):
            """Receive and process transcripts from the websocket."""
            nonlocal final_transcript_parts, has_started_transcribing
            try:
                async for message_string in ws:
                    msg = json.loads(message_string)
                    if not has_started_transcribing:
                        # Check for any transcript, even a partial one, to confirm audio is flowing
                        transcript_segment = msg.get("channel", {}).get("alternatives", [{}])[0].get("transcript", "")
                        if transcript_segment:
                            has_started_transcribing = True
                            # Cancel the monitor task as soon as we know it's working
                            monitor_task.cancel()

                    if msg.get("is_final"):
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

        async def monitor_transcription():
            """Check if transcription has started and show a warning if not."""
            try:
                nonlocal has_started_transcribing, warning_sent
                await asyncio.sleep(10)  # Wait for 10 seconds
                if not has_started_transcribing and not warning_sent:
                    warning_sent = True
                    print("No transcript received after 10s, sending alert.", file=sys.stderr)
                    # Use hs cli to show a native macOS alert
                    alert_cmd = 'hs -c "hs.alert.show(\'No audio detected. Check microphone.\')"'
                    os.system(alert_cmd)
            except asyncio.CancelledError:
                # This is expected if the task is cancelled, just ignore.
                pass


        monitor_task = asyncio.create_task(monitor_transcription())

        try:
            await asyncio.gather(sender(ws), receiver(ws, monitor_task))
        finally:
            # Ensure the monitor is always cancelled when we exit
            monitor_task.cancel()


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
