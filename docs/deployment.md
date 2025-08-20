## Deploying configs into Hammerspoon

This repo includes a script to copy the configuration and scripts into `~/.hammerspoon/whisper-clipboard-cli` and reload Hammerspoon.

### One-time install
```bash
./scripts/post_install.sh
```
- If `~/.hammerspoon/init.lua` is empty/missing, a minimal loader is created to include our config automatically.
- Files copied to `~/.hammerspoon/whisper-clipboard-cli/`:
  - `init.lua` (Hammerspoon config)
  - `scripts/transcribe_and_copy.py`
  - `.env` (from `.env.example` if missing)

### Configure your API key
- Edit `~/.hammerspoon/whisper-clipboard-cli/.env` and set `DEEPGRAM_API_KEY=...`

### After install
- Press Cmd–Shift–X to toggle recording
- After stopping, audio opens; transcription runs; transcript is copied to clipboard
- Sidecar transcript saved next to audio: `~/Recordings/transcripts_tmp/*.txt`

### Updating
- Pull latest repo changes, then re-run:
```bash
./scripts/post_install.sh
```
This overwrites the deployed Hammerspoon config and script with the current project files.
