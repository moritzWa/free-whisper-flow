#!/usr/bin/env bash
set -euo pipefail

# Post-install script: copies Hammerspoon config & scripts into ~/.hammerspoon/whisper-clipboard-cli
# and reloads Hammerspoon. Also prepares a .env placeholder if missing.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$HOME/.hammerspoon/whisper-clipboard-cli"

mkdir -p "$TARGET_DIR/scripts"

# Handle ~/.hammerspoon/init.lua setup
HAMMERSPOON_INIT="$HOME/.hammerspoon/init.lua"
WHISPER_SECTION_START="-- === whisper-clipboard-cli START ==="
WHISPER_SECTION_END="-- === whisper-clipboard-cli END ==="

mkdir -p "$HOME/.hammerspoon"

# Check if we already have our loader section
if [[ -f "${HAMMERSPOON_INIT}" ]] && grep -F "whisper-clipboard-cli START" "${HAMMERSPOON_INIT}" > /dev/null 2>&1; then
  echo "Found existing whisper-clipboard-cli section in ~/.hammerspoon/init.lua; cleaning it up."
  # Remove all whisper sections
  sed '/whisper-clipboard-cli START/,/whisper-clipboard-cli END/d' "${HAMMERSPOON_INIT}" > "${HAMMERSPOON_INIT}.tmp"
  mv "${HAMMERSPOON_INIT}.tmp" "${HAMMERSPOON_INIT}"
fi

echo "Adding whisper-clipboard-cli loader to ~/.hammerspoon/init.lua"
NEED_LOADER=true

# Copy our Hammerspoon config and scripts
cp -f "${PROJECT_DIR}/hammerspoon/init.lua" "${TARGET_DIR}/init.lua"
cp -f "${PROJECT_DIR}/scripts/transcribe_and_copy.py" "${TARGET_DIR}/scripts/transcribe_and_copy.py"
chmod +x "${TARGET_DIR}/scripts/transcribe_and_copy.py"

# Create .env if missing
if [[ ! -f "${TARGET_DIR}/.env" ]]; then
  cp -n "${PROJECT_DIR}/.env.example" "${TARGET_DIR}/.env" || true
  echo "Created ${TARGET_DIR}/.env (fill in DEEPGRAM_API_KEY)"
fi

# Clean up old whisper-clipboard config from main init.lua if present
if [[ -f "${HAMMERSPOON_INIT}" ]] && grep -F "record microphone audio" "${HAMMERSPOON_INIT}" > /dev/null 2>&1; then
  echo "Removing old whisper-clipboard config from ~/.hammerspoon/init.lua"
  # Create backup
  cp "${HAMMERSPOON_INIT}" "${HAMMERSPOON_INIT}.backup"
  # Remove everything from the first whisper comment to the end
  sed '/record microphone audio/,$d' "${HAMMERSPOON_INIT}" > "${HAMMERSPOON_INIT}.tmp"
  mv "${HAMMERSPOON_INIT}.tmp" "${HAMMERSPOON_INIT}"
fi

# Add our loader section if needed
if [[ "${NEED_LOADER}" == "true" ]]; then
  cat >> "${HAMMERSPOON_INIT}" <<LUA

${WHISPER_SECTION_START}
-- Load whisper-clipboard-cli config if present
local whisper_cfg = os.getenv("HOME") .. "/.hammerspoon/whisper-clipboard-cli/init.lua"
if hs.fs.attributes(whisper_cfg) then
  dofile(whisper_cfg)
end
${WHISPER_SECTION_END}
LUA
fi

# Reload Hammerspoon if running
open -g "hammerspoon://reload" || true

echo "Installed Hammerspoon config to ${TARGET_DIR}"
echo "Edit ${TARGET_DIR}/.env and set DEEPGRAM_API_KEY."
