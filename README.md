## free-whisper-flow

Free version of: Whisper Flow, Aqua Voice, Willow Voice, SuperWhisper, MacWhisper

Type faster by using your voice—for free. Press **Cmd+Shift+M**, speak, and get the transcript in your clipboard the moment you stop. This tool uses real-time audio streaming for near-instant results. It's hackable, with zero vendor lock-in, using free Deepgram credits that last forever.

https://github.com/user-attachments/assets/3c51bfbc-3645-4828-95f0-d75fc8b34838

## 🚀 Installation

Clone this repository and run the installer:

```bash
git clone https://github.com/your-username/free-whisper-flow.git
cd free-whisper-flow
./install.sh
```

The installer will:

- ✅ Install dependencies (Homebrew, ffmpeg, Hammerspoon, uv)
- 🎤 Configure your microphone, Deepgram API key, and Hammerspoon
- 🚀 Optionally add Hammerspoon to login items for auto-startup

## Usage

1. Press **Cmd+Shift+M** to start recording.
2. Speak.
3. Press **Cmd+Shift+M** again to stop.
4. The transcript is now in your clipboard.
5. Optionally press escape to cancel the recording.

That's it. It works globally across all applications. Optional auto-paste saves you the Cmd+V.

## How It Works

This tool uses `ffmpeg` to capture audio and streams it in real-time to a Python script. The script establishes a WebSocket connection with Deepgram's streaming transcription service. As soon as you stop recording, the final transcript is returned and copied to your clipboard. This streaming approach minimizes latency compared to traditional file-based transcription.

## Development

Because this project uses symlinks, any changes you make in the project files will be live once you reload the Hammerspoon configuration.

The standard "Reload Config" option can be unreliable. For a guaranteed refresh, run the following command in your terminal:

```bash
killall Hammerspoon && sleep 1 && open -a Hammerspoon
```

After running the command, you should see a "Config loaded" notification, confirming that your changes have been applied.

## Requirements

- **macOS**
- A [Deepgram API key](https://deepgram.com) (comes with $200 in free credits).

## Permissions

You will be prompted to grant permissions for:

- **Accessibility**: Hammerspoon needs this for global hotkeys.
- **Microphone**: macOS will ask on the first recording attempt.

The installer offers to add Hammerspoon to login items, which is recommended so it's always running.
