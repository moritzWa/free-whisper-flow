#!/usr/bin/env node
import prompts from "prompts";
import chalk from "chalk";
import { execSync } from "child_process";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const envPath = path.join(__dirname, ".env");

// Parse existing .env file if it exists
function parseEnv(filePath) {
  const env = {};
  if (!fs.existsSync(filePath)) return env;
  for (const line of fs.readFileSync(filePath, "utf-8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    val = val.replace(/^["']|["']$/g, "");
    env[key] = val;
  }
  return env;
}

// Detect available microphones via ffmpeg
function detectMics() {
  try {
    const output = execSync(
      'ffmpeg -f avfoundation -list_devices true -i "" 2>&1',
      { encoding: "utf-8" }
    );
    const mics = [];
    let inAudio = false;
    for (const line of output.split("\n")) {
      if (line.includes("audio devices")) inAudio = true;
      else if (line.includes("video devices")) inAudio = false;
      else if (inAudio) {
        const match = line.match(/\[(\d+)\]\s+(.+)$/);
        if (match) mics.push({ index: parseInt(match[1]), name: match[2] });
      }
    }
    return mics;
  } catch {
    return [];
  }
}

function writeEnv(config) {
  const lines = [];
  lines.push(`STT_PROVIDER=${config.provider}`);
  if (config.elevenlabsKey) lines.push(`ELEVENLABS_API_KEY=${config.elevenlabsKey}`);
  if (config.deepgramKey) lines.push(`DEEPGRAM_API_KEY=${config.deepgramKey}`);
  if (config.groqKey) lines.push(`GROQ_API_KEY=${config.groqKey}`);
  if (config.hotkey) lines.push(`HOTKEY=${config.hotkey}`);
  if (config.micPreference) lines.push(`MIC_PREFERENCE=${config.micPreference}`);
  if (config.micBlacklist) lines.push(`MIC_BLACKLIST=${config.micBlacklist}`);
  fs.writeFileSync(envPath, lines.join("\n") + "\n");
}

// Cancel handler - exit cleanly on Ctrl+C
const onCancel = () => {
  console.log("\nSetup cancelled.");
  process.exit(0);
};

async function run() {
  const existing = parseEnv(envPath);
  const isReconfigure = process.argv.includes("--settings");

  if (isReconfigure && Object.keys(existing).length > 0) {
    console.log(chalk.bold("\nCurrent settings:"));
    console.log(`  Provider:  ${chalk.cyan(existing.STT_PROVIDER || "elevenlabs")}`);
    console.log(`  Hotkey:    ${chalk.cyan(existing.HOTKEY || "cmd+shift+m")}`);
    if (existing.MIC_PREFERENCE) console.log(`  Mic pref:  ${chalk.cyan(existing.MIC_PREFERENCE)}`);
    if (existing.MIC_BLACKLIST) console.log(`  Mic block: ${chalk.cyan(existing.MIC_BLACKLIST)}`);
    console.log(`  Groq:      ${chalk.cyan(existing.GROQ_API_KEY ? "enabled" : "disabled")}`);
    console.log();
  }

  // 1. Provider selection
  const providerChoices = [
    {
      title: "FluidAudio (local, free) - ~3% WER, ~275ms, runs on Apple Neural Engine",
      value: "fluidaudio",
    },
    {
      title: "ElevenLabs Scribe v2 (cloud) - ~2.3% WER, ~800ms, requires API key",
      value: "elevenlabs",
    },
    {
      title: "Deepgram Nova-2 (cloud) - ~8.4% WER, real-time, requires API key ($200 free credits)",
      value: "deepgram",
    },
  ];

  const defaultProvider = providerChoices.findIndex(
    (c) => c.value === (existing.STT_PROVIDER || "fluidaudio")
  );

  const { provider } = await prompts(
    {
      type: "select",
      name: "provider",
      message: "Choose STT provider",
      choices: providerChoices,
      initial: Math.max(0, defaultProvider),
    },
    { onCancel }
  );

  // 2. API key for cloud providers
  let elevenlabsKey = existing.ELEVENLABS_API_KEY || "";
  let deepgramKey = existing.DEEPGRAM_API_KEY || "";

  if (provider === "elevenlabs") {
    const { key } = await prompts(
      {
        type: "text",
        name: "key",
        message: "ElevenLabs API key (from elevenlabs.io)",
        initial: elevenlabsKey,
        validate: (v) => (v.length > 0 ? true : "API key is required for ElevenLabs"),
      },
      { onCancel }
    );
    elevenlabsKey = key;
  } else if (provider === "deepgram") {
    const { key } = await prompts(
      {
        type: "text",
        name: "key",
        message: "Deepgram API key (from deepgram.com, $200 free credits)",
        initial: deepgramKey,
        validate: (v) => (v.length > 0 ? true : "API key is required for Deepgram"),
      },
      { onCancel }
    );
    deepgramKey = key;
  }

  // 3. Microphone selection
  const mics = detectMics();
  let micPreference = existing.MIC_PREFERENCE || "";
  let micBlacklist = existing.MIC_BLACKLIST || "";

  if (mics.length > 1) {
    const micChoices = mics.map((m) => ({
      title: m.name,
      value: m.name,
      selected: micPreference.toLowerCase().includes(m.name.toLowerCase()),
    }));

    const { preferred } = await prompts(
      {
        type: "multiselect",
        name: "preferred",
        message: "Select preferred microphones (space to toggle, enter to confirm)",
        choices: micChoices,
        hint: "- First available preferred mic is used",
      },
      { onCancel }
    );
    micPreference = preferred.join(",");

    // Blacklist: only ask if there are mics not in the preferred list
    const nonPreferred = mics.filter((m) => !preferred.includes(m.name));
    if (nonPreferred.length > 0) {
      const blacklistChoices = nonPreferred.map((m) => ({
        title: m.name,
        value: m.name,
        selected: micBlacklist.toLowerCase().includes(m.name.toLowerCase()),
      }));

      const { blocked } = await prompts(
        {
          type: "multiselect",
          name: "blocked",
          message: "Block any microphones? (e.g. AirPods when you have a desk mic)",
          choices: blacklistChoices,
        },
        { onCancel }
      );
      micBlacklist = blocked.join(",");
    }
  } else if (mics.length === 1) {
    console.log(chalk.dim(`  Using microphone: ${mics[0].name}`));
  }

  // 4. Hotkey
  const { hotkey } = await prompts(
    {
      type: "text",
      name: "hotkey",
      message: "Hotkey to start/stop recording",
      initial: existing.HOTKEY || "cmd+shift+m",
    },
    { onCancel }
  );

  // 5. Groq cleanup
  let groqKey = existing.GROQ_API_KEY || "";
  const { useGroq } = await prompts(
    {
      type: "confirm",
      name: "useGroq",
      message: "Enable LLM transcript cleanup? (removes filler words, fixes punctuation via Groq)",
      initial: !!groqKey,
    },
    { onCancel }
  );

  if (useGroq) {
    const { key } = await prompts(
      {
        type: "text",
        name: "key",
        message: "Groq API key (free at console.groq.com)",
        initial: groqKey,
        validate: (v) => (v.length > 0 ? true : "API key is required for Groq cleanup"),
      },
      { onCancel }
    );
    groqKey = key;
  } else {
    groqKey = "";
  }

  // Write config
  writeEnv({
    provider,
    elevenlabsKey,
    deepgramKey,
    groqKey,
    hotkey,
    micPreference,
    micBlacklist,
  });

  console.log();
  console.log(chalk.green("✅ Configuration saved to .env"));
  console.log();
  console.log(chalk.bold("Settings:"));
  console.log(`  Provider:  ${chalk.cyan(provider)}`);
  console.log(`  Hotkey:    ${chalk.cyan(hotkey)}`);
  if (micPreference) console.log(`  Mic pref:  ${chalk.cyan(micPreference)}`);
  if (micBlacklist) console.log(`  Mic block: ${chalk.cyan(micBlacklist)}`);
  console.log(`  Groq:      ${chalk.cyan(groqKey ? "enabled" : "disabled")}`);

  return true;
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
