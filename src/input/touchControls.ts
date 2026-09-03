import Phaser from "phaser";

export type StickVector = { x: number; y: number };

/**
 * Left-half virtual stick for touch / pointer drag.
 * Returns a normalized direction vector each frame.
 */
export class TouchControls {
  private readonly scene: Phaser.Scene;
  private base: Phaser.GameObjects.Arc;
  private thumb: Phaser.GameObjects.Arc;
  private activePointerId: number | null = null;
  private originX = 0;
  private originY = 0;
  private vector: StickVector = { x: 0, y: 0 };
  private readonly maxRadius = 54;
  private readonly leftHalfOnly: boolean;

  constructor(scene: Phaser.Scene, leftHalfOnly = true) {
    this.scene = scene;
    this.leftHalfOnly = leftHalfOnly;

    const { height } = scene.scale;
    const startX = 110;
    const startY = height - 110;

    this.base = scene.add
      .circle(startX, startY, this.maxRadius, 0x4a4740, 0.35)
      .setStrokeStyle(2, 0xc8c4b8, 0.45)
      .setScrollFactor(0)
      .setDepth(20)
      .setVisible(false);

    this.thumb = scene.add
      .circle(startX, startY, 28, 0x8b3a2f, 0.7)
      .setScrollFactor(0)
      .setDepth(21)
      .setVisible(false);

    scene.input.on("pointerdown", this.onDown, this);
    scene.input.on("pointermove", this.onMove, this);
    scene.input.on("pointerup", this.onUp, this);
    scene.input.on("pointerupoutside", this.onUp, this);
  }

  getVector(): StickVector {
    return this.vector;
  }

  destroy(): void {
    this.scene.input.off("pointerdown", this.onDown, this);
    this.scene.input.off("pointermove", this.onMove, this);
    this.scene.input.off("pointerup", this.onUp, this);
    this.scene.input.off("pointerupoutside", this.onUp, this);
    this.base.destroy();
    this.thumb.destroy();
  }

  private onDown(pointer: Phaser.Input.Pointer): void {
    if (this.activePointerId !== null) {
      return;
    }
    if (this.leftHalfOnly && pointer.x > this.scene.scale.width * 0.55) {
      return;
    }

    this.activePointerId = pointer.id;
    this.originX = pointer.x;
    this.originY = pointer.y;
    this.base.setPosition(this.originX, this.originY).setVisible(true);
    this.thumb.setPosition(this.originX, this.originY).setVisible(true);
    this.vector = { x: 0, y: 0 };
  }

  private onMove(pointer: Phaser.Input.Pointer): void {
    if (pointer.id !== this.activePointerId) {
      return;
    }

    const dx = pointer.x - this.originX;
    const dy = pointer.y - this.originY;
    const len = Math.hypot(dx, dy);
    const clamped = Math.min(len, this.maxRadius);
    const nx = len > 0 ? dx / len : 0;
    const ny = len > 0 ? dy / len : 0;

    this.thumb.setPosition(
      this.originX + nx * clamped,
      this.originY + ny * clamped,
    );
    this.vector = {
      x: nx * (clamped / this.maxRadius),
      y: ny * (clamped / this.maxRadius),
    };
  }

  private onUp(pointer: Phaser.Input.Pointer): void {
    if (pointer.id !== this.activePointerId) {
      return;
    }
    this.activePointerId = null;
    this.vector = { x: 0, y: 0 };
    this.base.setVisible(false);
    this.thumb.setVisible(false);
  }
}
