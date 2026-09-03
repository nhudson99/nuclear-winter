# Nuclear Winter

Title screen for a post-fallout USSR game. Built with **Phaser 3**, **Vite**, and **TypeScript**, and shippable as a browser app, Electron desktop app, or Capacitor mobile app from the same `dist/` build.

## Run

| Target | Command |
|--------|---------|
| Browser (dev) | `npm install && npm run dev` |
| Browser (production build) | `npm run build && npm run preview` |
| Desktop (Electron) | `npm run desktop` |
| Mobile sync | `npm run mobile:sync` |
| Android Studio | `npm run mobile:android` |
| Xcode (macOS) | `npm run mobile:ios` |

Open the local Vite URL (default `http://localhost:5173`) for the browser target.

## Project layout

```
src/main.ts                 Phaser game bootstrap (1280×720, Scale.FIT)
src/scenes/BootScene.ts     Asset loading
src/scenes/MenuScene.ts     Full-bleed title screen
public/assets/title-screen.png
electron/main.cjs           Desktop shell
capacitor.config.ts         Mobile wrappers (webDir: dist)
```

## Packaging notes

- **Web:** `vite build` writes static files to `dist/`.
- **Desktop:** Electron loads `dist/index.html`. Use `electron-builder` later if you need signed installers.
- **Mobile:** Capacitor copies `dist/` into the Android/iOS projects via `npm run mobile:sync`. Open the native IDE to run on a device or emulator. Store signing is left to your release process.
