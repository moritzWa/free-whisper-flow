-- Toggle recording of system audio (BlackHole) + microphone with Cmd–Shift–X

local recordingTask = nil
local lastOutputFile = nil
local outputDirectory = os.getenv("HOME") .. "/Recordings"
local audioSampleRate = 48000
local audioBitrate = "192k"
local fileExtension = "m4a" -- change to "wav" if you prefer

-- Prefer hardcoded Homebrew path; fall back to search (Hammerspoon PATH is minimal)
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
if ffmpegPath then
  print("ffmpeg detected at: " .. ffmpegPath)
  hs.alert.show("ffmpeg: " .. ffmpegPath)
else
  print("ffmpeg NOT found in common paths or shell")
  hs.alert.show("ffmpeg not found. brew install ffmpeg")
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
  lastOutputFile = outFile
  local cmd = string.format([[%s -hide_banner -loglevel error \
    -f avfoundation -i "%s" \
    -f avfoundation -i "%s" \
    -filter_complex "amix=inputs=2:duration=longest:dropout_transition=2" \
    -ar %d -c:a aac -b:a %s "%s"]],
    ffmpegPath, systemAudioDevice, microphoneDevice, audioSampleRate, audioBitrate, outFile)

  print("Starting ffmpeg with command:\n" .. cmd)

  recordingTask = hs.task.new("/bin/bash", function()
    hs.alert.show("Recording saved")
  end, {"-lc", cmd})

  recordingTask:start()
  hs.alert.show("Recording… (Cmd–Shift–X to stop)")
end

local function stopRecording()
  if recordingTask and recordingTask:isRunning() then
    local pid = recordingTask:pid()
    print("Stopping ffmpeg with PID: " .. tostring(pid))
    if pid then
      hs.task.new("/bin/kill", function() end, {"-INT", tostring(pid)}):start()
    else
      recordingTask:terminate()
    end
  end
  recordingTask = nil
  -- Open the saved file shortly after stopping so you can hear it
  if lastOutputFile then
    hs.timer.doAfter(0.6, function()
      if hs.fs.attributes(lastOutputFile) then
        hs.alert.show("Opening: " .. lastOutputFile)
        hs.task.new("/usr/bin/open", function() end, {lastOutputFile}):start()
      else
        print("File not found yet: " .. lastOutputFile)
      end
    end)
  end
end

local function toggleRecording()
  if recordingTask and recordingTask:isRunning() then
    stopRecording()
  else
    startRecording()
  end
end

hs.hotkey.bind({"cmd","shift"}, "x", toggleRecording)
