-- Cmd–Shift–X: record microphone audio
-- After stopping: transcribe with Deepgram → copy transcript to clipboard → optional auto-paste

-- Configurable paths
local homeDirectory = os.getenv("HOME")
local recordingsDirectory = homeDirectory .. "/Recordings"
local transcribeScript = homeDirectory .. "/.hammerspoon/whisper-clipboard-cli/scripts/transcribe_and_copy.py"
local envFilePath = homeDirectory .. "/.hammerspoon/whisper-clipboard-cli/.env"
local uvPath = "/opt/homebrew/bin/uv" -- adjust if uv is elsewhere

-- Behavior
local autoPasteAfterCopy = true

-- Audio settings
local audioSampleRate = 48000
local audioBitrate = "192k"
local fileExtension = "m4a" -- change to "wav" if desired

-- avfoundation device indices (auto-detected dynamically)
local microphoneDevice = nil  -- Will be auto-detected

-- Create custom style for bottom alerts
local bottomStyle = {table.unpack(hs.alert.defaultStyle)}
bottomStyle.atScreenEdge = 2

-- Test alert to verify bottom positioning
hs.alert.show("Config loaded - alerts at bottom", bottomStyle, 3)

-- Internal state
local recordingTask = nil
local lastOutputFile = nil
local recordingAlert = nil

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
  hs.alert.show("ffmpeg not found. brew install ffmpeg", bottomStyle)
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
  if not hs.fs.attributes(uvPath) then
    hs.alert.show("uv not found at " .. uvPath .. " - reinstall required", bottomStyle)
    return
  end
  local apiKey = readEnvVarFromFile(envFilePath, "DEEPGRAM_API_KEY")
  if not apiKey or apiKey == "" then
    hs.alert.show("Set DEEPGRAM_API_KEY in ~/.hammerspoon/whisper-clipboard-cli/.env", bottomStyle)
    return
  end

  hs.alert.show("Transcribing…", bottomStyle)
  local cmd = string.format("%q run --no-project %q --api-key %q %q", uvPath, transcribeScript, apiKey, path)
  hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
    print("📝 Transcription completed with exit code: " .. tostring(exitCode))
    print("📝 Transcription stdout: " .. (stdOut or "(empty)"))
    print("📝 Transcription stderr: " .. (stdErr or "(empty)"))

    if exitCode == 0 then
      hs.alert.show("Copied to clipboard", bottomStyle)
      if autoPasteAfterCopy then
        hs.timer.doAfter(0.05, function()
          hs.eventtap.keyStroke({"cmd"}, "v", 0)
        end)
      end
    else
      print("📝 Transcription failed with exit code: " .. tostring(exitCode))
      if stdErr and #stdErr > 0 then
        print("📝 Error details: " .. stdErr)
      end
      hs.alert.show("Transcription failed", bottomStyle)
    end
  end, {"-lc", cmd}):start()
end

local function getDefaultMicrophone()
  print("Using system default microphone")
  -- Use ":default" to let ffmpeg use the system's default audio input device
  -- This respects the user's Sound Settings preference
  return ":default"
end

local function startRecording()
  if not ffmpegPath then
    hs.alert.show("ffmpeg not available", bottomStyle)
    return
  end

  -- Use system default microphone
  microphoneDevice = getDefaultMicrophone()

  hs.fs.mkdir(recordingsDirectory)
  local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
  local outFile = string.format("%s/audio-%s.%s", recordingsDirectory, timestamp, fileExtension)
  lastOutputFile = outFile

  local cmd = string.format([[%s -hide_banner -loglevel error \
    -f avfoundation -i "%s" \
    -ar %d -c:a aac -b:a %s "%s"]],
    ffmpegPath, microphoneDevice, audioSampleRate, audioBitrate, outFile)

  print("Using microphone device: " .. microphoneDevice .. " for recording")

  recordingTask = hs.task.new("/bin/bash", function() end, {"-lc", cmd})
  recordingTask:start()

  -- Show persistent recording indicator
  recordingAlert = hs.alert.show("🔴 Recording... (Cmd+Shift+M to stop)", bottomStyle, hs.screen.mainScreen(), 86400) -- 24 hours
  hs.alert.show("Recording started", bottomStyle)
end

local function stopRecording()
  print("🛑 stopRecording() called")

  -- Dismiss persistent recording alert
  if recordingAlert then
    hs.alert.closeSpecific(recordingAlert)
    recordingAlert = nil
  end

  if recordingTask and recordingTask:isRunning() then
    local pid = recordingTask:pid()
    print("🛑 Found running task with PID: " .. tostring(pid))
    if pid then
      print("🛑 Sending SIGINT to allow graceful shutdown: " .. tostring(pid))
      hs.execute("kill -INT " .. tostring(pid))
      -- Wait a moment, then force kill if still running
      hs.timer.doAfter(1.0, function()
        hs.execute("kill -KILL " .. tostring(pid) .. " 2>/dev/null || true")
        print("🛑 Backup SIGKILL sent")
      end)
    end
    recordingTask:terminate()
  else
    print("🛑 No recording task running or not running")
  end
  recordingTask = nil
  hs.alert.show("Recording ended", bottomStyle)

  if lastOutputFile then
    print("🛑 Will check file in 0.2 seconds: " .. lastOutputFile)
    hs.timer.doAfter(0.2, function()
      local attrs = hs.fs.attributes(lastOutputFile)
      if attrs then
        print("🛑 File exists, size: " .. (attrs.size or 0) .. " bytes")
        runTranscription(lastOutputFile)
      else
        print("🛑 File does not exist!")
      end
    end)
  else
    print("🛑 No lastOutputFile set")
  end
end

local function toggleRecording()
  print("🔄 toggleRecording() called")
  if recordingTask and recordingTask:isRunning() then
    print("🔄 Task is running, calling stopRecording()")
    stopRecording()
  else
    print("🔄 No task running, calling startRecording()")
    startRecording()
  end
end

hs.hotkey.bind({"cmd","shift"}, "m", toggleRecording)
