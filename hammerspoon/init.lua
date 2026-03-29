-- Cmd–Shift–M: record microphone audio
-- After stopping: transcribe with Deepgram → copy transcript to clipboard → optional auto-paste

-- File-based logging so we can debug from terminal
local fwfLogPath = "/tmp/fwf_debug.log"
local function fwfLog(msg)
  local f = io.open(fwfLogPath, "a")
  if f then
    f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
    f:close()
  end
  print(msg)
end

-- Configurable paths
local homeDirectory = os.getenv("HOME")
local recordingsDirectory = homeDirectory .. "/Recordings"
local transcribeScript = homeDirectory .. "/.hammerspoon/free-whisper-flow/scripts/transcribe_and_copy.py"
local levelMeterScript = homeDirectory .. "/.hammerspoon/free-whisper-flow/scripts/level_meter.py"
local envFilePath = homeDirectory .. "/.hammerspoon/free-whisper-flow/.env"
local uvPath = "/opt/homebrew/bin/uv" -- adjust if uv is elsewhere
local levelFilePath = "/tmp/fwf_level.txt"
local fluidaudioBridge = homeDirectory .. "/.hammerspoon/free-whisper-flow/tools/fluidaudio-bridge/.build/release/fluidaudio-bridge"
local fluidaudioTempWav = "/tmp/fwf_recording.wav"

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
local savedClipboard = nil
local savedVolume = nil
local recordingStartTime = nil
local MIN_RECORDING_SECONDS = 0.8
local volumeFadeTimer = nil

local function fadeVolume(dev, targetVolume, duration, callback)
  if volumeFadeTimer then volumeFadeTimer:stop(); volumeFadeTimer = nil end
  local startVol = dev:outputVolume()
  local steps = 15
  local interval = duration / steps
  local step = 0
  volumeFadeTimer = hs.timer.doEvery(interval, function()
    step = step + 1
    local t = step / steps
    local vol = startVol + (targetVolume - startVol) * t
    dev:setOutputVolume(vol)
    if step >= steps then
      volumeFadeTimer:stop()
      volumeFadeTimer = nil
      if callback then callback() end
    end
  end)
end

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

-- Invalidate cached mic when audio devices change (e.g. AirPods connect/disconnect)
local micWatcherReady = false
hs.audiodevice.watcher.setCallback(function(event)
  if event == "dev#" and micWatcherReady then
    fwfLog("Audio devices changed, clearing cached mic")
    microphoneDevice = nil
  end
end)
hs.audiodevice.watcher.start()
-- Ignore device events for the first 3s (startup noise), then enable cache clearing
hs.timer.doAfter(3, function() micWatcherReady = true end)

-- Apps where we should NEVER auto-paste (only copy to clipboard)
-- Configurable via NEVER_PASTE_APPS in .env (comma-separated bundle IDs)
local defaultNeverPasteApps = {
  "com.apple.finder",
  "com.apple.Preview",
}
local neverPasteAppsEnv = splitCsv(readEnvVarFromFile(envFilePath, "NEVER_PASTE_APPS") or "")
local neverPasteSet = {}
for _, id in ipairs(defaultNeverPasteApps) do neverPasteSet[id] = true end
for _, id in ipairs(neverPasteAppsEnv) do neverPasteSet[id] = true end

-- Detect whether we should auto-paste into the current context.
-- Default: YES (paste). Only skip for deny-listed apps or when no app is focused.
-- Logs detailed diagnostics to the Hammerspoon console for debugging.
local function isTextInput()
  local frontApp = hs.application.frontmostApplication()
  local bundleId = frontApp and frontApp:bundleID() or "unknown"
  local appName = frontApp and frontApp:name() or "unknown"

  -- Log focused element details for debugging
  local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if focusedElement then
    local role = focusedElement:attributeValue("AXRole") or "nil"
    local subrole = focusedElement:attributeValue("AXSubrole") or "nil"
    fwfLog(string.format("FWF isTextInput: app=%s (%s) role=%s subrole=%s", appName, bundleId, role, subrole))
  else
    fwfLog(string.format("FWF isTextInput: app=%s (%s) focusedElement=nil", appName, bundleId))
  end

  -- Deny-list: never paste in these apps
  if neverPasteSet[bundleId] then
    fwfLog("FWF isTextInput: DENY-LISTED app, clipboard only")
    return false
  end

  -- No frontmost app (e.g. desktop focused)
  if not frontApp then
    fwfLog("FWF isTextInput: no frontmost app, clipboard only")
    return false
  end

  -- Default: paste
  fwfLog("FWF isTextInput: defaulting to PASTE")
  return true
end

-- STT provider: "elevenlabs" (default), "deepgram", or "fluidaudio"
local sttProvider = readEnvVarFromFile(envFilePath, "STT_PROVIDER") or "elevenlabs"
print("STT provider: " .. sttProvider)

-- Cache API keys at init time (avoid reading .env on every recording)
local cachedApiKey = nil
if sttProvider == "elevenlabs" then
  cachedApiKey = readEnvVarFromFile(envFilePath, "ELEVENLABS_API_KEY")
elseif sttProvider == "deepgram" then
  cachedApiKey = readEnvVarFromFile(envFilePath, "DEEPGRAM_API_KEY")
end
local cachedGroqKey = readEnvVarFromFile(envFilePath, "GROQ_API_KEY")
if cachedGroqKey == "" then cachedGroqKey = nil end

-- Feedback sound: Pop.aiff, pre-loaded for instant playback
local feedbackSound = hs.sound.getByFile("/System/Library/Sounds/Pop.aiff")
local function playSound()
  feedbackSound:stop()
  feedbackSound:play()
end

-- Shared overlay style constants
local OVERLAY_BG = { red = 0.1, green = 0.1, blue = 0.1, alpha = 0.85 }
local OVERLAY_RADIUS = 10
local OVERLAY_BOTTOM_OFFSET = 40

-- Waveform visualization
local waveformCanvas = nil
local waveformTimer = nil
local NUM_BARS = 30
local BAR_WIDTH = 4
local BAR_GAP = 2
local CANVAS_HEIGHT = 40
local CANVAS_PADDING = 12
local levelHistory = {}

-- Status overlay: shows spinner or result text in the same pill as the waveform
local spinnerTimer = nil
local spinnerAngle = 0
local resultTimer = nil

local function showSpinnerInCanvas()
  -- Replace waveform bars with a spinner in the same canvas
  if not waveformCanvas then return end

  -- Stop waveform updates
  if waveformTimer then waveformTimer:stop(); waveformTimer = nil end

  -- Hide all bar elements by making them transparent
  for i = 1, NUM_BARS do
    waveformCanvas[i + 1].fillColor = { red = 1, green = 1, blue = 1, alpha = 0 }
  end

  -- Add spinner dots (8 dots in a circle)
  local cx = waveformCanvas:frame().w / 2
  local cy = waveformCanvas:frame().h / 2
  local radius = 12
  local dotSize = 4
  local numDots = 8

  for i = 1, numDots do
    waveformCanvas:appendElements({
      type = "circle",
      action = "fill",
      fillColor = { red = 1, green = 1, blue = 1, alpha = 0.15 },
      radius = dotSize / 2,
      center = { x = cx, y = cy },
    })
  end

  spinnerAngle = 0
  spinnerTimer = hs.timer.doEvery(0.08, function()
    if not waveformCanvas then return end
    spinnerAngle = spinnerAngle + (2 * math.pi / numDots)
    local baseIdx = NUM_BARS + 1  -- after background + bars
    for i = 1, numDots do
      local angle = spinnerAngle + (i - 1) * (2 * math.pi / numDots)
      local dx = cx + radius * math.cos(angle)
      local dy = cy + radius * math.sin(angle)
      -- Fade: the "leading" dot is brightest
      local a = 0.15 + 0.75 * ((numDots - i) / numDots)
      waveformCanvas[baseIdx + i].center = { x = dx, y = dy }
      waveformCanvas[baseIdx + i].fillColor = { red = 1, green = 1, blue = 1, alpha = a }
    end
  end)
end

local function showResultInCanvas(text, duration)
  duration = duration or 1
  if not waveformCanvas then
    -- Canvas was already destroyed (e.g. cancel), nothing to show
    return
  end

  -- Stop spinner
  if spinnerTimer then spinnerTimer:stop(); spinnerTimer = nil end

  -- Hide spinner dots
  local baseIdx = NUM_BARS + 1
  local totalElements = waveformCanvas:elementCount()
  for i = baseIdx + 1, totalElements do
    waveformCanvas[i].fillColor = { red = 1, green = 1, blue = 1, alpha = 0 }
  end

  -- Add result text
  local canvasFrame = waveformCanvas:frame()
  waveformCanvas:appendElements({
    type = "text",
    text = text,
    textColor = { red = 1, green = 1, blue = 1, alpha = 0.9 },
    textAlignment = "center",
    textFont = ".AppleSystemUIFont",
    textSize = 18,
    frame = { x = 0, y = (canvasFrame.h - 22) / 2, w = canvasFrame.w, h = 22 },
  })

  -- Auto-dismiss after duration
  -- Store reference to the canvas we want to delete, in case the global changes
  local canvasToDelete = waveformCanvas
  resultTimer = hs.timer.doAfter(duration, function()
    print("📝 Result timer fired, cleaning up canvas")
    if canvasToDelete then
      canvasToDelete:delete()
    end
    -- Clear globals if they still point to this canvas
    if waveformCanvas == canvasToDelete then
      waveformCanvas = nil
    end
    resultTimer = nil
  end)
end

local function destroyWaveformCanvas()
  if waveformTimer then waveformTimer:stop(); waveformTimer = nil end
  if spinnerTimer then spinnerTimer:stop(); spinnerTimer = nil end
  if resultTimer then resultTimer:stop(); resultTimer = nil end
  if waveformCanvas then
    waveformCanvas:delete()
    waveformCanvas = nil
  end
  os.remove(levelFilePath)
end

local function createWaveformCanvas()
  -- Clean up any existing canvas (e.g. lingering "Cancelled" overlay)
  destroyWaveformCanvas()

  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local frame = screen:frame()
  local totalWidth = NUM_BARS * (BAR_WIDTH + BAR_GAP) - BAR_GAP + (CANVAS_PADDING * 2)
  local totalHeight = CANVAS_HEIGHT + (CANVAS_PADDING * 2)

  waveformCanvas = hs.canvas.new({
    x = (frame.w - totalWidth) / 2,
    y = frame.h - totalHeight - OVERLAY_BOTTOM_OFFSET,
    w = totalWidth,
    h = totalHeight,
  })

  -- Background with rounded corners
  waveformCanvas:appendElements({
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = OVERLAY_RADIUS, yRadius = OVERLAY_RADIUS },
    fillColor = OVERLAY_BG,
  })

  -- Add bar elements
  for i = 1, NUM_BARS do
    waveformCanvas:appendElements({
      type = "rectangle",
      action = "fill",
      roundedRectRadii = { xRadius = 2, yRadius = 2 },
      fillColor = { red = 1, green = 1, blue = 1, alpha = 0.9 },
      frame = {
        x = CANVAS_PADDING + (i - 1) * (BAR_WIDTH + BAR_GAP),
        y = CANVAS_PADDING + CANVAS_HEIGHT / 2 - 1,
        w = BAR_WIDTH,
        h = 2,
      },
    })
  end

  waveformCanvas:level(hs.canvas.windowLevels.overlay)
  waveformCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)

  waveformCanvas:show()

  -- Initialize level history
  levelHistory = {}
  for i = 1, NUM_BARS do
    levelHistory[i] = 0
  end
end

local function updateWaveform()
  if not waveformCanvas then return end

  -- Read current level from file
  local level = 0
  local f = io.open(levelFilePath, "r")
  if f then
    local val = f:read("*a")
    f:close()
    level = tonumber(val) or 0
  end

  -- Shift history left, add new level on right
  for i = 1, NUM_BARS - 1 do
    levelHistory[i] = levelHistory[i + 1]
  end
  levelHistory[NUM_BARS] = level

  -- Update bar heights (element indices are offset by 1 for the background)
  for i = 1, NUM_BARS do
    local l = levelHistory[i]
    -- Aggressive scaling: sqrt for more visible quiet speech, then boost
    local scaled = math.min(1.0, math.sqrt(l) * 2.5)
    -- Minimum bar height so there's always visible activity
    local minHeight = 4
    local barHeight = math.max(minHeight, scaled * CANVAS_HEIGHT)
    local yPos = CANVAS_PADDING + (CANVAS_HEIGHT - barHeight) / 2

    local alpha = 0.5 + scaled * 0.5

    waveformCanvas[i + 1].frame = {
      x = CANVAS_PADDING + (i - 1) * (BAR_WIDTH + BAR_GAP),
      y = yPos,
      w = BAR_WIDTH,
      h = barHeight,
    }
    waveformCanvas[i + 1].fillColor = { red = 1, green = 1, blue = 1, alpha = alpha }
  end
end

-- Shared handler for transcription results (used by both cloud and local providers)
local function handleTranscriptionResult(exitCode, stdOut, stdErr)
  if wasCancelled then
    fwfLog("Task callback ignored due to cancellation.")
    return
  end
  fwfLog("Transcription exit=" .. tostring(exitCode) .. " stdout=" .. tostring(stdOut and #stdOut or 0) .. "bytes")
  if stdErr and #stdErr > 0 then
    fwfLog("Transcription stderr: " .. stdErr)
  end

  if exitCode == 0 and stdOut and #stdOut > 0 then
    local transcript = nil
    local ok, decoded = pcall(hs.json.decode, stdOut)
    if ok and decoded and decoded.transcript then
      transcript = decoded.transcript
    end
    fwfLog("Transcript parsed: " .. tostring(transcript ~= nil) .. " text=" .. tostring(transcript and transcript:sub(1, 80) or "nil"))

    -- Optional Groq LLM cleanup (for fluidaudio provider, cleanup is done here instead of Python)
    if transcript and cachedGroqKey and sttProvider == "fluidaudio" then
      local groqStart = hs.timer.secondsSinceEpoch()
      fwfLog("Running Groq cleanup on transcript...")
      local groqBody = hs.json.encode({
        model = "llama-3.3-70b-versatile",
        messages = {
          { role = "system", content = "You are a transcript cleanup tool. You are NOT an assistant. Do NOT answer questions, add commentary, or respond to the content. Your ONLY job is to clean up the text.\n\nThe speaker is a software engineer. Remove filler words. Fix punctuation and capitalization. Fix misheard programming terms to their correct technical spelling. Keep the meaning, tone, and voice identical. Output ONLY the cleaned transcript. Nothing else." },
          { role = "user", content = transcript },
        },
        temperature = 0.1,
        max_tokens = 1024,
      })
      local headers = {
        ["Authorization"] = "Bearer " .. cachedGroqKey,
        ["Content-Type"] = "application/json",
      }
      local status, body = hs.http.post("https://api.groq.com/openai/v1/chat/completions", groqBody, headers)
      if status == 200 and body then
        local gOk, gDecoded = pcall(hs.json.decode, body)
        if gOk and gDecoded and gDecoded.choices and gDecoded.choices[1] then
          local cleaned = gDecoded.choices[1].message and gDecoded.choices[1].message.content
          if cleaned and #cleaned > 0 then
            fwfLog("Groq cleanup: '" .. transcript:sub(1, 40) .. "' -> '" .. cleaned:sub(1, 40) .. "'")
            transcript = cleaned
          end
        end
      end
      fwfLog(string.format("Groq cleanup took %.0fms", (hs.timer.secondsSinceEpoch() - groqStart) * 1000))
    end

    local shouldPaste = isTextInput()
    fwfLog("shouldPaste=" .. tostring(shouldPaste) .. " hasTranscript=" .. tostring(transcript ~= nil))

    if shouldPaste and transcript then
      hs.pasteboard.setContents(transcript)
      showResultInCanvas("Pasted")
      fwfLog("Set clipboard and sending Cmd+V")
      hs.timer.doAfter(0.05, function()
        hs.eventtap.keyStroke({"cmd"}, "v", 0)
        hs.timer.doAfter(0.2, function()
          if savedClipboard then
            hs.pasteboard.setContents(savedClipboard)
          end
        end)
      end)
    else
      if transcript then
        hs.pasteboard.setContents(transcript)
      end
      fwfLog("Fallback: copied to clipboard only")
      showResultInCanvas("Copied to clipboard")
    end
  else
    fwfLog("Transcription FAILED exit=" .. tostring(exitCode))
    showResultInCanvas("Transcription failed")
  end
end

local function runTranscriptionStream(task)
  if not hs.fs.attributes(transcribeScript) then
    print("Transcription script not found: " .. transcribeScript)
    return
  end
  if not cachedApiKey or cachedApiKey == "" then
    local apiKeyVar = sttProvider == "elevenlabs" and "ELEVENLABS_API_KEY" or "DEEPGRAM_API_KEY"
    hs.alert.show("Set " .. apiKeyVar .. " in ~/.hammerspoon/free-whisper-flow/.env", bottomStyle)
    return
  end

  task:setCallback(function(exitCode, stdOut, stdErr)
    handleTranscriptionResult(exitCode, stdOut, stdErr)
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
  local startTime = hs.timer.secondsSinceEpoch()
  fwfLog(string.format("startRecording() entered at %.3f", startTime))
  -- Play sound FIRST for instant feedback
  playSound()
  fwfLog(string.format("Sound dispatched in %.0fms", (hs.timer.secondsSinceEpoch() - startTime) * 1000))

  if not ffmpegPath then
    hs.alert.show("ffmpeg not available", bottomStyle)
    return
  end

  -- Use cached mic if available, otherwise detect (saves ~250ms)
  if not microphoneDevice then
    microphoneDevice = getDefaultMicrophone()
  end
  fwfLog(string.format("Mic selected in %.0fms", (hs.timer.secondsSinceEpoch() - startTime) * 1000))

  hs.fs.mkdir(recordingsDirectory)

  local fullCmd
  -- level_meter.py has no dependencies, run with python3 directly (skips uv overhead)
  local levelCmd = string.format("python3 %q", levelMeterScript)

  if sttProvider == "fluidaudio" then
    -- FluidAudio (local): ffmpeg writes WAV to temp file AND pipes raw PCM to level meter for waveform
    os.remove(fluidaudioTempWav)
    local ffmpegCmd = string.format(
      [[%s -hide_banner -loglevel error -f avfoundation -i "%s" -af "volume=2.0" -ar %d -ac 1 -c:a pcm_s16le -f s16le pipe:1 -ar %d -ac 1 %s]],
      ffmpegPath, microphoneDevice, audioSampleRate, audioSampleRate, fluidaudioTempWav)
    fullCmd = ffmpegCmd .. " | " .. levelCmd
  else
    -- Cloud providers: stream audio to Python transcription script
    local ffmpegCmd = string.format([[%s -hide_banner -loglevel error \
      -f avfoundation -i "%s" \
      -af "volume=2.0" \
      -ar %d -ac 1 -c:a pcm_s16le -f s16le -]],
      ffmpegPath, microphoneDevice, audioSampleRate)

    local pythonCmd = string.format("%q run --no-project %q --provider %s --api-key %q", uvPath, transcribeScript, sttProvider, cachedApiKey)
    if cachedGroqKey then
      pythonCmd = pythonCmd .. string.format(" --groq-api-key %q", cachedGroqKey)
    end
    local cloudLevelCmd = string.format("python3 %q", levelMeterScript)
    fullCmd = ffmpegCmd .. " | tee >(" .. cloudLevelCmd .. ") | " .. pythonCmd
  end

  fwfLog("Using microphone device: " .. microphoneDevice .. " for recording")
  fwfLog(string.format("Command built in %.0fms", (hs.timer.secondsSinceEpoch() - startTime) * 1000))

  -- Lower volume slightly while recording
  hs.timer.doAfter(0.15, function()
    local dev = hs.audiodevice.defaultOutputDevice()
    if dev then
      savedVolume = dev:outputVolume()
      fadeVolume(dev, savedVolume * 0.8, 0.5)
    end
  end)

  wasCancelled = false
  recordingStartTime = hs.timer.secondsSinceEpoch()
  savedClipboard = hs.pasteboard.getContents()

  if sttProvider == "fluidaudio" then
    recordingTask = hs.task.new("/bin/bash", function(exitCode, stdOut, stdErr)
      fwfLog("FluidAudio recording task ended, exit=" .. tostring(exitCode))
    end, {"-c", fullCmd})
    recordingTask:start()
  else
    recordingTask = hs.task.new("/bin/bash", nil, {"-c", fullCmd})
    runTranscriptionStream(recordingTask)
  end

  -- Show waveform visualization
  createWaveformCanvas()
  waveformTimer = hs.timer.doEvery(0.066, updateWaveform)  -- ~15fps

  -- Enter the modal to capture the escape key
  recordingModal:enter()
end

local function stopRecording()
  local stopTime = hs.timer.secondsSinceEpoch()
  fwfLog(string.format("stopRecording() called at %.3f (recorded %.1fs)", stopTime, stopTime - (recordingStartTime or stopTime)))

  -- Smoothly restore system volume and play stop sound
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev and savedVolume then
    fadeVolume(dev, savedVolume, 0.3, function() savedVolume = nil end)
  end
  playSound()

  -- Exit the modal so the escape key is released
  recordingModal:exit()

  -- Transition waveform to spinner while awaiting transcription
  showSpinnerInCanvas()

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

  -- For fluidaudio: now run the local transcription on the recorded WAV file
  if sttProvider == "fluidaudio" then
    if not hs.fs.attributes(fluidaudioBridge) then
      fwfLog("FluidAudio bridge not found at: " .. fluidaudioBridge)
      showResultInCanvas("FluidAudio not built - run install.sh")
      return
    end
    -- Small delay to let ffmpeg finish writing the WAV file
    hs.timer.doAfter(0.1, function()
      if wasCancelled then return end
      if not hs.fs.attributes(fluidaudioTempWav) then
        fwfLog("No recording file found at: " .. fluidaudioTempWav)
        showResultInCanvas("No audio recorded")
        return
      end
      local fileSize = hs.fs.attributes(fluidaudioTempWav, "size") or 0
      fwfLog(string.format("Starting FluidAudio transcription on: %s (%.1f KB)", fluidaudioTempWav, fileSize / 1024))
      local transcribeStart = hs.timer.secondsSinceEpoch()
      local transcribeTask = hs.task.new(fluidaudioBridge, function(exitCode, stdOut, stdErr)
        local transcribeElapsed = hs.timer.secondsSinceEpoch() - transcribeStart
        fwfLog(string.format("FluidAudio transcription took %.0fms (exit=%d)", transcribeElapsed * 1000, exitCode))
        handleTranscriptionResult(exitCode, stdOut, stdErr)
        os.remove(fluidaudioTempWav)
      end, {fluidaudioTempWav})
      transcribeTask:start()
    end)
  end
end

local function cancelRecording()
  print("🚫 Cancelling recording via Escape key.")

  -- Smoothly restore system volume
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev and savedVolume then
    fadeVolume(dev, savedVolume, 0.3, function() savedVolume = nil end)
  end

  wasCancelled = true

  if recordingTask and recordingTask:isRunning() then
    recordingTask:terminate()
  end
  recordingTask = nil

  -- Destroy waveform first, then show "Cancelled" in a fresh canvas
  destroyWaveformCanvas()

  -- Create a small notification canvas
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local frame = screen:frame()
  local width = 160
  local height = 40
  local cancelCanvas = hs.canvas.new({
    x = frame.x + (frame.w - width) / 2,
    y = frame.y + frame.h - height - OVERLAY_BOTTOM_OFFSET,
    w = width,
    h = height,
  })
  cancelCanvas:appendElements({
    type = "rectangle", action = "fill",
    roundedRectRadii = { xRadius = OVERLAY_RADIUS, yRadius = OVERLAY_RADIUS },
    fillColor = OVERLAY_BG,
  })
  cancelCanvas:appendElements({
    type = "text", text = "Cancelled",
    textColor = { red = 1, green = 1, blue = 1, alpha = 0.9 },
    textAlignment = "center", textFont = ".AppleSystemUIFont", textSize = 18,
    frame = { x = 0, y = (height - 22) / 2, w = width, h = 22 },
  })
  cancelCanvas:level(hs.canvas.windowLevels.overlay)
  cancelCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  cancelCanvas:show()
  hs.timer.doAfter(1, function() cancelCanvas:delete() end)

  recordingModal:exit()
end

local function toggleRecording()
  local hotkeyTime = hs.timer.secondsSinceEpoch()
  fwfLog(string.format("toggleRecording() called at %.3f", hotkeyTime))
  if recordingTask and recordingTask:isRunning() then
    -- Ignore stop if recording just started (accidental double-tap)
    local elapsed = hs.timer.secondsSinceEpoch() - (recordingStartTime or 0)
    if elapsed < MIN_RECORDING_SECONDS then
      fwfLog(string.format("Ignoring stop - only %.1fs elapsed (min %.1fs)", elapsed, MIN_RECORDING_SECONDS))
      return
    end
    fwfLog("Task is running, calling stopRecording()")
    stopRecording()
  else
    fwfLog("No task running, calling startRecording()")
    startRecording()
  end
end

recordingModal = hs.hotkey.modal.new()
recordingModal:bind({}, "escape", function()
    cancelRecording()
end)

-- Configurable hotkey: HOTKEY=cmd+shift+m (default) or e.g. HOTKEY=ctrl+alt+r
local hotkeyStr = readEnvVarFromFile(envFilePath, "HOTKEY") or "cmd+shift+m"
local hotkeyMods = {}
local hotkeyKey = nil
for part in hotkeyStr:gmatch("[^+]+") do
  part = part:gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if part == "cmd" or part == "ctrl" or part == "alt" or part == "shift" then
    table.insert(hotkeyMods, part)
  else
    hotkeyKey = part
  end
end
if hotkeyKey then
  hs.hotkey.bind(hotkeyMods, hotkeyKey, toggleRecording)
  fwfLog("Hotkey bound: " .. hotkeyStr)
else
  hs.hotkey.bind({"cmd","shift"}, "m", toggleRecording)
  fwfLog("Invalid HOTKEY in .env, using default cmd+shift+m")
end

-- Also bind F18 (remapped from Fn/Globe key via Karabiner-Elements)
hs.hotkey.bind({}, "f18", toggleRecording)

-- Pre-warm mic cache so first recording is instant
hs.timer.doAfter(1, function()
  microphoneDevice = getDefaultMicrophone()
  fwfLog("Pre-warmed mic cache: " .. tostring(microphoneDevice))
end)
