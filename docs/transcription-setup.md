## Setup: Transcription + Clipboard

This adds a Python CLI that sends the recorded audio to Deepgram and copies the transcript to your clipboard.

### 1) Create a virtualenv (recommended)
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install requests
```

### 2) Add the script `scripts/transcribe_and_copy.py`
Create `scripts/transcribe_and_copy.py`:

```python
#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
from typing import Optional

import requests

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

    headers = {
        "Authorization": f"Token {api_key}",
        "Content-Type": "audio/m4a",
    }
    params = {
        "model": "nova-2",
        "smart_format": "true",
    }

    r = requests.post(DEEGRAM_API_URL, headers=headers, params=params, data=data, timeout=600)
    r.raise_for_status()
    payload = r.json()

    # Path: results.channels[0].alternatives[0].transcript
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
        copy_to_clipboard(transcript)
        print(transcript)
        return 0
    except requests.HTTPError as e:
        print(f"HTTP error: {e} / {getattr(e, 'response', None) and getattr(e.response, 'text', '')}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

Make it executable:
```bash
chmod +x scripts/transcribe_and_copy.py
```

### 3) Export your API key
```bash
export DEEPGRAM_API_KEY="YOUR_KEY_HERE"
```
Optionally add to your shell profile.

### 4) Integrate with Hammerspoon
Append to `~/.hammerspoon/init.lua` stop handler after saving `lastOutputFile`:

```lua
-- After we set lastOutputFile, trigger transcription
local function runTranscription(path)
  local script = "${PROJECT_DIR}/scripts/transcribe_and_copy.py"  -- update this path
  hs.alert.show("Transcribing…")
  hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
    if exitCode == 0 then
      hs.alert.show("Transcript copied to clipboard")
    else
      hs.alert.show("Transcription failed")
      if stdErr and #stdErr > 0 then print(stdErr) end
    end
  end, {"-lc", string.format("%q %q", script, path)}):start()
end
```

Then call it at the end of `stopRecording()` after opening the file:

```lua
if lastOutputFile then
  runTranscription(lastOutputFile)
end
```

Note: replace `${PROJECT_DIR}` with the absolute path to this repo, or move the script somewhere in PATH.

### 5) Test
- Record a short clip → stop → watch for "Transcribing…" then "Transcript copied to clipboard"
- Cmd–V in a text field to verify

### 6) Troubleshooting
- "No transcript returned": ensure audio has speech and Deepgram key is valid
- HTTP 401/403: wrong API key
- Connection errors: check network or try again
- If `pbcopy` fails in headless contexts, Hammerspoon can paste directly via keystrokes
