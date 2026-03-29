## free-whisper-flow

Free, open-source alternative to [Wispr Flow](https://wispr.flow), [SuperWhisper](https://superwhisper.com), Aqua Voice, and others. Runs locally on Apple Silicon with ~3% word error rate and ~325ms latency - nearly as accurate as ElevenLabs (2.3% WER) and fast enough to feel instant. No subscription, no API key required.

Press **Cmd+Shift+M** (or the **Fn/Globe key**), speak, and get the transcript pasted the moment you stop. Live waveform visualization, smart paste, and zero vendor lock-in.

https://github.com/user-attachments/assets/3c51bfbc-3645-4828-95f0-d75fc8b34838

## Installation

Clone this repository and run the installer:

```bash
git clone https://github.com/moritzWa/free-whisper-flow.git
cd free-whisper-flow
./install.sh
```

The installer will:

- Install dependencies (Homebrew, ffmpeg, Hammerspoon)
- Build the FluidAudio bridge for local transcription
- Walk you through an interactive setup (provider, microphone, hotkey)
- Start Hammerspoon and optionally add it to login items

The FluidAudio model (~600MB) downloads automatically on your first transcription. Run `fwf` anytime to change settings.

## Usage

1. Press **Cmd+Shift+M** (or **Fn/Globe key**) to start recording. You'll hear a sound and see a waveform.
2. Speak.
3. Press the same key again to stop. A spinner shows while the transcript is being processed.
4. If your cursor is in a text input, the transcript is pasted directly (your clipboard is preserved). Otherwise it's copied to your clipboard.
5. Press **Escape** to cancel a recording.

## Configuration

All settings live in `.env` (created by the installer, or run `fwf` to reconfigure):

```bash
# STT provider: "fluidaudio" (local, free), "elevenlabs", or "deepgram"
STT_PROVIDER=fluidaudio

# Hotkey to start/stop recording
HOTKEY=cmd+shift+m

# Microphone preferences
MIC_PREFERENCE=MacBook Air Microphone
MIC_BLACKLIST=airpods

# --- Optional, only if using cloud providers ---
# ELEVENLABS_API_KEY=your_key_here
# DEEPGRAM_API_KEY=your_key_here

# --- Optional: LLM transcript cleanup via Groq (removes filler words) ---
# GROQ_API_KEY=your_key_here
```

### STT Providers

- **FluidAudio** (local, default) - ~3% word error rate, ~0.2s latency. Runs entirely on-device using [FluidAudio](https://github.com/FluidInference/FluidAudio) with the Parakeet TDT 0.6b model on Apple's Neural Engine. Free, offline, no API key needed. One-time model download (~600MB) on first use.
- **ElevenLabs Scribe v2** (cloud) - ~2.3% word error rate, ~2s latency. Requires an [ElevenLabs API key](https://elevenlabs.io).
- **Deepgram Nova-2** (cloud) - ~8.4% word error rate, real-time streaming. Requires a [Deepgram API key](https://deepgram.com) (comes with $200 in free credits).

Switch providers by changing `STT_PROVIDER` in `.env` or running `fwf`.

### Microphone Selection

The tool auto-detects available microphones and picks the first connected device from `MIC_PREFERENCE`, skipping anything in `MIC_BLACKLIST`. Falls back to system default if nothing matches. The selection is cached and refreshes when devices change (e.g. plugging in a mic).

To see your available devices:

```bash
ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A 20 "audio devices"
```

### Hotkey

The default hotkey is **Cmd+Shift+M**. Change it via `HOTKEY` in `.env` (e.g. `HOTKEY=ctrl+alt+r`). Supports `cmd`, `ctrl`, `alt`, `shift` modifiers.

The **Fn/Globe key** also works as a trigger. Install [Karabiner-Elements](https://karabiner-elements.pqrs.org/) and add a rule to remap Fn to F18. The tool listens for F18 automatically.

## Features

- **Live waveform** - real-time audio level visualization while recording
- **Smart paste** - auto-pastes into text inputs, copies to clipboard otherwise
- **Clipboard preservation** - your clipboard contents are restored after pasting
- **System audio muting** - automatically mutes system audio during recording to prevent feedback
- **Audio boost** - 2x volume boost for better recognition of quiet speech
- **Sound feedback** - audio cue on start/stop
- **Seamless transitions** - waveform -> spinner -> result notification in a single overlay

## How It Works

Hammerspoon handles the global hotkey, waveform visualization, and paste/clipboard logic. `ffmpeg` captures audio from your microphone. What happens next depends on the provider:

- **Cloud providers** (ElevenLabs/Deepgram): Audio is piped to a Python script that streams it over a WebSocket to the cloud API in real-time. Transcription results arrive as you speak.
- **FluidAudio** (local): Audio is saved to a temp WAV file while you speak. When you stop, a Swift CLI runs the Parakeet TDT model on Apple's Neural Engine and returns the transcript. No network required.

Both paths support optional LLM cleanup via Groq (removes filler words, fixes punctuation).

## Benchmarks

Measured on M4 MacBook Air (32GB), recording ~6s of speech:

**Start latency** (keypress to audio capture):
- ~96ms with cached mic selection
- ~350ms on first recording after reload (mic device scan)

**Stop-to-paste latency** (stop recording to text appearing):
- **FluidAudio (local)**: ~325ms transcription only, ~500ms with Groq cleanup
- **Deepgram (cloud)**: ~800ms including Groq cleanup (in Python)
- **ElevenLabs (cloud)**: ~800ms including Groq cleanup (in Python)

**Word error rate** (lower is better):
- **ElevenLabs Scribe v2**: ~2.3% - best accuracy
- **FluidAudio Parakeet TDT 0.6b**: ~3% - close to ElevenLabs, runs locally for free
- **Deepgram Nova-2**: ~8.4% - fastest cloud streaming, lower accuracy

**Cost**:
- **FluidAudio**: free, offline, runs on Apple Neural Engine
- **Deepgram**: API pricing ($200 in free credits on signup)
- **ElevenLabs**: API pricing

## Development

Because this project uses symlinks, any changes you make in the project files are live once you reload Hammerspoon:

```bash
killall Hammerspoon && sleep 1 && open -a Hammerspoon
```

## Requirements

- **macOS 14+** and **Apple Silicon** (M1 or later)
- **Xcode** or Command Line Tools (`xcode-select --install`)

That's it. The default local provider (FluidAudio) needs no API keys and works offline. Cloud providers (ElevenLabs, Deepgram) are optional and need API keys.

## Permissions

You will be prompted to grant permissions for:

- **Accessibility**: Hammerspoon needs this for global hotkeys and smart paste detection.
- **Microphone**: macOS will ask on the first recording attempt.

The installer offers to add Hammerspoon to login items, which is recommended so it's always running.
