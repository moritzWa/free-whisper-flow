## free-whisper-flow

Free version of: Whisper Flow, Aqua Voice, Willow Voice, SuperWhisper, MacWhisper

Type faster by using your voice - for free. Press **Cmd+Shift+M** (or the **Fn/Globe key**), speak, and get the transcript pasted or copied the moment you stop. Real-time audio streaming with a live waveform visualization for near-instant results. Hackable, with zero vendor lock-in.

https://github.com/user-attachments/assets/3c51bfbc-3645-4828-95f0-d75fc8b34838

## Installation

Clone this repository and run the installer:

```bash
git clone https://github.com/moritzWa/free-whisper-flow.git
cd free-whisper-flow
./install.sh
```

The installer will:

- Install dependencies (Homebrew, ffmpeg, Hammerspoon, uv)
- Configure your microphone, API key, and Hammerspoon
- Optionally add Hammerspoon to login items for auto-startup

## Usage

1. Press **Cmd+Shift+M** (or **Fn/Globe key**) to start recording. You'll hear a sound and see a waveform.
2. Speak.
3. Press the same key again to stop. A spinner shows while the transcript is being processed.
4. If your cursor is in a text input, the transcript is pasted directly (your clipboard is preserved). Otherwise it's copied to your clipboard.
5. Press **Escape** to cancel a recording.

## Configuration

All settings are in your `.env` file:

```bash
# STT provider: "elevenlabs" (default, more accurate) or "deepgram"
STT_PROVIDER=elevenlabs

# API keys (only the one matching your provider is needed)
ELEVENLABS_API_KEY=your_key_here
DEEPGRAM_API_KEY=your_key_here

# Comma-separated list of preferred mics (first available wins)
MIC_PREFERENCE=BY-GM18CU,MacBook Air Microphone

# Comma-separated list of mics to never use
MIC_BLACKLIST=airpods
```

### STT Providers

- **ElevenLabs Scribe v2** (default) - ~2.3% word error rate, ~2s latency for 8s of audio. Requires an [ElevenLabs API key](https://elevenlabs.io).
- **Deepgram Nova-2** - ~8.4% word error rate, real-time latency. Requires a [Deepgram API key](https://deepgram.com) (comes with $200 in free credits).

Switch providers by changing `STT_PROVIDER` in `.env`. Both API keys can coexist so you can switch back anytime.

### Microphone Selection

The tool auto-detects available microphones on each recording. It checks `MIC_PREFERENCE` in order and picks the first connected device, skipping anything in `MIC_BLACKLIST`. Falls back to system default if nothing matches.

To see your available devices:

```bash
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A 20 "audio devices"
```

### Fn/Globe Key Binding

To use the Fn/Globe key as a trigger, install [Karabiner-Elements](https://karabiner-elements.pqrs.org/) and add a rule to remap Fn to F18. The tool listens for F18 automatically.

## Features

- **Live waveform** - real-time audio level visualization while recording
- **Smart paste** - auto-pastes into text inputs, copies to clipboard otherwise
- **Clipboard preservation** - your clipboard contents are restored after pasting
- **System audio muting** - automatically mutes system audio during recording to prevent feedback
- **Audio boost** - 2x volume boost for better recognition of quiet speech
- **Sound feedback** - distinct start/stop sounds
- **Seamless transitions** - waveform -> spinner -> result notification in a single overlay

## How It Works

`ffmpeg` captures audio from your microphone and pipes it to a Python script via `tee` (splitting to both a level meter for the waveform and the transcription service). The Python script streams audio over a WebSocket to ElevenLabs or Deepgram and collects the transcript. Hammerspoon handles the global hotkey, waveform visualization, and paste/clipboard logic.

## Development

Because this project uses symlinks, any changes you make in the project files are live once you reload Hammerspoon:

```bash
killall Hammerspoon && sleep 1 && open -a Hammerspoon
```

## Requirements

- **macOS**
- An [ElevenLabs](https://elevenlabs.io) or [Deepgram](https://deepgram.com) API key

## Permissions

You will be prompted to grant permissions for:

- **Accessibility**: Hammerspoon needs this for global hotkeys and smart paste detection.
- **Microphone**: macOS will ask on the first recording attempt.

The installer offers to add Hammerspoon to login items, which is recommended so it's always running.
