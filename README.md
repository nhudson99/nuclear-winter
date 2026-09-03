# Nuclear Winter

Title screen and tutorial intro for a post-fallout USSR scavenging game. Built with **Phaser 3**, **Vite**, and **TypeScript**, and shippable as a browser app, Electron desktop app, or Capacitor mobile app from the same `dist/` build.

## Flow

1. **Menu** — full-bleed title art; press any button
2. **Boss briefing** — CRT portrait + rusty dialogue panel (`You want to eat? Then get to work`)
3. **Pip-Boy map** — green CRT map of the USSR

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
src/main.ts
src/scenes/BootScene.ts
src/scenes/MenuScene.ts
src/scenes/TutorialBossScene.ts
src/scenes/TutorialMapScene.ts
public/assets/title-screen.png
public/assets/boss-crt.png
public/assets/dialogue-panel.png
public/assets/ussr-pipboy-map.png
electron/main.cjs
capacitor.config.ts
```

## Packaging notes

- **Web:** `vite build` writes static files to `dist/`.
- **Desktop:** Electron loads `dist/index.html`.
- **Mobile:** Capacitor copies `dist/` into the Android/iOS projects via `npm run mobile:sync`.
