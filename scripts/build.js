
const fs = require("node:fs");
const path = require("node:path");

const src = path.join(__dirname, "../src");
const dest = path.join(__dirname, "../dist/HideMinimapForever");

// Clean previous build
fs.rmSync(dest, { recursive: true, force: true });

// Copy all files and subfolders
fs.cpSync(src, dest, { recursive: true });

console.log("Build complete: dist/HideMinimapForever");
