#!/usr/bin/env node
"use strict";
import { execSync } from "child_process";
import path from "path";
import { fileURLToPath } from "url";

// Simple check for macOS
if (process.platform !== "darwin") {
  console.error("❌ free-whisper-flow currently only supports macOS");
  process.exit(1);
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const installScriptPath = path.join(__dirname, "install.sh");

console.log("🚀 Running the free-whisper-flow installer...");

try {
  execSync(`bash "${installScriptPath}"`, { stdio: "inherit" });
} catch (error) {
  console.error("💀 Installation failed.");
  process.exit(1);
}
