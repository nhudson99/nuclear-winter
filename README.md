# Nuclear Winter

A top-down scavenging game set in a silent post-fallout Soviet city. Built with **Phaser 3**, **Vite**, and **TypeScript**, and shippable as a browser game, Electron desktop app, or Capacitor mobile app from the same `dist/` build.

## Play

| Target | Command |
|--------|---------|
| Browser (dev) | `npm install && npm run dev` |
| Browser (production build) | `npm run build && npm run preview` |
| Desktop (Electron) | `npm run desktop` |
| Mobile sync | `npm run mobile:sync` |
| Android Studio | `npm run mobile:android` |
| Xcode (macOS) | `npm run mobile:ios` |

Open the local Vite URL (default `http://localhost:5173`) for the browser target.

### Controls

- **Desktop:** WASD / arrow keys to move, `ESC` or **BACK** for the menu
- **Touch:** drag on the left half of the screen as a virtual stick; tap **BEGIN** / **BACK**

### Objective

Collect **3 supplies**, avoid the green radiation haze, and reach the bunker marker.

## Project layout

```
src/main.ts                 Phaser game bootstrap (1280×720, Scale.FIT)
src/scenes/BootScene.ts     Asset loading
src/scenes/MenuScene.ts     Full-bleed title screen
src/scenes/GameScene.ts     Scavenging slice
src/input/touchControls.ts  Virtual stick
public/assets/title-screen.png
electron/main.cjs           Desktop shell
capacitor.config.ts         Mobile wrappers (webDir: dist)
```

## Packaging notes

- **Web:** `vite build` writes static files to `dist/`.
- **Desktop:** Electron loads `dist/index.html`. Use `electron-builder` later if you need signed installers.
- **Mobile:** Capacitor copies `dist/` into the Android/iOS projects via `npm run mobile:sync`. Open the native IDE to run on a device or emulator. Store signing is left to your release process.
