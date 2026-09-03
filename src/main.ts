import Phaser from "phaser";
import { BootScene } from "./scenes/BootScene";
import { MenuScene } from "./scenes/MenuScene";
import { TutorialBossScene } from "./scenes/TutorialBossScene";
import { TutorialMapScene } from "./scenes/TutorialMapScene";
import { MainPlayScene } from "./scenes/MainPlayScene";

const config: Phaser.Types.Core.GameConfig = {
  type: Phaser.AUTO,
  parent: "game-container",
  width: 1280,
  height: 720,
  backgroundColor: "#1a1a16",
  physics: {
    default: "arcade",
    arcade: {
      gravity: { x: 0, y: 0 },
      debug: false,
    },
  },
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
  },
  input: {
    activePointers: 3,
  },
  scene: [BootScene, MenuScene, TutorialBossScene, TutorialMapScene, MainPlayScene],
};

new Phaser.Game(config);
