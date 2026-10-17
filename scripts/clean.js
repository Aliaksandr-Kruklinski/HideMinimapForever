
const fs = require("node:fs");
const path = require("node:path");
const config = require("../config.json");

const projectRoot = path.resolve(__dirname, "..");
const dest = path.join(projectRoot, "dist", config.addonName);

// Clean previous build
fs.rmSync(dest, { recursive: true, force: true });

console.log(`Cleaned previous build: dist/${config.addonName}`);
