#!/bin/bash
set -e

# Post-install script: copies Hammerspoon config & scripts into ~/.hammerspoon/free-whisper-flow

echo "🚀 Starting free-whisper-flow post-install..."

TARGET_DIR="$HOME/.hammerspoon/free-whisper-flow"
HAMMERSPOON_INIT="$HOME/.hammerspoon/init.lua"

# Define the section to be managed in init.lua
WHISPER_SECTION_START="-- === free-whisper-flow START ==="
WHISPER_SECTION_END="-- === free-whisper-flow END ==="

# 1. Clean up old installation section if it exists
if [[ -f "${HAMMERSPOON_INIT}" ]] && grep -F "free-whisper-flow START" "${HAMMERSPOON_INIT}" > /dev/null 2>&1; then
  echo "Found existing free-whisper-flow section in ~/.hammerspoon/init.lua; cleaning it up."
  # Use sed to delete the block between the start and end markers
  sed '/free-whisper-flow START/,/free-whisper-flow END/d' "${HAMMERSPOON_INIT}" > "${HAMMERSPOON_INIT}.tmp"
  mv "${HAMMERSPOON_INIT}.tmp" "${HAMMERSPOON_INIT}"
fi

# 2. Append the new loader section to init.lua
echo "Adding free-whisper-flow loader to ~/.hammerspoon/init.lua"
cat >> "${HAMMERSPOON_INIT}" << EOF

${WHISPER_SECTION_START}
-- Load free-whisper-flow config if present
local whisper_cfg = os.getenv("HOME") .. "/.hammerspoon/free-whisper-flow/init.lua"
if hs.fs.attributes(whisper_cfg) then
    dofile(whisper_cfg)
    print("✅ Loaded free-whisper-flow config")
else
    print(" M issing free-whisper-flow config at: " .. whisper_cfg)
end
${WHISPER_SECTION_END}
EOF

# 3. Recreate the target directory and copy files
echo "Creating directory ${TARGET_DIR}"
rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}/scripts"

echo "Copying scripts..."
# Copy the Lua entrypoint and the Python script
cp ./hammerspoon/init.lua "${TARGET_DIR}/init.lua"
cp ./scripts/transcribe_and_copy.py "${TARGET_DIR}/scripts/transcribe_and_copy.py"

# If a .env file exists, copy it too
if [ -f "./.env" ]; then
    echo "Copying .env file..."
    cp ./.env "${TARGET_DIR}/.env"
fi

# Reload Hammerspoon if running
open -g "hammerspoon://reload" || true

echo "Installed Hammerspoon config to ${TARGET_DIR}"
echo "Edit ${TARGET_DIR}/.env and set DEEPGRAM_API_KEY."
