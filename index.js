#!/usr/bin/env node

const { execSync } = require('child_process');
const path = require('path');
const os = require('os');

// Check if running on macOS
if (os.platform() !== 'darwin') {
  console.error('❌ whisper-clipboard-cli currently only supports macOS');
  console.error('   Open to PRs for Windows/Linux support!');
  process.exit(1);
}

console.log('🎙️  Whisper Clipboard CLI - Installer');
console.log('=====================================');

try {
  // Run the install script
  const installScript = path.join(__dirname, 'install.sh');
  execSync(`chmod +x "${installScript}" && "${installScript}"`, {
    stdio: 'inherit',
    cwd: __dirname
  });
} catch (error) {
  console.error('❌ Installation failed:', error.message);
  process.exit(1);
}