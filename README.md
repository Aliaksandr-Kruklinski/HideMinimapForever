
# HIDE MINIMAP FOREVER 1.0

Target: WoW Forever beta 1.60.1 (Interface 16001)

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

### Otinal Requirements

- Node.js 16.7 or newer
- npm (included with Node.js)

Download Node.js: https://nodejs.org/

### Project structure

```text
project/
├── src/
│   ├── HideMinimapForever.toc
│   ├── HideMinimapForever.lua
│   └── options.lua
├── scripts/
│   └── build.js
├── dist/
│   └── HideMinimapForever/
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

No external npm dependencies or `npm install` required.

### Build output

```text
dist/
└── HideMinimapForever/
    ├── HideMinimapForever.toc
    ├── HideMinimapForever.lua
    └── options.lua
```

Copy the generated `HideMinimapForever` folder into your WoW `Interface/AddOns/` directory.

## IMPORTANT

WoW Forever uses retail-style APIs with Interface number 16001.

If the addon is marked outdated, verify the installed build with:

```lua
/run print(select(4, GetBuildInfo()))
```

Then update the `## Interface` field in the relevant `.toc` files.
