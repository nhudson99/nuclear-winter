import Phaser from "phaser";

const RUST = 0x8b3a2f;
const ASH = "#c8c4b8";

export class MenuScene extends Phaser.Scene {
  private ashEmitter: Phaser.GameObjects.Particles.ParticleEmitter | null = null;
  private starting = false;

  constructor() {
    super("Menu");
  }

  create(): void {
    this.starting = false;
    const { width, height } = this.scale;

    const bg = this.add.image(width / 2, height / 2, "title-screen");
    bg.setDisplaySize(width, height);
    bg.setDepth(0);

    this.createAsh(width, height);

    const brand = this.add
      .text(width / 2, height * 0.62, "NUCLEAR WINTER", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "72px",
        color: ASH,
        stroke: "#1a1a16",
        strokeThickness: 6,
        align: "center",
      })
      .setOrigin(0.5)
      .setDepth(2);

    this.tweens.add({
      targets: brand,
      y: brand.y - 8,
      duration: 4200,
      yoyo: true,
      repeat: -1,
      ease: "Sine.easeInOut",
    });

    this.add
      .text(width / 2, height * 0.74, "Scavenge the silent republic.", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "22px",
        color: "#a39e90",
        stroke: "#1a1a16",
        strokeThickness: 3,
        align: "center",
      })
      .setOrigin(0.5)
      .setDepth(2);

    const begin = this.add
      .text(width / 2, height * 0.86, "BEGIN", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "36px",
        color: "#f0ebe0",
        stroke: "#1a1a16",
        strokeThickness: 4,
        padding: { x: 28, y: 16 },
      })
      .setOrigin(0.5)
      .setDepth(2)
      .setInteractive({ useHandCursor: true });

    begin.on("pointerover", () => {
      begin.setColor("#9aad3a");
    });
    begin.on("pointerout", () => {
      begin.setColor("#f0ebe0");
    });
    begin.on("pointerdown", () => {
      if (this.starting) {
        return;
      }
      this.starting = true;
      this.cameras.main.fadeOut(280, 26, 26, 22);
    });

    this.cameras.main.once(
      Phaser.Cameras.Scene2D.Events.FADE_OUT_COMPLETE,
      () => {
        this.scene.start("Game");
      },
    );

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

    // Keep a soft continuous fall across the full viewport height.
    void height;
  }

  shutdown(): void {
    this.ashEmitter?.destroy();
    this.ashEmitter = null;
  }
}
