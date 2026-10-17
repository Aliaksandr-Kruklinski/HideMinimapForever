
const fs = require("node:fs");
const path = require("node:path");
const config = require("../config.json");

const addonName = "HideMinimapForever";
const projectRoot = path.resolve(__dirname, "..");

const src = path.join(projectRoot, "dist", addonName);
const addonsDir = path.resolve(config.wowAddonsPath);
const dest = path.join(addonsDir, addonName);

// Verify build output
if (!fs.existsSync(src)) {
    throw new Error(`Build output not found: ${src}`);
}

// Verify WoW AddOns directory
if (!fs.existsSync(addonsDir)) {
    throw new Error(`WoW AddOns directory not found: ${addonsDir}`);
}

// Clean previous deployment
fs.rmSync(dest, { recursive: true, force: true });

// Copy built addon
fs.cpSync(src, dest, { recursive: true });

console.log(`Deployment complete: ${dest}`);
