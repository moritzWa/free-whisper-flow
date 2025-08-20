## Setup: Transcription + Clipboard

This adds a Python CLI that sends the recorded audio to Deepgram and copies the transcript to your clipboard.

### 1) Use uv to run the script with deps (recommended)
```bash
# Once: install uv (fast Python package/runtime manager)
brew install uv

# Run directly; uv will provision deps per-script using inline metadata
uv run scripts/transcribe_and_copy.py /path/to/audio.m4a --api-key $DEEPGRAM_API_KEY
```

The script declares its dependencies inline (requests, certifi) so users don't need a requirements.txt or virtualenv.

### 2) Hammerspoon integration
Update `~/.hammerspoon/whisper-clipboard-cli/init.lua` to call the script via uv:

```lua
local uvPath = "/opt/homebrew/bin/uv"  -- adjust if needed
local scriptPath = os.getenv("HOME") .. "/.hammerspoon/whisper-clipboard-cli/scripts/transcribe_and_copy.py"
local apiKey = readEnvVarFromFile(envFilePath, "DEEPGRAM_API_KEY")
local cmd = string.format("%q run --no-project %q --api-key %q %q", uvPath, scriptPath, apiKey, lastOutputFile)
```

If uv is not installed, fall back to `python3`.

### 3) Behavior
- Transcript saved to `~/Recordings/transcripts_tmp/*.txt`
- Transcript copied to clipboard (`pbcopy`)
- On errors, messages are printed in Hammerspoon Console and a brief alert is shown

### 4) Troubleshooting
- If cert errors occur, ensure `uv` is installed; it vendors certifi via requests
- If Hammerspoon can't find `uv`, update the `uvPath` or add it to PATH
