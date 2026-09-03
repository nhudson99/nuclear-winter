import Phaser from "phaser";

const RUST = 0x8b3a2f;

export class MenuScene extends Phaser.Scene {
  private ashEmitter: Phaser.GameObjects.Particles.ParticleEmitter | null = null;

  constructor() {
    super("Menu");
  }

  create(): void {
    const { width, height } = this.scale;

    const bg = this.add.image(width / 2, height / 2, "title-screen");
    bg.setDisplaySize(width, height);
    bg.setDepth(0);

    this.createAsh(width, height);

    const prompt = this.add
      .text(36, height - 40, "Press Any Button", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "28px",
        color: "#e8e2d4",
        stroke: "#1a1a16",
        strokeThickness: 5,
      })
      .setOrigin(0, 1)
      .setDepth(2);

    this.tweens.add({
      targets: prompt,
      alpha: 0.25,
      duration: 900,
      yoyo: true,
      repeat: -1,
      ease: "Sine.easeInOut",
    });

    this.cameras.main.fadeIn(400, 26, 26, 22);
  }

  private createAsh(width: number, height: number): void {
    const gfx = this.make.graphics({ x: 0, y: 0 }, false);
    gfx.fillStyle(0xd8d4c8, 1);
    gfx.fillCircle(4, 4, 3);
    gfx.generateTexture("ash-flake", 8, 8);
    gfx.destroy();

    this.ashEmitter = this.add.particles(0, 0, "ash-flake", {
      x: { min: 0, max: width },
      y: { min: -20, max: 0 },
      lifespan: { min: 6000, max: 11000 },
      speedY: { min: 18, max: 42 },
      speedX: { min: -12, max: 12 },
      scale: { min: 0.25, max: 0.7 },
      alpha: { start: 0.55, end: 0 },
      quantity: 2,
      frequency: 120,
      blendMode: "ADD",
      tint: [0xc8c4b8, 0x9aad3a, RUST],
    });
    this.ashEmitter.setDepth(1);
    this.ashEmitter.setScrollFactor(0);

    void height;
  }

  shutdown(): void {
    this.ashEmitter?.destroy();
    this.ashEmitter = null;
  }
}
