import Phaser from "phaser";

type Floor = 1 | 2;

type WallSpec = { x: number; y: number; w: number; h: number };

type StairsSide = "left" | "right";

export class MainPlayScene extends Phaser.Scene {
  private player!: Phaser.Physics.Arcade.Image;

  private cursors!: Phaser.Types.Input.Keyboard.CursorKeys;
  private wasd!: {
    W: Phaser.Input.Keyboard.Key;
    A: Phaser.Input.Keyboard.Key;
    S: Phaser.Input.Keyboard.Key;
    D: Phaser.Input.Keyboard.Key;
  };

  private pointerDown = false;

  private floor: Floor = 1;
  private floorBg1!: Phaser.GameObjects.Image;
  private floorBg2!: Phaser.GameObjects.Image;

  private wallsFloor1: Phaser.GameObjects.Rectangle[] = [];
  private wallsFloor2: Phaser.GameObjects.Rectangle[] = [];

  private leftStairsZone!: Phaser.GameObjects.Zone;
  private rightStairsZone!: Phaser.GameObjects.Zone;

  private lastStairSwitchAt = 0;
  private readonly stairCooldownMs = 900;

  constructor() {
    super("MainPlay");
  }

  create(): void {
    const { width, height } = this.scale;

    this.physics.world.setBounds(0, 0, width, height);

    // Two floor backgrounds; swap alpha when using stair zones.
    this.floorBg1 = this.add
      .image(width / 2, height / 2, "mansion-floor1")
      .setDisplaySize(width, height)
      .setDepth(0);

    this.floorBg2 = this.add
      .image(width / 2, height / 2, "mansion-floor2")
      .setDisplaySize(width, height)
      .setDepth(0)
      .setAlpha(0);

    this.cursors = this.input.keyboard!.createCursorKeys();
    this.wasd = {
      W: this.input.keyboard!.addKey(Phaser.Input.Keyboard.KeyCodes.W),
      A: this.input.keyboard!.addKey(Phaser.Input.Keyboard.KeyCodes.A),
      S: this.input.keyboard!.addKey(Phaser.Input.Keyboard.KeyCodes.S),
      D: this.input.keyboard!.addKey(Phaser.Input.Keyboard.KeyCodes.D),
    };

    this.input.on("pointerdown", this.onPointerDown, this);
    this.input.on("pointerup", this.onPointerUp, this);
    this.input.on("pointerupoutside", this.onPointerUp, this);

    // Player sprite: head-and-shoulders token with transparent PNG alpha.
    this.player = this.physics.add.image(width / 2, height * 0.68, "gulag-prisoner");
    this.player.setDepth(2);
    this.player.setDrag(600, 600);
    this.player.setMaxVelocity(240, 240);
    this.player.setCollideWorldBounds(false);

    const desiredSpriteWidth = Math.min(64, width * 0.055);
    const scale = desiredSpriteWidth / this.player.width;
    this.player.setScale(scale);
    const bodyRadius = (desiredSpriteWidth * 0.38) / this.player.scaleX;
    this.player.setCircle(bodyRadius);

    this.createMansionPhysics(width, height);

    this.applyFloor(1, "left");

    // Escape hatch
    this.input.keyboard?.once("keydown-ESC", () => {
      this.scene.start("TutorialMap");
    });
  }

  private onPointerDown(): void {
    this.pointerDown = true;
  }

  private onPointerUp(): void {
    this.pointerDown = false;
  }

  update(): void {
    if (!this.player.body) {
      return;
    }

    const { width } = this.scale;
    const speed = Math.min(200, width * 0.16);

    let dirX = 0;
    let dirY = 0;

    // Keyboard WASD / arrows.
    if (this.cursors.left.isDown || this.wasd.A.isDown) {
      dirX -= 1;
    }
    if (this.cursors.right.isDown || this.wasd.D.isDown) {
      dirX += 1;
    }
    if (this.cursors.up.isDown || this.wasd.W.isDown) {
      dirY -= 1;
    }
    if (this.cursors.down.isDown || this.wasd.S.isDown) {
      dirY += 1;
    }

    // Touch: move toward the pressed pointer position.
    if (this.pointerDown) {
      const pointer = this.input.activePointer;
      dirX = pointer.worldX - this.player.x;
      dirY = pointer.worldY - this.player.y;
    }

    const len = Math.hypot(dirX, dirY);
    if (len < 0.001) {
      this.player.setVelocity(0, 0);
      return;
    }

    const nx = dirX / len;
    const ny = dirY / len;

    this.player.setVelocity(nx * speed, ny * speed);
  }

  private createMansionPhysics(width: number, height: number): void {
    const mansionW = width * 0.58;
    const mansionH = height * 0.56;
    const mansionLeft = (width - mansionW) / 2;
    const mansionTop = (height - mansionH) / 2 + 10;

    const wallThickness = Math.max(14, Math.round(width * 0.018));

    const mkWall = (spec: WallSpec): Phaser.GameObjects.Rectangle => {
      const r = this.add.rectangle(spec.x, spec.y, spec.w, spec.h, 0x000000, 0);
      this.physics.add.existing(r, true);
      r.setDepth(1);
      return r;
    };

    // FLOOR 1: outer ring + one vertical wall.
    const floor1Walls: WallSpec[] = [
      { x: mansionLeft + wallThickness / 2, y: mansionTop + mansionH / 2, w: wallThickness, h: mansionH },
      {
        x: mansionLeft + mansionW - wallThickness / 2,
        y: mansionTop + mansionH / 2,
        w: wallThickness,
        h: mansionH,
      },
      { x: mansionLeft + mansionW / 2, y: mansionTop + wallThickness / 2, w: mansionW, h: wallThickness },
      {
        x: mansionLeft + mansionW / 2,
        y: mansionTop + mansionH - wallThickness / 2,
        w: mansionW,
        h: wallThickness,
      },
      {
        x: mansionLeft + mansionW / 2,
        y: mansionTop + mansionH * 0.52,
        w: wallThickness,
        h: mansionH * 0.35,
      },
    ];

    this.wallsFloor1 = floor1Walls.map((s) => mkWall(s));

    // FLOOR 2: outer ring + one horizontal wall.
    const floor2Walls: WallSpec[] = [
      { x: mansionLeft + wallThickness / 2, y: mansionTop + mansionH / 2, w: wallThickness, h: mansionH },
      {
        x: mansionLeft + mansionW - wallThickness / 2,
        y: mansionTop + mansionH / 2,
        w: wallThickness,
        h: mansionH,
      },
      { x: mansionLeft + mansionW / 2, y: mansionTop + wallThickness / 2, w: mansionW, h: wallThickness },
      {
        x: mansionLeft + mansionW / 2,
        y: mansionTop + mansionH - wallThickness / 2,
        w: mansionW,
        h: wallThickness,
      },
      {
        x: mansionLeft + mansionW * 0.52,
        y: mansionTop + mansionH / 2,
        w: mansionW * 0.34,
        h: wallThickness,
      },
    ];

    this.wallsFloor2 = floor2Walls.map((s) => mkWall(s));

    // Add colliders once (walls will be enabled/disabled per floor).
    for (const wall of this.wallsFloor1) {
      this.physics.add.collider(this.player, wall);
    }
    for (const wall of this.wallsFloor2) {
      this.physics.add.collider(this.player, wall);
    }

    // Stair zones.
    const stairsW = mansionW * 0.16;
    const stairsH = mansionH * 0.18;
    const stairsY = mansionTop + mansionH * 0.56;

    const leftX = mansionLeft + stairsW / 2 + wallThickness * 1.2;
    const rightX = mansionLeft + mansionW - stairsW / 2 - wallThickness * 1.2;

    this.leftStairsZone = this.add
      .zone(leftX, stairsY, stairsW, stairsH)
      .setOrigin(0.5)
      .setDepth(1);
    this.rightStairsZone = this.add
      .zone(rightX, stairsY, stairsW, stairsH)
      .setOrigin(0.5)
      .setDepth(1);

    this.physics.add.existing(this.leftStairsZone, true);
    this.physics.add.existing(this.rightStairsZone, true);

    this.physics.add.overlap(this.player, this.leftStairsZone, () => {
      this.trySwitchFloor(2, "left");
    });

    this.physics.add.overlap(this.player, this.rightStairsZone, () => {
      this.trySwitchFloor(1, "right");
    });
  }

  private trySwitchFloor(targetFloor: Floor, side: StairsSide): void {
    const now = this.time.now;
    if (now - this.lastStairSwitchAt < this.stairCooldownMs) {
      return;
    }
    if (targetFloor === this.floor) {
      return;
    }

    this.lastStairSwitchAt = now;
    this.applyFloor(targetFloor, side);
  }

  private applyFloor(targetFloor: Floor, side: StairsSide): void {
    this.floor = targetFloor;

    this.floorBg1.setAlpha(targetFloor === 1 ? 1 : 0);
    this.floorBg2.setAlpha(targetFloor === 2 ? 1 : 0);

    for (const wall of this.wallsFloor1) {
      const body = wall.body as any;
      if (body) {
        body.enable = targetFloor === 1;
      }
    }
    for (const wall of this.wallsFloor2) {
      const body = wall.body as any;
      if (body) {
        body.enable = targetFloor === 2;
      }
    }

    const px = side === "left" ? this.leftStairsZone.x : this.rightStairsZone.x;
    const py =
      side === "left" ? this.leftStairsZone.y + 10 : this.rightStairsZone.y + 8;
    this.player.setPosition(px, py);

    // Let movement resume smoothly.
    this.player.setVelocity(0, 0);
  }

  shutdown(): void {
    this.pointerDown = false;
    this.input.off("pointerdown", this.onPointerDown, this);
    this.input.off("pointerup", this.onPointerUp, this);
    this.input.off("pointerupoutside", this.onPointerUp, this);
  }
}
