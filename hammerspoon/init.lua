-- Cmd–Shift–X: record system audio (BlackHole) + microphone
-- After stopping: open audio file and transcribe with Deepgram → copy transcript to clipboard

-- Configurable paths
local homeDirectory = os.getenv("HOME")
local recordingsDirectory = homeDirectory .. "/Recordings"
local transcribeScript = homeDirectory .. "/.hammerspoon/whisper-clipboard-cli/scripts/transcribe_and_copy.py"
local envFilePath = homeDirectory .. "/.hammerspoon/whisper-clipboard-cli/.env"

-- Audio settings
local audioSampleRate = 48000
local audioBitrate = "192k"
local fileExtension = "m4a" -- change to "wav" if desired

-- avfoundation device indices (update if they change on your system)
-- Use: ffmpeg -f avfoundation -list_devices true -i ""
local systemAudioDevice = ":1"   -- BlackHole 2ch
local microphoneDevice  = ":4"   -- MacBook Pro Microphone

-- Internal state
local recordingTask = nil
local lastOutputFile = nil

-- Find ffmpeg in common locations and via a login shell
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
else
  hs.alert.show("ffmpeg not found. brew install ffmpeg")
end

-- Simple .env reader (KEY=VALUE, supports quoted values)
local function readEnvVarFromFile(filePath, key)
  local file = io.open(filePath, "r")
  if not file then return nil end
  for line in file:lines() do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" and not trimmed:match("^#") then
      local k, v = trimmed:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.+)$")
      if k == key and v then
        v = v:gsub('^%s*"', ""):gsub('"%s*$', "")
        v = v:gsub("^%s*'", ""):gsub("'%s*$", "")
        file:close()
        return v
      end
    end
  end
  file:close()
  return nil
end

local function runTranscription(path)
  if not hs.fs.attributes(transcribeScript) then
    print("Transcription script not found: " .. transcribeScript)
    return
  end
  local apiKey = readEnvVarFromFile(envFilePath, "DEEPGRAM_API_KEY")
  if not apiKey or apiKey == "" then
    hs.alert.show("Set DEEPGRAM_API_KEY in ~/.hammerspoon/whisper-clipboard-cli/.env")
    return
  end

  hs.alert.show("Transcribing…")
  local cmd = string.format("%q --api-key %q %q", transcribeScript, apiKey, path)
  hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
    if exitCode == 0 then
      hs.alert.show("Transcript copied to clipboard")
      if stdOut and #stdOut > 0 then print(stdOut) end
    else
      hs.alert.show("Transcription failed")
      if stdErr and #stdErr > 0 then print(stdErr) end
    end
  end, {"-lc", cmd}):start()
end

local function startRecording()
  if not ffmpegPath then
    hs.alert.show("ffmpeg not available")
    return
  end
  hs.fs.mkdir(recordingsDirectory)
  local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
  local outFile = string.format("%s/audio-%s.%s", recordingsDirectory, timestamp, fileExtension)
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

  if lastOutputFile then
    hs.timer.doAfter(0.8, function()
      if hs.fs.attributes(lastOutputFile) then
        hs.alert.show("Opening: " .. lastOutputFile)
        hs.task.new("/usr/bin/open", function() end, {lastOutputFile}):start()
        runTranscription(lastOutputFile)
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
