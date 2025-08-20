## Cmd–Shift–X Audio Recorder (macOS)

Press Cmd–Shift–X to start/stop recording a single audio file that mixes your system audio (what you hear) and your microphone. Files are saved to `~/Recordings`.

- **Platform**: macOS
- **Approach**: Hammerspoon hotkey + ffmpeg recorder + BlackHole virtual device
- **Why**: Lowest lift, no app to build, works offline

### Quick start

1) Install tools
```bash
# Homebrew (if needed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install ffmpeg
brew install --cask hammerspoon
brew install blackhole-2ch
```

2) Create a Multi-Output Device
- Open “Audio MIDI Setup” → + → Create Multi-Output Device
- Select your speakers/headphones AND “BlackHole 2ch”
- System Settings → Sound → Output: choose the new Multi-Output Device

3) Identify audio devices
```bash
ffmpeg -f avfoundation -list_devices true -i ""
```
Note the BlackHole device and your microphone (name or index).

4) Add the hotkey script to Hammerspoon
- Create/edit `~/.hammerspoon/init.lua` and paste the script from [`docs/setup.md`](docs/setup.md)
- Update `systemAudioDevice` and `microphoneDevice`

5) Permissions & login
- Open Hammerspoon → allow **Accessibility**
- First record → allow **Microphone**
- Hammerspoon → Preferences → enable “Launch at login”

6) Use it
- Cmd–Shift–X to start
- Cmd–Shift–X to stop
- Find files in `~/Recordings`

### Transcription + Clipboard
- To automatically transcribe the audio with Deepgram and copy it to the clipboard, follow:
  - Plan: [`docs/transcription-plan.md`](docs/transcription-plan.md)
  - Setup guide and Python script: [`docs/transcription-setup.md`](docs/transcription-setup.md)

### Notes
- To record WAV instead of M4A: set `fileExtension = "wav"` and change codec to `-c:a pcm_s16le` in the script.
- If system audio is missing, ensure Output is your Multi-Output Device that includes BlackHole.
