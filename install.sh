#!/usr/bin/env bash
set -euo pipefail

# Interactive installer for whisper-clipboard-cli
# Makes the entire setup process braindead simple

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.hammerspoon/whisper-clipboard-cli"
HAMMERSPOON_INIT="$HOME/.hammerspoon/init.lua"

echo "🎙️  Whisper Clipboard CLI - Interactive Installer"
echo "=================================================="
echo

# Function to ask yes/no questions
ask_yes_no() {
    local prompt="$1"
    local default="${2:-}"
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt [Y/n]: " -r answer
            answer="${answer:-y}"
        elif [[ "$default" == "n" ]]; then
            read -p "$prompt [y/N]: " -r answer
            answer="${answer:-n}"
        else
            read -p "$prompt [y/n]: " -r answer
        fi
        
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required dependencies
echo "🔍 Checking dependencies..."

# Check Homebrew
if ! command_exists brew; then
    echo "❌ Homebrew not found"
    if ask_yes_no "Install Homebrew?"; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add to PATH for this session
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            export PATH="/opt/homebrew/bin:$PATH"
        fi
    else
        echo "❌ Homebrew is required. Exiting."
        exit 1
    fi
else
    echo "✅ Homebrew found"
fi

# Check ffmpeg
if ! command_exists ffmpeg; then
    echo "❌ ffmpeg not found"
    if ask_yes_no "Install ffmpeg via Homebrew?" "y"; then
        echo "Installing ffmpeg..."
        brew install ffmpeg
    else
        echo "❌ ffmpeg is required. Exiting."
        exit 1
    fi
else
    echo "✅ ffmpeg found"
fi

# Check uv (required for Python execution and dependency management)
if ! command_exists uv; then
    echo "❌ uv not found"
    if ask_yes_no "Install uv via Homebrew?" "y"; then
        echo "Installing uv..."
        brew install uv
    else
        echo "❌ uv is required for Python execution. Exiting."
        exit 1
    fi
else
    echo "✅ uv found"
fi

# Check Hammerspoon
if ! brew list --cask hammerspoon &>/dev/null && ! [[ -d "/Applications/Hammerspoon.app" ]]; then
    echo "❌ Hammerspoon not found"
    if ask_yes_no "Install Hammerspoon via Homebrew?" "y"; then
        echo "Installing Hammerspoon..."
        brew install --cask hammerspoon
        echo "📝 After installation, you'll need to:"
        echo "   1. Open Hammerspoon from Applications"
        echo "   2. Grant Accessibility permissions when prompted"
        echo "   3. Enable 'Launch Hammerspoon at login' in Preferences"
    else
        echo "❌ Hammerspoon is required. Exiting."
        exit 1
    fi
else
    echo "✅ Hammerspoon found"
fi

echo

# Auto-detect microphone
echo "🎤 Auto-detecting microphone..."
if microphone_device=$("$PROJECT_DIR/scripts/detect_microphone.sh" 2>/dev/null); then
    echo "✅ Found microphone: device $microphone_device"
else
    echo "❌ Could not auto-detect microphone. You may need to configure manually."
    microphone_device=":0"  # fallback
fi

echo

# Get Deepgram API key
echo "🔑 Deepgram API Key Setup"
echo "You need a Deepgram API key for transcription."
echo "Get one free at: https://deepgram.com"
echo

deepgram_key=""
while [[ -z "$deepgram_key" ]]; do
    read -p "Enter your Deepgram API key: " -r deepgram_key
    if [[ -z "$deepgram_key" ]]; then
        echo "API key is required for transcription."
    fi
done

echo

# Check for existing installation
if [[ -d "$TARGET_DIR" ]]; then
    echo "🔄 Existing installation found at $TARGET_DIR"
    if ask_yes_no "Overwrite existing installation?" "y"; then
        echo "Backing up existing installation..."
        mv "$TARGET_DIR" "$TARGET_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    else
        echo "Installation cancelled."
        exit 0
    fi
fi

# Install files
echo "📦 Installing files..."
mkdir -p "$TARGET_DIR/scripts"

# Copy and update init.lua with detected microphone
echo "Configuring Hammerspoon script with detected microphone..."
sed "s|local microphoneDevice  = \":[0-9]*\"|local microphoneDevice  = \"$microphone_device\"|" \
    "$PROJECT_DIR/hammerspoon/init.lua" > "$TARGET_DIR/init.lua"

# Copy transcription script
cp "$PROJECT_DIR/scripts/transcribe_and_copy.py" "$TARGET_DIR/scripts/"
chmod +x "$TARGET_DIR/scripts/transcribe_and_copy.py"

# Create .env file with API key
echo "DEEPGRAM_API_KEY=$deepgram_key" > "$TARGET_DIR/.env"

echo "✅ Files installed to $TARGET_DIR"

# Setup Hammerspoon loader
if [[ ! -f "$HAMMERSPOON_INIT" ]] || [[ ! -s "$HAMMERSPOON_INIT" ]]; then
    echo "📝 Creating Hammerspoon init.lua..."
    mkdir -p "$(dirname "$HAMMERSPOON_INIT")"
    cat > "$HAMMERSPOON_INIT" <<'EOF'
-- Load whisper-clipboard-cli config if present
local cfg = os.getenv("HOME") .. "/.hammerspoon/whisper-clipboard-cli/init.lua"
if hs.fs.attributes(cfg) then 
    dofile(cfg) 
    print("Loaded whisper-clipboard-cli")
end
EOF
else
    echo "📝 Existing Hammerspoon init.lua found"
    if ! grep -q "whisper-clipboard-cli" "$HAMMERSPOON_INIT"; then
        echo "Adding whisper-clipboard-cli loader to existing init.lua..."
        cat >> "$HAMMERSPOON_INIT" <<'EOF'

-- Load whisper-clipboard-cli config if present
local cfg = os.getenv("HOME") .. "/.hammerspoon/whisper-clipboard-cli/init.lua"
if hs.fs.attributes(cfg) then 
    dofile(cfg) 
    print("Loaded whisper-clipboard-cli")
end
EOF
    else
        echo "✅ whisper-clipboard-cli already configured in init.lua"
    fi
fi

# Reload Hammerspoon
echo "🔄 Reloading Hammerspoon..."
open -g "hammerspoon://reload" 2>/dev/null || echo "Note: Hammerspoon may not be running yet"

echo
echo "🎉 Installation Complete!"
echo "===================="
echo
echo "Next steps:"
echo "1. If Hammerspoon isn't running, open it from Applications"
echo "2. Grant Accessibility permissions when prompted"
echo "3. Grant Microphone permissions when you first record"
echo "4. Enable 'Launch Hammerspoon at login' in Hammerspoon Preferences"
echo
echo "Usage:"
echo "• Press Cmd+Shift+X to start/stop recording"
echo "• Recordings are saved to ~/Recordings"
echo "• Transcripts are automatically copied to clipboard"
echo
echo "Files installed:"
echo "• Configuration: $TARGET_DIR"
echo "• Microphone device: $microphone_device"
echo "• API key: configured in $TARGET_DIR/.env"
echo