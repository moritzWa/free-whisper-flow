#!/usr/bin/env bash
set -euo pipefail

# Interactive installer for free-whisper-flow
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.hammerspoon/free-whisper-flow"
HAMMERSPOON_INIT="$HOME/.hammerspoon/init.lua"

echo "🎙️  free-whisper-flow installer"
echo "================================"
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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- 1. System dependencies ---

echo "🔍 Checking dependencies..."

if ! command_exists brew; then
    echo "❌ Homebrew not found"
    if ask_yes_no "Install Homebrew?" "y"; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        [[ -f "/opt/homebrew/bin/brew" ]] && export PATH="/opt/homebrew/bin:$PATH"
    else
        echo "❌ Homebrew is required. Exiting."; exit 1
    fi
else
    echo "✅ Homebrew"
fi

for dep in ffmpeg uv; do
    if ! command_exists "$dep"; then
        echo "❌ $dep not found"
        if ask_yes_no "Install $dep via Homebrew?" "y"; then
            brew install "$dep"
        else
            echo "❌ $dep is required. Exiting."; exit 1
        fi
    else
        echo "✅ $dep"
    fi
done

if ! brew list --cask hammerspoon &>/dev/null && ! [[ -d "/Applications/Hammerspoon.app" ]]; then
    echo "❌ Hammerspoon not found (macOS automation framework that powers the hotkey and UI)"
    if ask_yes_no "Install Hammerspoon via Homebrew?" "y"; then
        brew install --cask hammerspoon
    else
        echo "❌ Hammerspoon is required. Exiting."; exit 1
    fi
else
    echo "✅ Hammerspoon"
fi

# Check Node.js (needed for setup CLI)
if ! command_exists node; then
    echo "❌ Node.js not found"
    if ask_yes_no "Install Node.js via Homebrew?" "y"; then
        brew install node
    else
        echo "❌ Node.js is required for the setup CLI. Exiting."; exit 1
    fi
else
    echo "✅ Node.js"
fi

echo

# --- 2. Build FluidAudio bridge ---

echo "🔨 Building FluidAudio bridge (local STT)..."
if command_exists swift; then
    BRIDGE_DIR="$PROJECT_DIR/tools/fluidaudio-bridge"
    if cd "$BRIDGE_DIR" && swift build -c release 2>&1; then
        echo "✅ FluidAudio bridge built"
    else
        echo "⚠️  FluidAudio build failed. Local STT won't be available."
        echo "   Cloud providers still work. Install Xcode to fix."
    fi
    cd "$PROJECT_DIR"
else
    echo "⚠️  Swift not found. Run xcode-select --install for local STT."
fi

echo

# --- 3. Install npm dependencies and run interactive setup ---

echo "📦 Installing dependencies..."
cd "$PROJECT_DIR"
npm install --silent 2>/dev/null

echo
echo "⚙️  Configuration"
echo "-----------------"
node setup.js

echo

# --- 4. Link files ---

echo "📦 Linking files..."
mkdir -p "${TARGET_DIR}/scripts"
ln -sf "$PROJECT_DIR/hammerspoon/init.lua" "$TARGET_DIR/init.lua"
ln -sf "$PROJECT_DIR/scripts/transcribe_and_copy.py" "$TARGET_DIR/scripts/transcribe_and_copy.py"
ln -sf "$PROJECT_DIR/scripts/level_meter.py" "$TARGET_DIR/scripts/level_meter.py"
ln -sf "$PROJECT_DIR/tools" "$TARGET_DIR/tools"
ln -sf "$PROJECT_DIR/.env" "$TARGET_DIR/.env"
ln -sf "$PROJECT_DIR/hammerspoon/init.lua" "$HAMMERSPOON_INIT"
echo "✅ Files linked to ${TARGET_DIR}"

# --- 5. Install fwf command ---

echo "📦 Installing fwf settings command..."
FWF_BIN="/usr/local/bin/fwf"
cat > /tmp/fwf_launcher <<SCRIPT
#!/usr/bin/env bash
cd "$PROJECT_DIR" && node setup.js --settings
SCRIPT
chmod +x /tmp/fwf_launcher
if sudo mv /tmp/fwf_launcher "$FWF_BIN" 2>/dev/null; then
    echo "✅ Run 'fwf' anytime to change settings"
else
    # Fallback: put in user-local bin
    mkdir -p "$HOME/.local/bin"
    mv /tmp/fwf_launcher "$HOME/.local/bin/fwf"
    echo "✅ Run '~/.local/bin/fwf' to change settings (add ~/.local/bin to PATH)"
fi

# --- 6. Start Hammerspoon ---

echo
echo "🔄 Starting Hammerspoon..."
killall Hammerspoon 2>/dev/null && sleep 1
open -a Hammerspoon 2>/dev/null || echo "Note: Open Hammerspoon manually from Applications."

# Add to login items
if ask_yes_no "Add Hammerspoon to login items (auto-start on boot)?" "y"; then
    if ! osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -q "Hammerspoon"; then
        osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Hammerspoon.app", hidden:false}' 2>/dev/null \
            && echo "✅ Hammerspoon will start on boot" \
            || echo "⚠️  Could not add to login items. Enable manually in Hammerspoon > Preferences."
    else
        echo "✅ Already in login items"
    fi
fi

echo
# --- 7. Ensure Accessibility permissions ---

echo
echo "🔐 Checking Accessibility permissions..."
sleep 2  # Give Hammerspoon a moment to start and request permissions

# Check if Hammerspoon has accessibility access
if ! osascript -e 'tell application "System Events" to key code 0' &>/dev/null; then
    echo "⚠️  Hammerspoon needs Accessibility permissions to detect hotkeys."
    echo "   Opening System Settings - please toggle Hammerspoon ON, then come back here."
    echo
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    echo -n "   Waiting for you to grant permission..."
    while ! osascript -e 'tell application "System Events" to key code 0' &>/dev/null 2>&1; do
        sleep 2
        echo -n "."
    done
    echo
    echo "✅ Accessibility permissions granted!"
    # Restart Hammerspoon to pick up permissions
    killall Hammerspoon 2>/dev/null && sleep 1
    open -a Hammerspoon 2>/dev/null
else
    echo "✅ Accessibility permissions already granted"
fi

echo
echo "🎉 Setup complete!"
echo
HOTKEY=$(grep "^HOTKEY=" "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "cmd+shift+m")
echo "Press ${HOTKEY} to start recording. Run 'fwf' to change settings."
echo
