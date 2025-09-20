## Free Whisper Flow

**Own your transcription workflow.** Press **Cmd+Shift+M**, speak, and get the transcript in your clipboard the moment you stop. This tool uses real-time audio streaming for near-instant results. It's hackable, with zero vendor lock-in, using free Deepgram credits that last forever.

(Free alternative to [SuperWhisper](https://superwhisper.com), [With Aqua](https://withaqua.com/), [Wisper Flow](https://wisprflow.ai), etc)

![Demo](demo.gif)

## 🚀 Installation

Clone this repository and run the installer:

```bash
git clone httpshttps://github.com/moritzWa/free-whisper-flow.git # Please replace with the actual repo URL
cd free-whisper-flow
./install.sh
```

The installer will:

- ✅ Install required dependencies (Homebrew, ffmpeg, Hammerspoon, uv)
- 🎤 Use your system's default microphone
- 🔑 Prompt for your Deepgram API key
- 📦 Set up the Hammerspoon configuration automatically

## Usage

1. Press **Cmd+Shift+M** to start recording.
2. Speak.
3. Press **Cmd+Shift+M** again to stop.
4. The transcript is now in your clipboard.

That's it. It works globally across all applications. Optional auto-paste saves you the Cmd+V.

## How It Works

This tool uses `ffmpeg` to capture audio and streams it in real-time to a Python script. The script establishes a WebSocket connection with Deepgram's streaming transcription service. As soon as you stop recording, the final transcript is returned and copied to your clipboard. This streaming approach minimizes latency compared to traditional file-based transcription.

## Requirements

- **macOS**
- A [Deepgram API key](https://deepgram.com) (comes with $200 in free credits).

The installer will automatically handle:

- [Homebrew](https://brew.sh): Package manager for macOS.
- [ffmpeg](https://ffmpeg.org): For real-time audio capture.
- [Hammerspoon](https://hammerspoon.org): For global hotkey management.
- [uv](https://docs.astral.sh/uv/): A fast Python installer and runner.

## Permissions

You will be prompted to grant permissions for:

- **Accessibility**: Hammerspoon needs this for global hotkeys.
- **Microphone**: macOS will ask on the first recording attempt.

We recommend enabling "Launch Hammerspoon at login" for convenience.
