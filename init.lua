-- Toggle recording of system audio (BlackHole) + microphone with Cmd–Shift–X

local recordingTask = nil
local outputDirectory = os.getenv("HOME") .. "/Recordings"
local audioSampleRate = 48000
local audioBitrate = "192k"
local fileExtension = "m4a" -- change to "wav" if you prefer

-- Robustly find ffmpeg (Hammerspoon's PATH may be minimal)
local function findFFmpeg()
  local candidates = {
    "/opt/homebrew/bin/ffmpeg",
    "/usr/local/bin/ffmpeg",
    "/usr/bin/ffmpeg",
  }
  for _, p in ipairs(candidates) do
    if hs.fs.attributes(p) then return p end
  end
  local fromWhich = hs.execute("/bin/bash -lc 'which ffmpeg'"):gsub("%s+$", "")
  if fromWhich ~= "" then return fromWhich end
  return nil
end

local ffmpegPath = findFFmpeg()
if not ffmpegPath then
  hs.alert.show("ffmpeg not found. Install via Homebrew: brew install ffmpeg")
end

-- Using indices from your device list: BlackHole 2ch (:1) and MacBook Pro Microphone (:4)
local systemAudioDevice = ":1"
local microphoneDevice  = ":4"

local function startRecording()
  if not ffmpegPath then
    hs.alert.show("ffmpeg not available")
    return
  end
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
  if recordingTask and recordingTask:isRunning() then
    local pid = recordingTask:pid()
    if pid then
      -- Send SIGINT so ffmpeg finalizes the file cleanly
      hs.task.new("/bin/kill", function() end, {"-INT", tostring(pid)}):start()
    else
      -- Fallback: terminate the task (may not finalize container in rare cases)
      recordingTask:terminate()
    end
  end
  recordingTask = nil
end

local function toggleRecording()
  if recordingTask and recordingTask:isRunning() then
    stopRecording()
  else
    startRecording()
  end
end

hs.hotkey.bind({"cmd","shift"}, "x", toggleRecording)
