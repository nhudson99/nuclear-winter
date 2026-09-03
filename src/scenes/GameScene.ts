import Phaser from "phaser";
import { TouchControls } from "../input/touchControls";

const PLAYER_SPEED = 180;
const RADIATION_MAX = 100;
const SUPPLIES_NEEDED = 3;

type BuildingSpec = { x: number; y: number; w: number; h: number };

export class GameScene extends Phaser.Scene {
  private player!: Phaser.Physics.Arcade.Image;
  private cursors: Phaser.Types.Input.Keyboard.CursorKeys | null = null;
  private wasd: {
    W: Phaser.Input.Keyboard.Key;
    A: Phaser.Input.Keyboard.Key;
    S: Phaser.Input.Keyboard.Key;
    D: Phaser.Input.Keyboard.Key;
  } | null = null;
  private touch!: TouchControls;
  private supplies!: Phaser.Physics.Arcade.Group;
  private radiationZone!: Phaser.GameObjects.Zone;
  private bunker!: Phaser.Physics.Arcade.Image;
  private radiation = RADIATION_MAX;
  private supplyCount = 0;
  private radiationBar!: Phaser.GameObjects.Rectangle;
  private supplyText!: Phaser.GameObjects.Text;
  private statusText!: Phaser.GameObjects.Text;
  private backButton!: Phaser.GameObjects.Text;
  private ended = false;
  private leaving = false;
  private inRadiation = false;

  constructor() {
    super("Game");
  }

  create(): void {
    this.ended = false;
    this.leaving = false;
    this.radiation = RADIATION_MAX;
    this.supplyCount = 0;
    this.inRadiation = false;

    const mapW = 1920;
    const mapH = 1280;
    this.cameras.main.setBounds(0, 0, mapW, mapH);
    this.physics.world.setBounds(0, 0, mapW, mapH);

    this.drawWorld(mapW, mapH);
    this.createTextures();

    const buildings = this.physics.add.staticGroup();
    const buildingSpecs: BuildingSpec[] = [
      { x: 220, y: 200, w: 280, h: 160 },
      { x: 620, y: 180, w: 200, h: 220 },
      { x: 1100, y: 240, w: 320, h: 140 },
      { x: 1580, y: 200, w: 240, h: 180 },
      { x: 280, y: 620, w: 180, h: 260 },
      { x: 700, y: 700, w: 300, h: 160 },
      { x: 1200, y: 680, w: 220, h: 240 },
      { x: 1640, y: 720, w: 200, h: 200 },
      { x: 480, y: 1040, w: 340, h: 140 },
      { x: 1080, y: 1080, w: 260, h: 150 },
    ];

    for (const b of buildingSpecs) {
      const block = this.add
        .rectangle(b.x, b.y, b.w, b.h, 0x3a3832)
        .setStrokeStyle(3, 0x5c574c);
      this.physics.add.existing(block, true);
      buildings.add(block);
    }

    this.player = this.physics.add.image(160, 1120, "scavenger");
    this.player.setCollideWorldBounds(true);
    this.player.setDepth(5);
    this.cameras.main.startFollow(this.player, true, 0.12, 0.12);

    this.physics.add.collider(this.player, buildings);

    this.supplies = this.physics.add.group();
    const supplySpots = [
      { x: 420, y: 380 },
      { x: 980, y: 520 },
      { x: 1480, y: 980 },
    ];
    for (const spot of supplySpots) {
      const crate = this.supplies.create(spot.x, spot.y, "supply") as Phaser.Physics.Arcade.Image;
      crate.setImmovable(true);
      crate.setDepth(4);
    }

    this.physics.add.overlap(
      this.player,
      this.supplies,
      (_player, supply) => {
        const item = supply as Phaser.Physics.Arcade.Image;
        item.destroy();
        this.supplyCount += 1;
        this.supplyText.setText(`Supplies ${this.supplyCount}/${SUPPLIES_NEEDED}`);
        if (this.supplyCount >= SUPPLIES_NEEDED && !this.ended) {
          this.statusText.setText("Return to the bunker.");
          this.statusText.setColor("#9aad3a");
        }
      },
      undefined,
      this,
    );

    const radX = 900;
    const radY = 860;
    const radW = 360;
    const radH = 280;
    const haze = this.add.rectangle(radX, radY, radW, radH, 0x9aad3a, 0.18);
    haze.setStrokeStyle(2, 0x9aad3a, 0.55);
    haze.setDepth(2);

    this.radiationZone = this.add.zone(radX, radY, radW, radH);
    this.physics.add.existing(this.radiationZone, true);

    this.bunker = this.physics.add.image(1700, 1120, "bunker");
    this.bunker.setImmovable(true);
    this.bunker.setDepth(4);
    this.physics.add.overlap(
      this.player,
      this.bunker,
      () => {
        if (this.ended) {
          return;
        }
        if (this.supplyCount >= SUPPLIES_NEEDED) {
          this.endRun(true);
        } else {
          this.statusText.setText("Need more supplies.");
          this.statusText.setColor("#c8c4b8");
        }
      },
      undefined,
      this,
    );

    if (this.input.keyboard) {
      this.cursors = this.input.keyboard.createCursorKeys();
      this.wasd = {
        W: this.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.W),
        A: this.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.A),
        S: this.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.S),
        D: this.input.keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.D),
      };
      this.input.keyboard.on("keydown-ESC", () => {
        this.returnToMenu();
      });
    }

    this.touch = new TouchControls(this, true);
    this.createHud();
    this.cameras.main.fadeIn(350, 26, 26, 22);
  }

  update(_time: number, delta: number): void {
    if (this.ended) {
      this.player.setVelocity(0, 0);
      return;
    }

    this.inRadiation = this.physics.overlap(this.player, this.radiationZone);

    if (this.inRadiation) {
      this.radiation = Math.max(0, this.radiation - (18 * delta) / 1000);
      this.radiationBar.width = Math.max(2, 200 * (this.radiation / RADIATION_MAX));
      this.radiationBar.setFillStyle(0x9aad3a);
      if (this.radiation <= 0) {
        this.endRun(false);
        return;
      }
    } else {
      this.radiationBar.setFillStyle(0x8b3a2f);
    }

    let vx = 0;
    let vy = 0;

    if (this.cursors?.left.isDown || this.wasd?.A.isDown) {
      vx -= 1;
    }
    if (this.cursors?.right.isDown || this.wasd?.D.isDown) {
      vx += 1;
    }
    if (this.cursors?.up.isDown || this.wasd?.W.isDown) {
      vy -= 1;
    }
    if (this.cursors?.down.isDown || this.wasd?.S.isDown) {
      vy += 1;
    }

    const stick = this.touch.getVector();
    if (Math.abs(stick.x) > 0.08 || Math.abs(stick.y) > 0.08) {
      vx = stick.x;
      vy = stick.y;
    }

    const len = Math.hypot(vx, vy);
    if (len > 0) {
      vx = (vx / len) * PLAYER_SPEED;
      vy = (vy / len) * PLAYER_SPEED;
    }

    this.player.setVelocity(vx, vy);
  }

  private drawWorld(mapW: number, mapH: number): void {
    const g = this.add.graphics();
    g.fillStyle(0x2a2824, 1);
    g.fillRect(0, 0, mapW, mapH);

    g.lineStyle(2, 0x3d3a34, 0.6);
    for (let x = 0; x < mapW; x += 80) {
      g.lineBetween(x, 0, x, mapH);
    }
    for (let y = 0; y < mapH; y += 80) {
      g.lineBetween(0, y, mapW, y);
    }

    // Tram tracks
    g.lineStyle(4, 0x5a564c, 0.9);
    g.lineBetween(40, 1120, mapW - 40, 1120);
    g.lineBetween(40, 1140, mapW - 40, 1140);

    g.setDepth(0);
  }

  private createTextures(): void {
    if (!this.textures.exists("scavenger")) {
      const p = this.make.graphics({ x: 0, y: 0 }, false);
      p.fillStyle(0x5c5348, 1);
      p.fillRoundedRect(4, 10, 24, 28, 4);
      p.fillStyle(0xc8c4b8, 1);
      p.fillCircle(16, 10, 8);
      p.fillStyle(0x8b3a2f, 1);
      p.fillRect(8, 20, 16, 10);
      p.generateTexture("scavenger", 32, 40);
      p.destroy();
    }

    if (!this.textures.exists("supply")) {
      const s = this.make.graphics({ x: 0, y: 0 }, false);
      s.fillStyle(0x8b3a2f, 1);
      s.fillRoundedRect(0, 4, 28, 20, 3);
      s.lineStyle(2, 0xc8c4b8, 1);
      s.strokeRoundedRect(0, 4, 28, 20, 3);
      s.generateTexture("supply", 28, 28);
      s.destroy();
    }

    if (!this.textures.exists("bunker")) {
      const b = this.make.graphics({ x: 0, y: 0 }, false);
      b.fillStyle(0x3a3832, 1);
      b.fillRoundedRect(0, 8, 56, 40, 4);
      b.fillStyle(0x1a1a16, 1);
      b.fillRect(18, 24, 20, 24);
      b.fillStyle(0x9aad3a, 1);
      b.fillCircle(28, 18, 4);
      b.generateTexture("bunker", 56, 56);
      b.destroy();
    }
  }

  private createHud(): void {
    const pad = 16;
    this.add
      .rectangle(pad + 100, pad + 12, 204, 16, 0x4a4740)
      .setScrollFactor(0)
      .setDepth(30)
      .setOrigin(0.5);

    this.radiationBar = this.add
      .rectangle(pad + 2, pad + 12, 200, 12, 0x8b3a2f)
      .setScrollFactor(0)
      .setDepth(31)
      .setOrigin(0, 0.5);

    this.add
      .text(pad, pad + 28, "RADIATION", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "14px",
        color: "#a39e90",
      })
      .setScrollFactor(0)
      .setDepth(31);

    this.supplyText = this.add
      .text(pad, pad + 50, `Supplies 0/${SUPPLIES_NEEDED}`, {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "18px",
        color: "#c8c4b8",
      })
      .setScrollFactor(0)
      .setDepth(31);

    this.statusText = this.add
      .text(this.scale.width / 2, 36, "Collect supplies. Avoid the green haze.", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "18px",
        color: "#c8c4b8",
        align: "center",
      })
      .setOrigin(0.5, 0)
      .setScrollFactor(0)
      .setDepth(31);

    this.backButton = this.add
      .text(this.scale.width - pad, pad, "BACK", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "22px",
        color: "#f0ebe0",
        backgroundColor: "#00000066",
        padding: { x: 14, y: 8 },
      })
      .setOrigin(1, 0)
      .setScrollFactor(0)
      .setDepth(31)
      .setInteractive({ useHandCursor: true });

    this.backButton.on("pointerdown", () => {
      this.returnToMenu();
    });
  }

  private endRun(won: boolean): void {
    this.ended = true;
    this.player.setVelocity(0, 0);
    this.statusText.setText(won ? "Bunker sealed. You endure." : "Radiation took you.");
    this.statusText.setColor(won ? "#9aad3a" : "#8b3a2f");

    this.time.delayedCall(2200, () => {
      this.returnToMenu();
    });
  }

  private returnToMenu(): void {
    if (this.leaving) {
      return;
    }
    this.leaving = true;
    this.touch.destroy();
    this.cameras.main.fadeOut(280, 26, 26, 22);
    this.cameras.main.once(
      Phaser.Cameras.Scene2D.Events.FADE_OUT_COMPLETE,
      () => {
        this.scene.start("Menu");
      },
    );
  }
}
