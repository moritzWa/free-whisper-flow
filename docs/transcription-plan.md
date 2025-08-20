## Plan: Transcription + Clipboard (Deepgram)

- **Goal**: After a recording finishes, automatically send the audio file to Deepgram for transcription and put the text on the macOS clipboard.

### User flow
- Press Cmd–Shift–X → recording starts
- Press Cmd–Shift–X → recording stops
- Transcript is generated and copied to clipboard automatically
- Optional: auto-open transcript viewer or show an alert on success/failure

### Architecture
- **Recorder**: Already implemented via Hammerspoon + ffmpeg + BlackHole
- **Transcriber**: Minimal Python CLI script invoked by Hammerspoon
  - Inputs: path to recorded file
  - Reads `DEEPGRAM_API_KEY` from environment (or `--api-key` flag)
  - Calls Deepgram Pre-recorded API
  - Parses JSON → transcript
  - Copies to clipboard via `pbcopy`
  - Prints transcript for logging
- **Hammerspoon integration**
  - On stop, spawn the Python script (non-blocking)
  - Show an alert: "Transcribing…" and on finish "Transcript copied"

### Why Python script?
- Lower lift than adding HTTP/JSON handling in Lua
- No heavy dependencies; can use `requests` and built-in `subprocess`/`json`
- Clipboard handled natively with `pbcopy`

### File formats
- Current output: `.m4a` (AAC) at 48 kHz. Deepgram supports M4A; no conversion required.

### Error handling
- If API key missing → alert and skip
- If HTTP error → alert and log
- If file unreadable/too large → alert and log

### Security
- Do not hardcode keys in the repo or scripts
- Use environment variable: `DEEPGRAM_API_KEY`
- Optionally support key via `--api-key` for ad-hoc runs

### Future enhancements
- Language detection or prompt hints
- Paste directly to the frontmost app (Hammerspoon can simulate Cmd–V)
- Save transcript alongside audio file
- Add retry with exponential backoff for transient network errors
