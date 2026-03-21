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
import base64
import json
import os
import ssl
import sys
import subprocess
import urllib.request
from typing import Optional

import websockets
import certifi

DEEPGRAM_API_URL = "wss://api.deepgram.com/v1/listen"
ELEVENLABS_API_URL = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"


def read_api_key(cli_key: Optional[str], provider: str) -> str:
    if provider == "elevenlabs":
        env_var = "ELEVENLABS_API_KEY"
    else:
        env_var = "DEEPGRAM_API_KEY"
    key = cli_key or os.getenv(env_var)
    if not key:
        print(f"{env_var} not set and --api-key not provided", file=sys.stderr)
        sys.exit(2)
    return key


async def transcribe_stream_deepgram(api_key: str) -> str:
    uri = (
        f"{DEEPGRAM_API_URL}?model=nova-2&smart_format=true"
        "&encoding=linear16&sample_rate=16000"
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
            nonlocal final_transcript_parts, has_started_transcribing
            try:
                async for message_string in ws:
                    msg = json.loads(message_string)
                    if not has_started_transcribing:
                        transcript_segment = msg.get("channel", {}).get("alternatives", [{}])[0].get("transcript", "")
                        if transcript_segment:
                            has_started_transcribing = True
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
            try:
                nonlocal has_started_transcribing, warning_sent
                await asyncio.sleep(10)
                if not has_started_transcribing and not warning_sent:
                    warning_sent = True
                    print("No transcript received after 10s, sending alert.", file=sys.stderr)
                    alert_cmd = 'hs -c "hs.alert.show(\'No audio detected. Check microphone.\')"'
                    os.system(alert_cmd)
            except asyncio.CancelledError:
                pass

        monitor_task = asyncio.create_task(monitor_transcription())

        try:
            await asyncio.gather(sender(ws), receiver(ws, monitor_task))
        finally:
            monitor_task.cancel()

    return " ".join(final_transcript_parts)


async def transcribe_stream_elevenlabs(api_key: str) -> str:
    uri = (
        f"{ELEVENLABS_API_URL}?model_id=scribe_v2_realtime"
        "&audio_format=pcm_16000&commit_strategy=vad"
        "&language_code=en"
    )

    final_transcript_parts = []
    has_started_transcribing = False
    sender_done = asyncio.Event()

    ssl_context = ssl.create_default_context(cafile=certifi.where())

    async with websockets.connect(
        uri,
        extra_headers={"xi-api-key": api_key},
        ssl=ssl_context,
    ) as ws:

        async def sender(ws):
            """Stream audio from stdin, then send silence + commit to flush."""
            try:
                while True:
                    data = await asyncio.get_event_loop().run_in_executor(
                        None, sys.stdin.buffer.read, 8192
                    )
                    if not data:
                        break
                    await ws.send(json.dumps({
                        "message_type": "input_audio_chunk",
                        "audio_base_64": base64.b64encode(data).decode(),
                        "commit": False,
                        "sample_rate": 16000,
                    }))
                # Send 2s of silence so VAD detects end-of-speech
                silence = b'\x00' * 64000  # 2s at 16kHz 16-bit mono
                for i in range(0, len(silence), 8192):
                    await ws.send(json.dumps({
                        "message_type": "input_audio_chunk",
                        "audio_base_64": base64.b64encode(silence[i:i+8192]).decode(),
                        "commit": False,
                        "sample_rate": 16000,
                    }))
                # Manual commit as final flush
                await ws.send(json.dumps({
                    "message_type": "input_audio_chunk",
                    "audio_base_64": "",
                    "commit": True,
                    "sample_rate": 16000,
                }))
            except Exception as e:
                print(f"Error in sender: {e}", file=sys.stderr)
            sender_done.set()
            print("Sender finished.", file=sys.stderr)

        async def receiver(ws):
            """Collect committed transcripts. Once sender is done and we get a
            final commit with no more partials following, close immediately."""
            nonlocal final_transcript_parts, has_started_transcribing
            try:
                while True:
                    # Once sender is done and we've seen a commit, use short timeout
                    # to catch any remaining messages, then exit
                    use_short = sender_done.is_set()
                    try:
                        msg_str = await asyncio.wait_for(ws.recv(), timeout=0.8 if use_short else 30.0)
                    except asyncio.TimeoutError:
                        break
                    msg = json.loads(msg_str)
                    msg_type = msg.get("message_type", "")

                    if not has_started_transcribing:
                        if msg_type in ("partial_transcript", "committed_transcript"):
                            if msg.get("text", ""):
                                has_started_transcribing = True

                    if msg_type == "committed_transcript":
                        text = msg.get("text", "")
                        if text:
                            final_transcript_parts.append(text)
            except Exception as e:
                print(f"Error in receiver: {e}", file=sys.stderr)
            print("Receiver finished.", file=sys.stderr)

        async def monitor():
            try:
                await asyncio.sleep(10)
                if not has_started_transcribing:
                    print("No transcript received after 10s, sending alert.", file=sys.stderr)
                    os.system('hs -c "hs.alert.show(\'No audio detected. Check microphone.\')"')
            except asyncio.CancelledError:
                pass

        monitor_task = asyncio.create_task(monitor())
        # Run sender and receiver concurrently so receiver collects
        # transcripts while audio is still streaming
        await asyncio.gather(sender(ws), receiver(ws))
        monitor_task.cancel()

    return " ".join(final_transcript_parts)


CLEANUP_SYSTEM_PROMPT = (
    "Clean up this speech-to-text transcript. The speaker is a software engineer. "
    "Remove filler words. Fix punctuation and capitalization. "
    "Fix misheard programming terms to their correct technical spelling. "
    "Keep the meaning, tone, and voice identical. "
    "Return ONLY the cleaned transcript text. No preamble, no commentary, no labels."
)


def cleanup_with_llm(transcript: str, groq_api_key: str) -> str:
    """Send transcript through Groq LLM for cleanup. Returns original on failure."""
    try:
        body = json.dumps({
            "model": "meta-llama/llama-4-scout-17b-16e-instruct",
            "messages": [
                {"role": "system", "content": CLEANUP_SYSTEM_PROMPT},
                {"role": "user", "content": transcript},
            ],
            "temperature": 0.1,
            "max_tokens": 1024,
        }).encode()

        req = urllib.request.Request(
            "https://api.groq.com/openai/v1/chat/completions",
            data=body,
            headers={
                "Authorization": f"Bearer {groq_api_key}",
                "Content-Type": "application/json",
                "User-Agent": "free-whisper-flow/1.0",
            },
        )
        ssl_ctx = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(req, timeout=5, context=ssl_ctx) as resp:
            result = json.loads(resp.read())
            cleaned = result["choices"][0]["message"]["content"].strip()
            if cleaned:
                print(f"LLM cleanup: '{transcript}' -> '{cleaned}'", file=sys.stderr)
                return cleaned
    except Exception as e:
        print(f"LLM cleanup failed, using raw transcript: {e}", file=sys.stderr)
    return transcript


def copy_to_clipboard(text: str) -> None:
    try:
        subprocess.run(["pbcopy"], input=text.encode("utf-8"), check=True)
    except Exception as e:
        print(f"Failed to copy to clipboard: {e}", file=sys.stderr)


async def main() -> int:
    parser = argparse.ArgumentParser(
        description="Transcribe an audio stream and copy to clipboard"
    )
    parser.add_argument(
        "--api-key", dest="api_key", help="API key (or set via env var)"
    )
    parser.add_argument(
        "--provider", dest="provider", default="elevenlabs",
        choices=["deepgram", "elevenlabs"],
        help="STT provider (default: elevenlabs)"
    )
    parser.add_argument(
        "--groq-api-key", dest="groq_api_key", default=None,
        help="Groq API key for LLM transcript cleanup"
    )
    args = parser.parse_args()

    try:
        key = read_api_key(args.api_key, args.provider)
        if args.provider == "elevenlabs":
            transcript = await transcribe_stream_elevenlabs(key)
        else:
            transcript = await transcribe_stream_deepgram(key)
        if not transcript:
            print("No transcript returned", file=sys.stderr)
            return 1
        # Optional LLM cleanup via Groq
        if args.groq_api_key:
            transcript = cleanup_with_llm(transcript, args.groq_api_key)
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
