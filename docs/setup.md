## Setup: Cmd–Shift–X Audio Recorder (Hammerspoon + BlackHole)

Lowest-lift path to record system audio + mic with a global hotkey.

### 1) Install prerequisites
```bash
# Homebrew (if needed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Tools
brew install ffmpeg
brew install --cask hammerspoon
brew install blackhole-2ch
```

### 2) Route system audio to BlackHole while you can still hear it
- Open “Audio MIDI Setup” (Spotlight → search it)
- Click + → Create Multi-Output Device
- Check your speakers/headphones AND “BlackHole 2ch”
- System Settings → Sound → Output: choose that Multi-Output Device

### 3) Find device names or indices for ffmpeg
List devices:
```bash
ffmpeg -f avfoundation -list_devices true -i ""
```
Note the exact name or index for:
- **System audio** (BlackHole)
- **Microphone** (built-in or external)

### 4) Configure Hammerspoon
Create or replace `~/.hammerspoon/init.lua` with this. Update the two device lines to match your system (use either `:"Name"` or `:N` index):

```lua
-- Toggle recording of system audio (BlackHole) + microphone with Cmd–Shift–X

local recordingTask = nil
local outputDirectory = os.getenv("HOME") .. "/Recordings"
local audioSampleRate = 48000
local audioBitrate = "192k"
local fileExtension = "m4a" -- change to "wav" if you prefer

-- Find ffmpeg path
local ffmpegPath = hs.execute("which ffmpeg"):gsub("%s+$", "")
if ffmpegPath == "" then
  hs.alert.show("ffmpeg not found in PATH. Install via Homebrew.")
end

-- UPDATE THESE to your avfoundation device names or indices
-- Examples: ":BlackHole 2ch" or ":1"; ":MacBook Pro Microphone" or ":0"
local systemAudioDevice = ":BlackHole 2ch"
local microphoneDevice  = ":MacBook Pro Microphone"

local function startRecording()
  hs.fs.mkdir(outputDirectory)
  local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
  local outFile = string.format("%s/audio-%s.%s", outputDirectory, timestamp, fileExtension)
  local cmd = string.format([[%s -hide_banner -loglevel error \
    -f avfoundation -i "%s" \
    -f avfoundation -i "%s" \
    -filter_complex "amix=inputs=2:duration=longest:dropout_transition=2" \
    -ar %d -c:a aac -b:a %s "%s"]],
    ffmpegPath, systemAudioDevice, microphoneDevice, audioSampleRate, audioBitrate, outFile)

  recordingTask = hs.task.new("/bin/bash", function()
    hs.alert.show("Recording saved")
  end, {"-lc", cmd})

  recordingTask:start()
  hs.alert.show("Recording… (Cmd–Shift–X to stop)")
end

local function stopRecording()
  if recordingTask then
    -- SIGINT lets ffmpeg finalize the file cleanly
    recordingTask:sendSignal("int")
    recordingTask = nil
  end
end

local function toggleRecording()
  if recordingTask then
    stopRecording()
  else
    startRecording()
  end
end

hs.hotkey.bind({"cmd","shift"}, "x", toggleRecording)
```

### 5) Grant permissions
- Launch Hammerspoon → allow **Accessibility**
- First recording → allow **Microphone**

### 6) Start at login
- Hammerspoon → Preferences → General → enable “Launch Hammerspoon at login”

### 7) Quick test
- Press Cmd–Shift–X → speak and play some music
- Press Cmd–Shift–X again
- Check `~/Recordings` for a timestamped file

### Troubleshooting
- **No system audio**: Ensure Output device is your Multi-Output Device that includes BlackHole.
- **Wrong devices**: Re-run the list command and update `systemAudioDevice` / `microphoneDevice`.
- **ffmpeg not found**: Ensure Homebrew’s bin is in PATH; `which ffmpeg` should return something like `/opt/homebrew/bin/ffmpeg`.
- **Clipping**: Lower volumes or change `amix` params; you can add `:normalize=0` and keep source levels low.
- **Prefer WAV**: Set `fileExtension = "wav"` and change codec to `-c:a pcm_s16le` (larger files).
- **Use indices**: Names can change across OS updates; indices (e.g., `":1"`) are often more stable.
