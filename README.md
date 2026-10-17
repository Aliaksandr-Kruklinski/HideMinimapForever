# HIDE MINIMAP FOREVER 1.0

**Target:** WoW Forever beta 1.60.1 (Interface 16001)

## INSTALL

1. Unzip into `World of Warcraft/_classic_beta_/Interface/AddOns/`
2. The folder should be: `AddOns/HideMinimapForever/`
3. Restart WoW or type `/reload`.
4. Open options with `/fmf`, or right-click the minimap button.

## FEATURES

- Fade and fully hide minimap after customizable idle delay
- Smooth configurable fade speed
- Fade-only mode with adjustable minimum opacity
- Mouse-over reveals the minimap when hidden
- Optional always-visible minimap during combat
- Movable minimap button (drag around map)
- Left click: enable / disable automatic hiding
- Right click: open addon options
- Middle click: pin minimap visible / resume auto hiding
- Settings saved between sessions

## DEVELOPMENT

### Requirements

- Node.js 16.7 or newer
- npm (included with Node.js)

Download Node.js: https://nodejs.org/

No external npm dependencies or `npm install` required.

### Project Structure

```text
project/
├── src/
│   ├── HideMinimapForever.toc
│   ├── HideMinimapForever.lua
│   └── options.lua
├── scripts/
│   ├── build.js
│   └── deploy.js
├── dist/
│   └── HideMinimapForever/
├── config.json
├── package.json
└── README.md
```

### Build

Run the following command from the project root:

```bash
npm run build
```

The build script will:

1. Remove the previous `dist/HideMinimapForever` folder.
2. Copy all files and subfolders from `src/`.
3. Generate the addon in `dist/HideMinimapForever/`.

### Build Output

```text
dist/
└── HideMinimapForever/
    ├── HideMinimapForever.toc
    ├── HideMinimapForever.lua
    └── options.lua
```

The generated `HideMinimapForever` folder is ready for distribution or manual installation into WoW's `Interface/AddOns/` directory.

### Deploy

The deployment script automatically installs the addon into your local World of Warcraft installation.

**1. Configure the AddOns directory**

Create a `config.json` file in the project root:

```json
{
  "wowAddonsPath": "C:/Games/World of Warcraft/_classic_beta_/Interface/AddOns"
}
```

Replace the example path with your actual WoW AddOns directory.

Use forward slashes (`/`) in Windows paths or escape backslashes (`\\`).

**2. Run deployment**

```bash
npm run deploy
```

npm automatically executes the scripts in the following order:

1. `predeploy` — runs `npm run build`.
2. `deploy` — runs `node scripts/deploy.js`.

The deployment process will:

1. Build the latest addon files into `dist/HideMinimapForever/`.
2. Verify that the build output and configured AddOns directory exist.
3. Remove the previous installed `HideMinimapForever` folder.
4. Copy the freshly built addon into the WoW AddOns directory.

If the build fails, deployment will not proceed.

**3. npm scripts**

```json
{
  "scripts": {
    "build": "node scripts/build.js",
    "predeploy": "npm run build",
    "deploy": "node scripts/deploy.js"
  }
}
```

**4. Reload WoW**

After deployment, type `/reload` in-game to load the updated addon.

### Development Notes

- `npm run build` — prepare a distributable addon in `dist/`.
- `npm run deploy` — build and install the addon into the configured WoW directory.
- `config.json` contains a machine-specific installation path and should be added to `.gitignore`.
- The deployment replaces the existing installed addon folder, so do not store custom files inside it.
- No external npm dependencies are required.

## IMPORTANT

WoW Forever uses retail-style APIs with Interface number `16001`.

If the addon is marked outdated, verify the installed build with:

```lua
/run print(select(4, GetBuildInfo()))
```

Then update the `## Interface` field in the relevant `.toc` files.