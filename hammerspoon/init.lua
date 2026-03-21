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
local MIN_RECORDING_SECONDS = 1.5
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

-- STT provider: "elevenlabs" (default) or "deepgram"
local sttProvider = readEnvVarFromFile(envFilePath, "STT_PROVIDER") or "elevenlabs"
print("STT provider: " .. sttProvider)

-- Feedback sounds: same sound (Pop), higher pitch on start, lower on stop
local popSoundPath = "/System/Library/Sounds/Pop.aiff"
local function playSound(rate)
  hs.task.new("/usr/bin/afplay", nil, {"--rate", tostring(rate), popSoundPath}):start()
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
        fwfLog("Task callback ignored due to cancellation.")
        return
    end
    fwfLog("Transcription exit=" .. tostring(exitCode) .. " stdout=" .. tostring(stdOut and #stdOut or 0) .. "bytes")
    if stdErr and #stdErr > 0 then
      fwfLog("Transcription stderr: " .. stdErr)
    end

    if exitCode == 0 and stdOut and #stdOut > 0 then
      -- Parse transcript from JSON stdout
      local transcript = nil
      local ok, decoded = pcall(hs.json.decode, stdOut)
      if ok and decoded and decoded.transcript then
        transcript = decoded.transcript
      end
      fwfLog("Transcript parsed: " .. tostring(transcript ~= nil) .. " text=" .. tostring(transcript and transcript:sub(1, 80) or "nil"))

      local shouldPaste = isTextInput()
      fwfLog("shouldPaste=" .. tostring(shouldPaste) .. " hasTranscript=" .. tostring(transcript ~= nil))

      if shouldPaste and transcript then
        -- Paste via clipboard, then restore original clipboard contents
        hs.pasteboard.setContents(transcript)
        showResultInCanvas("Pasted")
        fwfLog("Set clipboard and sending Cmd+V")
        hs.timer.doAfter(0.05, function()
          hs.eventtap.keyStroke({"cmd"}, "v", 0)
          -- Restore clipboard after a short delay to ensure paste completes
          hs.timer.doAfter(0.2, function()
            if savedClipboard then
              hs.pasteboard.setContents(savedClipboard)
            end
          end)
        end)
      else
        -- No text input focused - copy to clipboard as fallback
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
  local groqKey = readEnvVarFromFile(envFilePath, "GROQ_API_KEY")
  if groqKey and groqKey ~= "" then
    pythonCmd = pythonCmd .. string.format(" --groq-api-key %q", groqKey)
  end
  local levelCmd = string.format("%q run --no-project %q", uvPath, levelMeterScript)

  local fullCmd = ffmpegCmd .. " | tee >(" .. levelCmd .. ") | " .. pythonCmd

  print("Using microphone device: " .. microphoneDevice .. " for recording")
  print("Executing streaming command: " .. fullCmd)


  -- Play start sound (higher pitch), then smoothly lower system volume
  playSound(2)
  hs.timer.doAfter(0.15, function()
    local dev = hs.audiodevice.defaultOutputDevice()
    if dev then
      savedVolume = dev:outputVolume()
      fadeVolume(dev, savedVolume * 0.8, 0.5)
    end
  end)

  wasCancelled = false -- Reset the flag each time we start
  recordingStartTime = hs.timer.secondsSinceEpoch()
  savedClipboard = hs.pasteboard.getContents() -- Save clipboard before Python overwrites it
  recordingTask = hs.task.new("/bin/bash", nil, {"-lc", fullCmd})
  runTranscriptionStream(recordingTask)


  -- Show waveform visualization
  createWaveformCanvas()
  waveformTimer = hs.timer.doEvery(0.066, updateWaveform)  -- ~15fps

  -- Enter the modal to capture the escape key
  recordingModal:enter()
end

local function stopRecording()
  print("🛑 stopRecording() called")

  -- Smoothly restore system volume and play stop sound
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev and savedVolume then
    fadeVolume(dev, savedVolume, 0.3, function() savedVolume = nil end)
  end
  playSound(0.8)

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
  fwfLog("toggleRecording() called")
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

hs.hotkey.bind({"cmd","shift"}, "m", toggleRecording)

-- Also bind F18 (remapped from Fn/Globe key via Karabiner-Elements)
hs.hotkey.bind({}, "f18", toggleRecording)
