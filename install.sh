#!/usr/bin/env bash
set -euo pipefail

# Interactive installer for free-whisper-flow
# - Checks and installs Homebrew, ffmpeg, Hammerspoon, uv
# - Sets up ~/.hammerspoon/free-whisper-flow directory
# - Prompts for Deepgram API key and creates .env file
# - Configures Hammerspoon's init.lua to load the script

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.hammerspoon/free-whisper-flow"
HAMMERSPOON_INIT="$HOME/.hammerspoon/init.lua"

echo "🎙️  free-whisper-flow - Interactive Installer"
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

echo

# Check for existing Deepgram API key
deepgram_key=""
if [[ -f "${TARGET_DIR}/.env" ]] && grep -q "DEEPGRAM_API_KEY=" "${TARGET_DIR}/.env"; then
    existing_key=$(grep "DEEPGRAM_API_KEY=" "${TARGET_DIR}/.env" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    if [[ -n "${existing_key}" && "${existing_key}" != "your_api_key_here" ]]; then
        echo "🔑 Found existing Deepgram API key"
        deepgram_key="${existing_key}"
    fi
fi

# Get Deepgram API key if not found
if [[ -z "${deepgram_key}" ]]; then
    echo "🔑 Deepgram API Key Setup"
    echo "You need a Deepgram API key for transcription."
    echo "Get one free at: https://deepgram.com"
    echo

    while [[ -z "${deepgram_key}" ]]; do
        read -p "Enter your Deepgram API key: " -r deepgram_key
        if [[ -z "${deepgram_key}" ]]; then
            echo "API key is required for transcription."
        fi
    done
fi

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

# Install files by creating symlinks for development
echo "📦 Linking files for development..."
mkdir -p "${TARGET_DIR}/scripts"

# Link Hammerspoon script
echo "Linking Hammerspoon configuration..."
ln -sf "$PROJECT_DIR/hammerspoon/init.lua" "$TARGET_DIR/init.lua"

# Link transcription script
ln -sf "$PROJECT_DIR/scripts/transcribe_and_copy.py" "$TARGET_DIR/scripts/transcribe_and_copy.py"

# Create .env file in project root and link it
echo "DEEPGRAM_API_KEY=${deepgram_key}" > "$PROJECT_DIR/.env"
ln -sf "$PROJECT_DIR/.env" "$TARGET_DIR/.env"
echo "🔑 API key stored in ${PROJECT_DIR}/.env and linked."
echo "   (Make sure to add .env to your .gitignore file)"

echo "✅ Files linked to ${TARGET_DIR}"

# Symlink the main init.lua file that Hammerspoon loads
ln -sf "$PROJECT_DIR/hammerspoon/init.lua" "$HAMMERSPOON_INIT"
echo "✅ Main Hammerspoon config linked."

# Reload Hammerspoon
echo "🔄 Restarting Hammerspoon to apply changes..."
killall Hammerspoon && sleep 1 && open -a Hammerspoon 2>/dev/null || echo "Note: Hammerspoon may not have been running."

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
echo "• Uses your system's default microphone (set in System Settings > Sound)"
echo
echo "Files installed:"
echo "• Configuration: ${TARGET_DIR}"
echo "• API key: configured in ${TARGET_DIR}/.env"
echo