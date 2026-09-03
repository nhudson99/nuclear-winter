import Phaser from "phaser";

export class TutorialMapScene extends Phaser.Scene {
  constructor() {
    super("TutorialMap");
  }

  create(): void {
    const { width, height } = this.scale;

    this.add.rectangle(width / 2, height / 2, width, height, 0x020804);

    const map = this.add.image(width / 2, height / 2, "ussr-pipboy-map");
    map.setDisplaySize(width, height);
    map.setDepth(0);

    // Soft scanline overlay for Pip-Boy CRT feel
    const scan = this.add.graphics().setDepth(1).setAlpha(0.12);
    for (let y = 0; y < height; y += 3) {
      scan.fillStyle(0x001100, 1);
      scan.fillRect(0, y, width, 1);
    }

    const hint = this.add
      .text(width - 36, height - 36, "Press any key to continue", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "20px",
        color: "#7dff7a",
        stroke: "#001400",
        strokeThickness: 4,
      })
      .setOrigin(1, 1)
      .setDepth(2);

    this.tweens.add({
      targets: hint,
      alpha: 0.25,
      duration: 800,
      yoyo: true,
      repeat: -1,
      ease: "Sine.easeInOut",
    });

    const advance = () => {
      this.input.keyboard?.off("keydown", advance);
      this.input.off("pointerdown", advance);
      this.cameras.main.fadeOut(280, 2, 8, 4);
      this.cameras.main.once(
        Phaser.Cameras.Scene2D.Events.FADE_OUT_COMPLETE,
        () => {
          this.scene.start("Menu");
        },
      );
    };

    this.input.keyboard?.once("keydown", advance);
    this.input.once("pointerdown", advance);

    this.cameras.main.fadeIn(350, 2, 8, 4);
  }
}
