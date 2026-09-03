import Phaser from "phaser";

export class TutorialMapScene extends Phaser.Scene {
  private selectionRect?: Phaser.GameObjects.Rectangle;
  private entering = false;

  constructor() {
    super("TutorialMap");
  }

  create(): void {
    const { width, height } = this.scale;

    this.add.rectangle(width / 2, height / 2, width, height, 0x020804).setDepth(0);

    const map = this.add.image(width / 2, height / 2, "ussr-pipboy-map");
    map.setDisplaySize(width, height);
    map.setDepth(0);

    const scan = this.add.graphics().setDepth(1).setAlpha(0.12);
    for (let y = 0; y < height; y += 3) {
      scan.fillStyle(0x001100, 1);
      scan.fillRect(0, y, width, 1);
    }

    const squareSize = Math.min(width, height) * 0.22;
    const squareX = width * 0.52;
    const squareY = height * 0.56;

    this.selectionRect = this.add
      .rectangle(squareX, squareY, squareSize, squareSize, 0x7dff7a, 0)
      .setStrokeStyle(6, 0x7dff7a, 1)
      .setDepth(3)
      .setAlpha(0.2)
      .setInteractive({ useHandCursor: true });

    this.tweens.add({
      targets: this.selectionRect,
      alpha: 1,
      duration: 650,
      yoyo: true,
      repeat: -1,
      ease: "Sine.easeInOut",
    });

    this.selectionRect.on("pointerdown", () => {
      if (this.entering) {
        return;
      }
      this.entering = true;

      this.cameras.main.fadeOut(260, 2, 8, 4);
      this.cameras.main.once(
        Phaser.Cameras.Scene2D.Events.FADE_OUT_COMPLETE,
        () => {
          this.scene.start("MainPlay", { mapId: 0 });
        },
      );
    });

    this.input.keyboard?.once("keydown-ESC", () => {
      this.scene.start("Menu");
    });

    this.cameras.main.fadeIn(350, 2, 8, 4);
  }

  shutdown(): void {
    this.entering = false;
    if (this.selectionRect) {
      this.tweens.killTweensOf(this.selectionRect);
      this.selectionRect.removeAllListeners();
    }
  }
}
