import Phaser from "phaser";

const BOSS_LINE = "You want to eat? Then get to work";

export class TutorialBossScene extends Phaser.Scene {
  private dialogueText!: Phaser.GameObjects.Text;
  private continuePrompt!: Phaser.GameObjects.Text;
  private typingComplete = false;
  private advancing = false;
  private charIndex = 0;
  private typeTimer?: Phaser.Time.TimerEvent;

  constructor() {
    super("TutorialBoss");
  }

  create(): void {
    this.typingComplete = false;
    this.advancing = false;
    this.charIndex = 0;

    const { width, height } = this.scale;

    this.add.rectangle(width / 2, height / 2, width, height, 0x0c0c0a);

    const crt = this.add.image(width / 2, height * 0.38, "boss-crt");
    const crtMaxW = width * 0.72;
    const crtMaxH = height * 0.58;
    const crtScale = Math.min(crtMaxW / crt.width, crtMaxH / crt.height);
    crt.setScale(crtScale);
    crt.setDepth(1);

    const panelW = width * 0.86;
    const panelH = 168;
    const panelX = width / 2;
    const panelY = height - panelH / 2 - 28;

    const panel = this.add.image(panelX, panelY, "dialogue-panel");
    panel.setDisplaySize(panelW, panelH);
    panel.setDepth(2);

    const textPadX = 48;
    const textPadY = 36;
    this.dialogueText = this.add
      .text(panelX - panelW / 2 + textPadX, panelY - panelH / 2 + textPadY, "", {
        fontFamily: '"Russo One", sans-serif',
        fontSize: "32px",
        color: "#f0ebe0",
        stroke: "#1a1a16",
        strokeThickness: 4,
        wordWrap: { width: panelW - textPadX * 2 - 40 },
      })
      .setOrigin(0, 0)
      .setDepth(3);

    this.continuePrompt = this.add
      .text(
        panelX + panelW / 2 - textPadX,
        panelY + panelH / 2 - 22,
        "Press any key to continue",
        {
          fontFamily: '"Russo One", sans-serif',
          fontSize: "18px",
          color: "#c8c4b8",
          stroke: "#1a1a16",
          strokeThickness: 3,
        },
      )
      .setOrigin(1, 1)
      .setDepth(3)
      .setAlpha(0);

    this.typeTimer = this.time.addEvent({
      delay: 38,
      repeat: BOSS_LINE.length - 1,
      callback: () => {
        this.charIndex += 1;
        this.dialogueText.setText(BOSS_LINE.slice(0, this.charIndex));
        if (this.charIndex >= BOSS_LINE.length) {
          this.onTypingFinished();
        }
      },
    });

    this.input.keyboard?.on("keydown", this.onAnyInput, this);
    this.input.on("pointerdown", this.onAnyInput, this);

    this.cameras.main.fadeIn(350, 12, 12, 10);
  }

  private onTypingFinished(): void {
    this.typingComplete = true;
    this.continuePrompt.setAlpha(1);
    this.tweens.add({
      targets: this.continuePrompt,
      alpha: 0.3,
      duration: 700,
      yoyo: true,
      repeat: -1,
      ease: "Sine.easeInOut",
    });
  }

  private onAnyInput(): void {
    if (this.advancing) {
      return;
    }

    if (!this.typingComplete) {
      this.typeTimer?.remove(false);
      this.charIndex = BOSS_LINE.length;
      this.dialogueText.setText(BOSS_LINE);
      this.onTypingFinished();
      return;
    }

    this.advancing = true;
    this.cameras.main.fadeOut(280, 12, 12, 10);
    this.cameras.main.once(
      Phaser.Cameras.Scene2D.Events.FADE_OUT_COMPLETE,
      () => {
        this.scene.start("TutorialMap");
      },
    );
  }

  shutdown(): void {
    this.typeTimer?.remove(false);
    this.input.keyboard?.off("keydown", this.onAnyInput, this);
    this.input.off("pointerdown", this.onAnyInput, this);
  }
}
