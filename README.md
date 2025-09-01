## Whisper Clipboard CLI

**Own your transcription workflow.** Press **Cmd+Shift+X**, speak, get text in your clipboard instantly. Zero vendor lock-in, hackable, using free Deepgram credits that last forever.

![Demo](demo.gif)

## 🚀 One-Line Install

```bash
npx whisper-clipboard-cli
```

Or clone and run manually:
```bash
git clone https://github.com/degtrdg/whisper-clipboard-cli.git
cd whisper-clipboard-cli
./install.sh
```

The installer will:
- ✅ Install required dependencies (Homebrew, ffmpeg, Hammerspoon)
- 🎤 Auto-detect your microphone
- 🔑 Prompt for your Deepgram API key
- 📦 Set up everything automatically

## Usage

**Cmd+Shift+X** → speak → **Cmd+Shift+X** → text in clipboard

That's it. Works everywhere - Slack, code editors, docs, anything. Optional auto-paste saves you the Cmd+V.

Files: `~/Recordings` (audio) • `~/Recordings/transcripts_tmp` (text)

## Requirements

**Required:**
- macOS (only tested here, but open to PRs for Windows/Linux)
- [Deepgram API key](https://deepgram.com) - $200 worth of credits which basically lasts forever

**Auto-installed by installer:**
- [Homebrew](https://brew.sh) - Package manager for macOS
- [ffmpeg](https://ffmpeg.org) - Audio recording
- [Hammerspoon](https://hammerspoon.org) - System automation and hotkeys
- [uv](https://docs.astral.sh/uv/) - Fast Python runner with automatic dependency management

## Permissions

Grant when prompted:
- **Accessibility** (Hammerspoon needs this for hotkeys)
- **Microphone** (on first recording)

Optional: Enable "Launch Hammerspoon at login"
