
const fs = require("node:fs");
const path = require("node:path");

const src = path.join(__dirname, "../src");
const dest = path.join(__dirname, "../dist/HideMinimapForever");

// Clean previous build
fs.rmSync(dest, { recursive: true, force: true });

console.log("Cleaned previous build: dist/HideMinimapForever");
