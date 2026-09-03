import Phaser from "phaser";

export class BootScene extends Phaser.Scene {
  constructor() {
    super("Boot");
  }

  preload(): void {
    const { width, height } = this.scale;
    const barWidth = Math.min(420, width * 0.5);
    const barX = (width - barWidth) / 2;
    const barY = height / 2;

    const frame = this.add.rectangle(width / 2, barY, barWidth, 18, 0x4a4740);
    frame.setStrokeStyle(2, 0x8b3a2f);

    const fill = this.add.rectangle(barX + 2, barY, 4, 12, 0x9aad3a);
    fill.setOrigin(0, 0.5);

    this.load.on("progress", (value: number) => {
      fill.width = Math.max(4, (barWidth - 4) * value);
    });

    this.load.image("title-screen", "assets/title-screen.png");
    this.load.image("boss-crt", "assets/boss-crt.png");
    this.load.image("dialogue-panel", "assets/dialogue-panel.png");
    this.load.image("ussr-pipboy-map", "assets/ussr-pipboy-map.png");
  }

  create(): void {
    this.scene.start("Menu");
  }
}
