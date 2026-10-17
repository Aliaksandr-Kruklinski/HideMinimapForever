
const fs = require("node:fs");
const path = require("node:path");
const config = require("../config.json");

const projectRoot = path.resolve(__dirname, "..");
const src = path.join(projectRoot, "src");
const dest = path.join(projectRoot, "dist", config.addonName);

// Copy all files and subfolders
fs.cpSync(src, dest, { recursive: true });

console.log(`Build complete: dist/${config.addonName}`);
