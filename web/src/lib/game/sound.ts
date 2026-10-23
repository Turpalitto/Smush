"use client";

// All sound effects are synthesized at runtime via the Web Audio API so the
// game ships with zero third-party audio assets (avoiding any licensing
// risk). Music is intentionally not included — see MONETIZATION.md /
// GAME_DESIGN.md: the game is fully playable with music off by default.
export type SfxName =
  | "move"
  | "absorb"
  | "absorb_big"
  | "evolve"
  | "mutation"
  | "attack"
  | "damage"
  | "victory"
  | "defeat"
  | "click"
  | "boss";

class SoundManager {
  private ctx: AudioContext | null = null;
  private sfxVolume = 0.8;
  private musicVolume = 0; // music is off by default, no track is bundled

  private ensureCtx(): AudioContext | null {
    if (typeof window === "undefined") return null;
    if (!this.ctx) {
      const Ctor = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (!Ctor) return null;
      this.ctx = new Ctor();
    }
    if (this.ctx.state === "suspended") {
      void this.ctx.resume();
    }
    return this.ctx;
  }

  setSfxVolume(v: number) {
    this.sfxVolume = Math.max(0, Math.min(1, v));
  }

  setMusicVolume(v: number) {
    this.musicVolume = Math.max(0, Math.min(1, v));
    void this.musicVolume; // reserved for a future bundled music track
  }

  play(name: SfxName) {
    const ctx = this.ensureCtx();
    if (!ctx || this.sfxVolume <= 0) return;
    const now = ctx.currentTime;

    const tone = (freq: number, duration: number, type: OscillatorType, gainScale = 1, delay = 0) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = type;
      osc.frequency.setValueAtTime(freq, now + delay);
      gain.gain.setValueAtTime(0.0001, now + delay);
      gain.gain.exponentialRampToValueAtTime(this.sfxVolume * 0.35 * gainScale, now + delay + 0.015);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + delay + duration);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now + delay);
      osc.stop(now + delay + duration + 0.02);
    };

    switch (name) {
      case "move":
        tone(220, 0.05, "sine", 0.2);
        break;
      case "absorb":
        tone(520, 0.08, "triangle");
        tone(780, 0.08, "triangle", 0.8, 0.04);
        break;
      case "absorb_big":
        tone(300, 0.1, "sawtooth");
        tone(600, 0.12, "triangle", 1, 0.05);
        tone(900, 0.14, "sine", 0.7, 0.1);
        break;
      case "evolve":
        tone(260, 0.15, "sine");
        tone(390, 0.15, "sine", 1, 0.08);
        tone(520, 0.25, "sine", 1, 0.16);
        break;
      case "mutation":
        tone(440, 0.12, "square", 0.6);
        tone(660, 0.18, "sine", 1, 0.08);
        break;
      case "attack":
        tone(140, 0.08, "sawtooth");
        break;
      case "damage":
        tone(120, 0.18, "square", 1);
        break;
      case "victory":
        tone(392, 0.16, "sine");
        tone(494, 0.16, "sine", 1, 0.14);
        tone(587, 0.16, "sine", 1, 0.28);
        tone(784, 0.3, "sine", 1, 0.42);
        break;
      case "defeat":
        tone(220, 0.3, "sawtooth");
        tone(160, 0.35, "sawtooth", 1, 0.18);
        break;
      case "click":
        tone(680, 0.05, "square", 0.5);
        break;
      case "boss":
        tone(90, 0.4, "sawtooth", 1);
        tone(70, 0.5, "sawtooth", 0.8, 0.2);
        break;
    }
  }
}

export const soundManager = new SoundManager();
