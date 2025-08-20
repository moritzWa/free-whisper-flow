#!/usr/bin/env bash
set -euo pipefail

# Post-install script: copies Hammerspoon config & scripts into ~/.hammerspoon/whisper-clipboard-cli
# and reloads Hammerspoon. Also prepares a .env placeholder if missing.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$HOME/.hammerspoon/whisper-clipboard-cli"

mkdir -p "$TARGET_DIR/scripts"

# Copy Hammerspoon init.lua into ~/.hammerspoon/init.lua if empty or user agrees
if [ ! -s "$HOME/.hammerspoon/init.lua" ]; then
  echo "~/.hammerspoon/init.lua is missing or empty; installing a minimal loader to include our config."
  mkdir -p "$HOME/.hammerspoon"
  cat > "$HOME/.hammerspoon/init.lua" <<'LUA'
-- Load whisper-clipboard-cli config if present
local cfg = os.getenv("HOME") .. "/.hammerspoon/whisper-clipboard-cli/init.lua"
if hs.fs.attributes(cfg) then dofile(cfg) end
LUA
else
  echo "Found existing ~/.hammerspoon/init.lua; leaving it as-is. Ensure it loads our config if desired."
fi

# Copy our Hammerspoon config and scripts
cp -f "$PROJECT_DIR/hammerspoon/init.lua" "$TARGET_DIR/init.lua"
cp -f "$PROJECT_DIR/scripts/transcribe_and_copy.py" "$TARGET_DIR/scripts/transcribe_and_copy.py"
chmod +x "$TARGET_DIR/scripts/transcribe_and_copy.py"

# Create .env if missing
if [ ! -f "$TARGET_DIR/.env" ]; then
  cp -n "$PROJECT_DIR/.env.example" "$TARGET_DIR/.env" || true
  echo "Created $TARGET_DIR/.env (fill in DEEPGRAM_API_KEY)"
fi

# Reload Hammerspoon if running
open -g "hammerspoon://reload" || true

echo "Installed Hammerspoon config to $TARGET_DIR"
echo "Edit $TARGET_DIR/.env and set DEEPGRAM_API_KEY."
