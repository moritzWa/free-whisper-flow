-- Cmd–Shift–M: record microphone audio
-- After stopping: transcribe with Deepgram → copy transcript to clipboard → optional auto-paste

-- Configurable paths
local homeDirectory = os.getenv("HOME")
local recordingsDirectory = homeDirectory .. "/Recordings"
local transcribeScript = homeDirectory .. "/.hammerspoon/free-whisper-flow/scripts/transcribe_and_copy.py"
local envFilePath = homeDirectory .. "/.hammerspoon/free-whisper-flow/.env"
local uvPath = "/opt/homebrew/bin/uv" -- adjust if uv is elsewhere

-- Audio settings
local audioSampleRate = 16000 -- Reduced for efficiency
local audioBitrate = "256k"    -- Bitrate for pcm_s16le
local fileExtension = "m4a" -- change to "wav" if desired

-- avfoundation device indices (auto-detected dynamically)
local microphoneDevice = nil  -- Will be auto-detected

-- Microphone preference and blacklist (loaded from .env, comma-separated)
-- MIC_PREFERENCE=BY-GM18CU,MacBook Air Microphone
-- MIC_BLACKLIST=airpods
local function splitCsv(str)
  local result = {}
  if not str or str == "" then return result end
  for item in str:gmatch("([^,]+)") do
    item = item:gsub("^%s+", ""):gsub("%s+$", "")
    if item ~= "" then table.insert(result, item) end
  end
  return result
end

-- Create custom style for bottom alerts
local bottomStyle = {table.unpack(hs.alert.defaultStyle)}
bottomStyle.atScreenEdge = 2

-- Test alert to verify bottom positioning
hs.alert.show("Config loaded - alerts at bottom", bottomStyle, 3)

-- Ensure Hammerspoon CLI tool is installed for IPC
hs.ipc.cliInstall()

-- Internal state
local recordingTask = nil
local lastOutputFile = nil
local recordingAlert = nil
local recordingModal = nil
local wasCancelled = false

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

-- Load mic config from .env (falls back to system default if not set)
local micPreference = splitCsv(readEnvVarFromFile(envFilePath, "MIC_PREFERENCE") or "")
local micBlacklist  = splitCsv(readEnvVarFromFile(envFilePath, "MIC_BLACKLIST") or "")

-- STT provider: "elevenlabs" (default) or "deepgram"
local sttProvider = readEnvVarFromFile(envFilePath, "STT_PROVIDER") or "elevenlabs"
print("STT provider: " .. sttProvider)

-- Feedback sounds: same sound (Pop), higher pitch on start, lower on stop
local popSoundPath = "/System/Library/Sounds/Pop.aiff"
local function playSound(rate)
  hs.task.new("/usr/bin/afplay", nil, {"--rate", tostring(rate), popSoundPath}):start()
end

local function runTranscriptionStream(task)
  if not hs.fs.attributes(transcribeScript) then
    print("Transcription script not found: " .. transcribeScript)
    return
  end
  if not hs.fs.attributes(uvPath) then
    hs.alert.show("uv not found at " .. uvPath .. " - reinstall required", bottomStyle)
    return
  end
  local apiKeyVar = sttProvider == "elevenlabs" and "ELEVENLABS_API_KEY" or "DEEPGRAM_API_KEY"
  local apiKey = readEnvVarFromFile(envFilePath, apiKeyVar)
  if not apiKey or apiKey == "" then
    hs.alert.show("Set " .. apiKeyVar .. " in ~/.hammerspoon/free-whisper-flow/.env", bottomStyle)
    return
  end

  task:setCallback(function(exitCode, stdOut, stdErr)
    -- If the cancellation flag is set, do nothing.
    if wasCancelled then
        print("📝 Task callback ignored due to cancellation.")
        return
    end
    print("📝 Transcription completed with exit code: " .. tostring(exitCode))
    print("📝 Transcription stdout: " .. (stdOut or "(empty)"))
    print("📝 Transcription stderr: " .. (stdErr or "(empty)"))

    if exitCode == 0 and stdOut and #stdOut > 0 then
      -- Check if the focused UI element is a text input field
      local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
      local isTextInput = false
      if focusedElement then
        local role = focusedElement:attributeValue("AXRole")
        isTextInput = (role == "AXTextField" or role == "AXTextArea" or role == "AXComboBox" or role == "AXSearchField")
      end

      if isTextInput then
        hs.alert.show("Pasted", bottomStyle)
        hs.timer.doAfter(0.05, function()
          hs.eventtap.keyStroke({"cmd"}, "v", 0)
        end)
      else
        hs.alert.show("Copied to clipboard", bottomStyle)
      end
    else
      print("📝 Transcription failed with exit code: " .. tostring(exitCode))
      if stdErr and #stdErr > 0 then
        print("📝 Error details: " .. stdErr)
      end
      hs.alert.show("Transcription failed", bottomStyle)
    end
  end)
  task:start()
end

local function getAvailableAudioDevices()
  -- Parse ffmpeg's avfoundation device list to get audio device names and indices
  local output = hs.execute(ffmpegPath .. " -f avfoundation -list_devices true -i '' 2>&1")
  local devices = {}
  local inAudio = false
  for line in output:gmatch("[^\r\n]+") do
    if line:find("audio devices") then
      inAudio = true
    elseif line:find("video devices") then
      inAudio = false
    elseif inAudio then
      local idx, name = line:match("%[(%d+)%]%s+(.+)$")
      if idx and name then
        table.insert(devices, { index = tonumber(idx), name = name })
      end
    end
  end
  return devices
end

local function getDefaultMicrophone()
  -- If no preferences configured, just use system default
  if #micPreference == 0 then
    print("No MIC_PREFERENCE set, using system default microphone")
    return ":default"
  end

  local devices = getAvailableAudioDevices()
  print("Available audio devices:")
  for _, d in ipairs(devices) do
    print("  [" .. d.index .. "] " .. d.name)
  end

  -- Check preference list in order
  for _, pref in ipairs(micPreference) do
    for _, d in ipairs(devices) do
      if d.name:lower():find(pref:lower(), 1, true) then
        -- Check blacklist
        local blocked = false
        for _, bl in ipairs(micBlacklist) do
          if d.name:lower():find(bl:lower(), 1, true) then
            blocked = true
            break
          end
        end
        if not blocked then
          print("Selected microphone: [" .. d.index .. "] " .. d.name)
          return ":" .. tostring(d.index)
        end
      end
    end
  end

  -- Fallback: first non-blacklisted device
  for _, d in ipairs(devices) do
    local blocked = false
    for _, bl in ipairs(micBlacklist) do
      if d.name:lower():find(bl:lower(), 1, true) then
        blocked = true
        break
      end
    end
    if not blocked then
      print("Fallback microphone: [" .. d.index .. "] " .. d.name)
      return ":" .. tostring(d.index)
    end
  end

  print("No suitable microphone found, using system default")
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

  -- Note: We no longer save a file, but ffmpeg might need a dummy path in some configs.
  -- The important part is piping to stdout with '-'.

  local ffmpegCmd = string.format([[%s -hide_banner -loglevel error \
    -f avfoundation -i "%s" \
    -af "volume=2.0" \
    -ar %d -ac 1 -c:a pcm_s16le -f s16le -]],
    ffmpegPath, microphoneDevice, audioSampleRate)

  local apiKeyVar = sttProvider == "elevenlabs" and "ELEVENLABS_API_KEY" or "DEEPGRAM_API_KEY"
  local apiKeyForCmd = readEnvVarFromFile(envFilePath, apiKeyVar)
  local pythonCmd = string.format("%q run --no-project %q --provider %s --api-key %q", uvPath, transcribeScript, sttProvider, apiKeyForCmd)

  local fullCmd = ffmpegCmd .. " | " .. pythonCmd

  print("Using microphone device: " .. microphoneDevice .. " for recording")
  print("Executing streaming command: " .. fullCmd)


  -- Play start sound (higher pitch)
  playSound(2)

  wasCancelled = false -- Reset the flag each time we start
  recordingTask = hs.task.new("/bin/bash", nil, {"-lc", fullCmd})
  runTranscriptionStream(recordingTask)


  -- Show persistent recording indicator
  recordingAlert = hs.alert.show("🔴 Transcribing... (Cmd+Shift+M to stop)", bottomStyle, hs.screen.mainScreen(), 86400) -- 24 hours

  -- Enter the modal to capture the escape key
  recordingModal:enter()
end

local function stopRecording()
  print("🛑 stopRecording() called")

  -- Play stop sound (lower pitch)
  playSound(0.8)

  -- Exit the modal so the escape key is released
  recordingModal:exit()

  -- Dismiss persistent recording alert
  if recordingAlert then
    hs.alert.closeSpecific(recordingAlert)
    recordingAlert = nil
  end

  if recordingTask and recordingTask:isRunning() then
    local pid = recordingTask:pid()
    print("🛑 Found parent task with PID: " .. tostring(pid))
    if pid then
      -- Find the ffmpeg process which is a child of our task's shell and kill it.
      -- This allows the python script to finish gracefully.
      local pgrep_cmd = "pgrep -P " .. tostring(pid) .. " ffmpeg"
      local ffmpeg_pid_str = hs.execute(pgrep_cmd):gsub("[\n\r]", "")
      if ffmpeg_pid_str and ffmpeg_pid_str ~= "" then
          print("🛑 Found ffmpeg child PID: " .. ffmpeg_pid_str .. ". Sending SIGINT.")
          hs.execute("kill -INT " .. ffmpeg_pid_str)
      else
          print("🛑 Could not find ffmpeg child PID. Killing process group as fallback.")
          hs.execute("kill -INT -" .. tostring(pid)) -- Fallback
      end
    end
    -- The main task will terminate automatically when the pipe closes
  else
    print("🛑 No recording task running or not running")
  end
  recordingTask = nil
end

local function cancelRecording()
  print("🚫 Cancelling recording via Escape key.")

  wasCancelled = true

  if recordingAlert then
    hs.alert.closeSpecific(recordingAlert)
    recordingAlert = nil
  end

  if recordingTask and recordingTask:isRunning() then
    recordingTask:terminate()
  end
  recordingTask = nil

  hs.alert.show("Cancelled", bottomStyle, 2)

  recordingModal:exit()
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

recordingModal = hs.hotkey.modal.new()
recordingModal:bind({}, "escape", function()
    cancelRecording()
end)

hs.hotkey.bind({"cmd","shift"}, "m", toggleRecording)
