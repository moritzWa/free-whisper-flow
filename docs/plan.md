## Plan: Cmd–Shift–X Audio Recorder (Hammerspoon + BlackHole)

- **Goal**: Toggle recording of both system audio and microphone with Cmd–Shift–X; save to `~/Recordings`.

### User flow
- **Toggle**: Cmd–Shift–X starts/stops recording
- **Output**: Timestamped `.m4a` files
- **Autostart**: Hammerspoon launches at login

### Architecture
- **Global hotkey**: Hammerspoon binds Cmd–Shift–X
- **Recorder**: `ffmpeg` run as a background task
- **System audio capture**: BlackHole 2ch virtual device
- **Mixing**: `ffmpeg` `amix` filter (system + mic → one track)

### Dependencies
- Hammerspoon (hotkey + task management)
- ffmpeg (capture + encode)
- BlackHole 2ch (virtual output for system audio)
- Audio MIDI Setup (create a Multi-Output Device so you can hear output while capturing via BlackHole)

### Permissions (macOS)
- Accessibility (Hammerspoon hotkey)
- Microphone (ffmpeg capture)
- Screen Recording: not needed when using BlackHole

### File behavior
- Format: `m4a` (AAC, 48 kHz, 192 kbps) — configurable
- Naming: `audio-YYYY-MM-DD_HH-MM-SS.m4a`
- Location: `~/Recordings` (auto-created)

### Reliability
- Stop via SIGINT so ffmpeg finalizes files
- If device names/indices change, update two config lines in `init.lua`

### Alternatives (later)
- Aggregate Device (merge Mic + BlackHole into one input)
- Native Swift app (ScreenCaptureKit / AVAudioEngine)

### Next steps
- Follow `docs/setup.md` to install and configure
