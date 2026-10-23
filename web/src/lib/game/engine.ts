"use client";

import { BALANCE } from "./constants";
import { massToRadius, speedMultiplierForMass, maxHpForMass, canAbsorb, evolutionStageForMass } from "./growth";
import { MUTATIONS, MUTATION_BY_ID, rollMutationChoices, detectActiveCombos, ComboDef, MutationDef } from "./mutations";
import { ENEMY_TYPES, ENEMY_BY_ID, EnemyTypeDef } from "./enemies";
import { BOSS_DEF, bossPhaseForHp, BossPhaseDef } from "./boss";
import { RNG, mulberry32 } from "./rng";

export type GameMode = "classic" | "practice";

export interface EngineConfig {
  mode: GameMode;
  seed: number;
  startMassBonus: number;
  speedMultBonus: number;
  essenceChanceBonus: number;
  unlockedMutations: string[];
  autoAbsorb: boolean;
}

interface Vec2 {
  x: number;
  y: number;
}

interface Particle {
  x: number; y: number; vx: number; vy: number; life: number; maxLife: number; color: string; size: number;
}

interface Pellet {
  id: number; x: number; y: number; mass: number; kind: "essence" | "nutrient";
}

interface Enemy {
  id: number;
  type: EnemyTypeDef;
  x: number; y: number; vx: number; vy: number;
  mass: number;
  hp: number;
  maxHp: number;
  state: string;
  timer: number;
  alive: boolean;
  flashTimer: number;
}

interface HazardZone {
  x: number; y: number; radius: number; ttl: number; dps: number; color: string;
}

interface Decoration {
  x: number; y: number; r: number; kind: "mushroom" | "crystal" | "rock" | "flower"; hue: number;
}

interface BossState {
  active: boolean;
  x: number; y: number; vx: number; vy: number;
  hp: number; maxHp: number;
  phase: BossPhaseDef;
  slamTimer: number;
  addsTimer: number;
  telegraph: { active: boolean; x: number; y: number; radius: number; timer: number; duration: number } | null;
  introTimer: number;
  defeated: boolean;
  flashTimer: number;
}

export interface MutationInstance {
  id: string;
  level: number;
}

export interface Snapshot {
  running: boolean;
  gameOver: "none" | "victory" | "defeat";
  mass: number;
  hp: number;
  maxHp: number;
  timeLeft: number;
  elapsed: number;
  evolutionStage: number;
  evolutionProgress: number; // 0..1 toward next threshold
  mutations: MutationInstance[];
  combos: string[];
  bossActive: boolean;
  bossHpFraction: number;
  bossPhaseIndex: number;
  bossNameRu: string;
  pendingMutationChoice: MutationDef[] | null;
  dashReady: boolean;
  shieldCharges: number;
  reviveAvailable: boolean;
  encounteredCreatures: Set<string>;
  bossEncountered: boolean;
}

export interface EngineCallbacks {
  onMutationChoice?: (choices: MutationDef[]) => void;
  onComboUnlocked?: (combo: ComboDef) => void;
  onGameOver?: (result: "victory" | "defeat", summary: RunResultSummary) => void;
  onPlayerDowned?: () => void; // hp hit 0, offer revive before finalizing defeat
  onBossEncountered?: () => void;
  onBossDefeated?: () => void;
  onAbsorb?: (kind: "pellet" | "enemy" | "boss") => void;
  onDamaged?: () => void;
  onEvolve?: (stage: number) => void;
  onCreatureDiscovered?: (id: string) => void;
}

export interface RunResultSummary {
  massReached: number;
  durationSec: number;
  bossDefeated: boolean;
  mutationsChosen: string[];
}

let idCounter = 1;
function nextId() {
  return idCounter++;
}

interface PlayerState {
  x: number;
  y: number;
  vx: number;
  vy: number;
  mass: number;
  hp: number;
  facing: number;
  squash: number;
  invuln: number;
  dashCooldown: number;
  shieldCooldown: number;
  shieldCharges: number;
  regenAccum: number;
  electricTimer: number;
  freezeTimer: number;
  poisonTickTimer: number;
  cloneTimer: number;
  cloneCooldown: number;
  clone: { x: number; y: number; vx: number; vy: number; ttl: number } | null;
}

export class SlimeRushEngine {
  private ctx: CanvasRenderingContext2D;
  private canvas: HTMLCanvasElement;
  private cfg: EngineConfig;
  private cb: EngineCallbacks;
  private rng: RNG;

  private running = false;
  private paused = false;
  private gameOver: "none" | "victory" | "defeat" = "none";
  private awaitingMutationChoice = false;
  private reviveUsed = false;
  private reviveOffered = false;

  private elapsed = 0;
  private runDuration: number;

  private player: PlayerState = {
    x: BALANCE.ARENA_WIDTH / 2,
    y: BALANCE.ARENA_HEIGHT / 2,
    vx: 0,
    vy: 0,
    mass: BALANCE.BASE_MASS,
    hp: BALANCE.PLAYER_BASE_HP,
    facing: 0,
    squash: 0,
    invuln: 0,
    dashCooldown: 0,
    shieldCooldown: 0,
    shieldCharges: 0,
    regenAccum: 0,
    electricTimer: 0,
    freezeTimer: 0,
    poisonTickTimer: 0,
    cloneTimer: 0,
    cloneCooldown: 0,
    clone: null as { x: number; y: number; vx: number; vy: number; ttl: number } | null,
  };

  private input: Vec2 = { x: 0, y: 0 };
  private dashRequested = false;

  private mutations = new Map<string, number>();
  private activeCombos = new Set<string>();
  private mutationsChosenOrder: string[] = [];
  private nextEvolutionIndex = 0;

  private pellets: Pellet[] = [];
  private enemies: Enemy[] = [];
  private particles: Particle[] = [];
  private hazards: HazardZone[] = [];
  private decorations: Decoration[] = [];
  private trail: { x: number; y: number; life: number }[] = [];

  private boss: BossState | null = null;
  private bossSpawned = false;
  private bossEncounteredFired = false;

  private camera = { x: 0, y: 0 };
  private rafHandle: number | null = null;
  private lastTime = 0;

  private encounteredCreatures = new Set<string>();

  constructor(canvas: HTMLCanvasElement, cfg: EngineConfig, cb: EngineCallbacks = {}) {
    this.canvas = canvas;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("2D canvas context unavailable");
    this.ctx = ctx;
    this.cfg = cfg;
    this.cb = cb;
    this.rng = mulberry32(cfg.seed);
    this.runDuration = cfg.mode === "classic" ? BALANCE.CLASSIC_RUN_DURATION_SEC : BALANCE.PRACTICE_RUN_DURATION_SEC;
    this.player.mass = BALANCE.BASE_MASS + cfg.startMassBonus;
    this.player.hp = maxHpForMass(this.player.mass);
    this.generateWorld();
  }

  // ---------- public API ----------

  setInputVector(x: number, y: number) {
    const len = Math.hypot(x, y);
    if (len > 1) {
      x /= len;
      y /= len;
    }
    this.input.x = x;
    this.input.y = y;
  }

  requestDash() {
    this.dashRequested = true;
  }

  start() {
    this.running = true;
    this.lastTime = performance.now();
    const loop = (t: number) => {
      const dt = Math.min(0.05, (t - this.lastTime) / 1000);
      this.lastTime = t;
      if (this.running && !this.paused && this.gameOver === "none" && !this.awaitingMutationChoice) {
        this.update(dt);
      }
      this.render();
      this.rafHandle = requestAnimationFrame(loop);
    };
    this.rafHandle = requestAnimationFrame(loop);
  }

  stop() {
    this.running = false;
    if (this.rafHandle) cancelAnimationFrame(this.rafHandle);
  }

  setPaused(p: boolean) {
    this.paused = p;
  }

  chooseMutation(id: string) {
    const current = this.mutations.get(id) ?? 0;
    this.mutations.set(id, current + 1);
    this.mutationsChosenOrder.push(id);
    const combosNow = detectActiveCombos(this.mutations.keys());
    for (const combo of combosNow) {
      if (!this.activeCombos.has(combo.id)) {
        this.activeCombos.add(combo.id);
        this.cb.onComboUnlocked?.(combo);
      }
    }
    if (id === "shield") {
      this.player.shieldCharges = this.mutations.get("shield") ?? 1;
    }
    this.awaitingMutationChoice = false;
  }

  /** Called after a successfully-completed rewarded ad for the revive slot. */
  reviveWithAd() {
    if (this.reviveUsed) return false;
    this.reviveUsed = true;
    this.player.hp = Math.round(maxHpForMass(this.player.mass) * 0.5);
    this.player.invuln = 2;
    this.gameOver = "none";
    return true;
  }

  finalizeDefeat() {
    this.gameOver = "defeat";
    this.cb.onGameOver?.("defeat", this.summary());
  }

  abandon() {
    this.running = false;
  }

  getSnapshot(): Snapshot {
    const thresholds = BALANCE.EVOLUTION_THRESHOLDS;
    const stage = evolutionStageForMass(this.player.mass, thresholds);
    const prevThreshold = stage === 0 ? 0 : thresholds[stage - 1];
    const nextThreshold = thresholds[stage] ?? thresholds[thresholds.length - 1] * 1.4;
    const progress = Math.min(
      1,
      (this.player.mass - prevThreshold) / Math.max(1, nextThreshold - prevThreshold),
    );

    return {
      running: this.running,
      gameOver: this.gameOver,
      mass: Math.round(this.player.mass),
      hp: Math.max(0, Math.round(this.player.hp)),
      maxHp: maxHpForMass(this.player.mass),
      timeLeft: Math.max(0, Math.round(this.runDuration - this.elapsed)),
      elapsed: Math.round(this.elapsed),
      evolutionStage: stage,
      evolutionProgress: progress,
      mutations: Array.from(this.mutations.entries()).map(([id, level]) => ({ id, level })),
      combos: Array.from(this.activeCombos),
      bossActive: !!this.boss?.active,
      bossHpFraction: this.boss ? this.boss.hp / this.boss.maxHp : 1,
      bossPhaseIndex: this.boss?.phase.index ?? 0,
      bossNameRu: BOSS_DEF.nameRu,
      pendingMutationChoice: null,
      dashReady: this.player.dashCooldown <= 0,
      shieldCharges: this.player.shieldCharges,
      reviveAvailable: !this.reviveUsed,
      encounteredCreatures: this.encounteredCreatures,
      bossEncountered: this.bossEncounteredFired,
    };
  }

  private summary(): RunResultSummary {
    return {
      massReached: Math.round(this.player.mass),
      durationSec: Math.round(this.elapsed),
      bossDefeated: !!this.boss?.defeated,
      mutationsChosen: this.mutationsChosenOrder,
    };
  }

  // ---------- world generation ----------

  private generateWorld() {
    const w = BALANCE.ARENA_WIDTH;
    const h = BALANCE.ARENA_HEIGHT;
    for (let i = 0; i < 140; i++) {
      const kinds: Decoration["kind"][] = ["mushroom", "crystal", "rock", "flower"];
      this.decorations.push({
        x: this.rng() * w,
        y: this.rng() * h,
        r: 10 + this.rng() * 26,
        kind: kinds[Math.floor(this.rng() * kinds.length)],
        hue: this.rng() * 360,
      });
    }
    for (let i = 0; i < BALANCE.MAX_PELLETS; i++) {
      this.spawnPellet();
    }
    for (let i = 0; i < 16; i++) {
      this.spawnEnemy(0);
    }
  }

  private randomArenaPoint(minDistFromPlayer = 300): Vec2 {
    for (let attempt = 0; attempt < 20; attempt++) {
      const x = this.rng() * BALANCE.ARENA_WIDTH;
      const y = this.rng() * BALANCE.ARENA_HEIGHT;
      if (Math.hypot(x - this.player.x, y - this.player.y) >= minDistFromPlayer) return { x, y };
    }
    return { x: this.rng() * BALANCE.ARENA_WIDTH, y: this.rng() * BALANCE.ARENA_HEIGHT };
  }

  private spawnPellet() {
    if (this.pellets.length >= BALANCE.MAX_PELLETS) return;
    const p = this.randomArenaPoint(80);
    this.pellets.push({
      id: nextId(),
      x: p.x,
      y: p.y,
      mass: 2 + this.rng() * 4,
      kind: this.rng() < 0.25 ? "essence" : "nutrient",
    });
  }

  private spawnEnemy(stage: number) {
    if (this.enemies.filter((e) => e.alive).length >= BALANCE.MAX_ENEMIES) return;
    const candidates = ENEMY_TYPES.filter((e) => e.minStage <= stage);
    const type = candidates[Math.floor(this.rng() * candidates.length)];
    const p = this.randomArenaPoint(350);
    this.enemies.push({
      id: nextId(),
      type,
      x: p.x,
      y: p.y,
      vx: 0,
      vy: 0,
      mass: type.mass,
      hp: 20 + type.mass * 0.8,
      maxHp: 20 + type.mass * 0.8,
      state: "idle",
      timer: this.rng() * 2,
      alive: true,
      flashTimer: 0,
    });
  }

  // ---------- update loop ----------

  private update(dt: number) {
    this.elapsed += dt;

    this.updatePlayerMovement(dt);
    this.updateMutationPassives(dt);
    this.updateTrail(dt);
    this.updateClone(dt);
    this.updatePellets();
    this.updateEnemies(dt);
    this.updateHazards(dt);
    this.updateParticles(dt);
    this.updateBoss(dt);
    this.checkEvolution();
    this.checkTimeUp();

    if (this.player.hp <= 0 && this.gameOver === "none" && !this.reviveOffered) {
      this.reviveOffered = true;
      this.cb.onPlayerDowned?.();
    } else if (this.player.hp <= 0 && this.reviveUsed && this.gameOver === "none") {
      this.finalizeDefeat();
    }
  }

  private updatePlayerMovement(dt: number) {
    const mult = Math.max(
      BALANCE.MIN_SPEED_MULTIPLIER,
      speedMultiplierForMass(this.player.mass) + this.getMutationSpeedBonus() + this.cfg.speedMultBonus,
    );
    const baseSpeed = BALANCE.MOVE_BASE_SPEED * mult;

    const targetVx = this.input.x * baseSpeed;
    const targetVy = this.input.y * baseSpeed;

    this.player.vx += (targetVx - this.player.vx) * Math.min(1, dt * BALANCE.FRICTION);
    this.player.vy += (targetVy - this.player.vy) * Math.min(1, dt * BALANCE.FRICTION);

    if (this.player.dashCooldown > 0) this.player.dashCooldown -= dt;
    if (this.dashRequested && this.mutations.has("dash") && this.player.dashCooldown <= 0) {
      const dirLen = Math.hypot(this.input.x, this.input.y) || 1;
      const dashLevel = this.mutations.get("dash") ?? 1;
      const power = (MUTATION_BY_ID.dash.params.power + (dashLevel - 1) * 150);
      const dirX = dirLen > 0.01 ? this.input.x / dirLen : Math.cos(this.player.facing);
      const dirY = dirLen > 0.01 ? this.input.y / dirLen : Math.sin(this.player.facing);
      this.player.vx += dirX * power;
      this.player.vy += dirY * power;
      const cooldownBase = MUTATION_BY_ID.dash.params.cooldown + (dashLevel - 1) * MUTATION_BY_ID.dash.params.cooldownPerLevel;
      this.player.dashCooldown = Math.max(1.5, cooldownBase);
      this.player.squash = 1;
      if (this.mutations.has("spikes")) {
        this.applyPiercingDash();
      }
    }
    this.dashRequested = false;

    this.player.x = clamp(this.player.x + this.player.vx * dt, 20, BALANCE.ARENA_WIDTH - 20);
    this.player.y = clamp(this.player.y + this.player.vy * dt, 20, BALANCE.ARENA_HEIGHT - 20);

    const speed = Math.hypot(this.player.vx, this.player.vy);
    if (speed > 10) this.player.facing = Math.atan2(this.player.vy, this.player.vx);
    this.player.squash = Math.max(0, this.player.squash - dt * 2.5);

    if (this.player.invuln > 0) this.player.invuln -= dt;
    if (this.player.shieldCooldown > 0) this.player.shieldCooldown -= dt;
    if (this.mutations.has("shield") && this.player.shieldCooldown <= 0 && this.player.shieldCharges <= 0) {
      this.player.shieldCharges = 1;
    }
  }

  private applyPiercingDash() {
    const radius = massToRadius(this.player.mass) + 30;
    for (const e of this.enemies) {
      if (!e.alive) continue;
      if (dist(this.player, e) < radius) {
        this.damageEnemy(e, 40, "#ff8c42");
      }
    }
  }

  private getMutationSpeedBonus(): number {
    const level = this.mutations.get("haste");
    if (!level) return 0;
    const def = MUTATION_BY_ID.haste;
    return def.params.speedMult + (level - 1) * def.params.speedMultPerLevel;
  }

  private updateMutationPassives(dt: number) {
    const radius = massToRadius(this.player.mass);

    // regen
    const regenLevel = this.mutations.get("regen");
    if (regenLevel) {
      const def = MUTATION_BY_ID.regen;
      const hpPerSec = def.params.hpPerSec + (regenLevel - 1) * def.params.hpPerSecPerLevel;
      this.player.hp = Math.min(maxHpForMass(this.player.mass), this.player.hp + hpPerSec * dt);
    }

    // magnet: pull pellets and weak enemies
    const magnetLevel = this.mutations.get("magnet");
    if (magnetLevel) {
      const def = MUTATION_BY_ID.magnet;
      const r = def.params.radius + (magnetLevel - 1) * def.params.radiusPerLevel;
      this.pullTargets(r, def.params.pullForce, dt, false);
    }

    // vacuum: long range pull of weak targets
    const vacuumLevel = this.mutations.get("vacuum");
    if (vacuumLevel) {
      const def = MUTATION_BY_ID.vacuum;
      const r = def.params.radius + (vacuumLevel - 1) * def.params.radiusPerLevel;
      this.pullTargets(r, 160, dt, true);
    }

    // poison trail: drop hazard periodically while moving
    if (this.mutations.has("poison_trail")) {
      this.player.poisonTickTimer -= dt;
      const moving = Math.hypot(this.player.vx, this.player.vy) > 30;
      if (this.player.poisonTickTimer <= 0 && moving) {
        const level = this.mutations.get("poison_trail")!;
        const def = MUTATION_BY_ID.poison_trail;
        this.hazards.push({
          x: this.player.x,
          y: this.player.y,
          radius: def.params.tickRadius,
          ttl: 4,
          dps: def.params.dps + (level - 1) * def.params.dpsPerLevel,
          color: "#7CFC6B",
        });
        this.player.poisonTickTimer = 0.5;
        if (this.player.clone && this.activeCombos.has("toxic_clones")) {
          this.hazards.push({
            x: this.player.clone.x,
            y: this.player.clone.y,
            radius: def.params.tickRadius,
            ttl: 4,
            dps: def.params.dps,
            color: "#9bffa0",
          });
        }
      }
    }

    // electric discharge
    if (this.mutations.has("electric")) {
      this.player.electricTimer -= dt;
      if (this.player.electricTimer <= 0) {
        const level = this.mutations.get("electric")!;
        const def = MUTATION_BY_ID.electric;
        const r = def.params.radius;
        let hitCount = 0;
        for (const e of this.enemies) {
          if (!e.alive) continue;
          if (dist(this.player, e) < r) {
            this.damageEnemy(e, def.params.damage, "#9fe8ff");
            hitCount++;
          }
        }
        if (this.boss?.active && dist(this.player, this.boss) < r) {
          this.damageBoss(def.params.damage * 1.2);
        }
        this.spawnBurst(this.player.x, this.player.y, "#9fe8ff", 14);
        this.player.electricTimer = def.params.interval + (level - 1) * def.params.intervalPerLevel;
      }
    }

    // freeze aura
    if (this.mutations.has("freeze")) {
      const def = MUTATION_BY_ID.freeze;
      for (const e of this.enemies) {
        if (!e.alive) continue;
        if (dist(this.player, e) < def.params.radius) {
          e.vx *= 1 - def.params.slowFactor * dt * 2;
          e.vy *= 1 - def.params.slowFactor * dt * 2;
        }
      }
    }

    // split: periodically spawn a clone
    if (this.mutations.has("split")) {
      this.player.cloneCooldown -= dt;
      if (!this.player.clone && this.player.cloneCooldown <= 0) {
        const def = MUTATION_BY_ID.split;
        this.player.clone = {
          x: this.player.x + (this.rng() - 0.5) * 60,
          y: this.player.y + (this.rng() - 0.5) * 60,
          vx: 0,
          vy: 0,
          ttl: def.params.duration,
        };
        this.player.cloneCooldown = def.params.cooldown;
      }
    }

    void radius;
  }

  private pullTargets(radius: number, force: number, dt: number, weakOnly: boolean) {
    for (const p of this.pellets) {
      const d = dist(this.player, p);
      if (d < radius && d > 1) {
        const pull = force * dt;
        p.x += ((this.player.x - p.x) / d) * pull;
        p.y += ((this.player.y - p.y) / d) * pull;
      }
    }
    if (!weakOnly) return;
    for (const e of this.enemies) {
      if (!e.alive) continue;
      if (e.mass > this.player.mass * 0.25) continue;
      const d = dist(this.player, e);
      if (d < radius && d > 1) {
        const pull = force * 0.6 * dt;
        e.x += ((this.player.x - e.x) / d) * pull;
        e.y += ((this.player.y - e.y) / d) * pull;
      }
    }
  }

  private updateClone(dt: number) {
    const clone = this.player.clone;
    if (!clone) return;
    clone.ttl -= dt;
    // simple homing-ish wander near player, absorbs nearby pellets
    const dx = this.player.x - clone.x;
    const dy = this.player.y - clone.y;
    const d = Math.hypot(dx, dy) || 1;
    const desired = 70;
    const steerX = (dx / d) * (d > desired ? 1 : -0.3);
    const steerY = (dy / d) * (d > desired ? 1 : -0.3);
    clone.vx += steerX * 400 * dt;
    clone.vy += steerY * 400 * dt;
    clone.vx *= 0.9;
    clone.vy *= 0.9;
    clone.x += clone.vx * dt;
    clone.y += clone.vy * dt;

    const cloneRadius = massToRadius(this.player.mass * (MUTATION_BY_ID.split.params.massShare)) * 0.8;
    for (const p of this.pellets) {
      if (dist(clone, p) < cloneRadius) {
        this.player.mass += p.mass * 0.5;
        p.x = -9999;
      }
    }
    this.pellets = this.pellets.filter((p) => p.x > -1000);

    if (clone.ttl <= 0) this.player.clone = null;
  }

  private updateTrail(dt: number) {
    this.trail.push({ x: this.player.x, y: this.player.y, life: 0.5 });
    for (const t of this.trail) t.life -= dt;
    this.trail = this.trail.filter((t) => t.life > 0).slice(-24);
  }

  private updatePellets() {
    const radius = massToRadius(this.player.mass);
    const absorbRadius = radius * (this.cfg.autoAbsorb ? BALANCE.AUTO_ABSORB_RADIUS_BONUS : 1.05);
    for (const p of this.pellets) {
      if (dist(this.player, p) < absorbRadius) {
        this.player.mass += p.mass;
        if (p.kind === "essence") this.spawnBurst(p.x, p.y, "#ffe66d", 8);
        else this.spawnBurst(p.x, p.y, "#8be38b", 6);
        this.cb.onAbsorb?.("pellet");
        p.x = -99999;
      }
    }
    const before = this.pellets.length;
    this.pellets = this.pellets.filter((p) => p.x > -10000);
    const removed = before - this.pellets.length;
    for (let i = 0; i < removed; i++) this.spawnPellet();
  }

  private updateEnemies(dt: number) {
    const radius = massToRadius(this.player.mass);
    const absorbRadius = radius * (this.cfg.autoAbsorb ? BALANCE.AUTO_ABSORB_RADIUS_BONUS : 1.05);
    const camoMult = this.mutations.has("camouflage") ? MUTATION_BY_ID.camouflage.params.detectionMult : 1;

    for (const e of this.enemies) {
      if (!e.alive) continue;
      e.timer -= dt;
      e.flashTimer = Math.max(0, e.flashTimer - dt);
      const d = dist(this.player, e);
      const effectiveDetect = e.type.detectRadius * camoMult;

      switch (e.type.behavior) {
        case "passive":
          break;
        case "flee": {
          if (d < effectiveDetect && this.player.mass > e.mass) {
            const dx = e.x - this.player.x;
            const dy = e.y - this.player.y;
            const len = Math.hypot(dx, dy) || 1;
            e.vx = (dx / len) * e.type.speed;
            e.vy = (dy / len) * e.type.speed;
          } else {
            e.vx *= 0.95;
            e.vy *= 0.95;
          }
          break;
        }
        case "erratic": {
          if (e.timer <= 0) {
            const angle = this.rng() * Math.PI * 2;
            e.vx = Math.cos(angle) * e.type.speed;
            e.vy = Math.sin(angle) * e.type.speed;
            e.timer = 0.4 + this.rng() * 0.6;
          }
          break;
        }
        case "armored": {
          if (e.timer <= 0) {
            const angle = this.rng() * Math.PI * 2;
            e.vx = Math.cos(angle) * e.type.speed * 0.5;
            e.vy = Math.sin(angle) * e.type.speed * 0.5;
            e.timer = 2 + this.rng() * 2;
          }
          break;
        }
        case "hazard": {
          if (e.timer <= 0) {
            const angle = this.rng() * Math.PI * 2;
            e.vx = Math.cos(angle) * e.type.speed;
            e.vy = Math.sin(angle) * e.type.speed;
            e.timer = 1.5 + this.rng();
            if (this.rng() < 0.4) {
              this.hazards.push({ x: e.x, y: e.y, radius: 50, ttl: 5, dps: 8, color: "#4caf50" });
            }
          }
          break;
        }
        case "ambush": {
          e.vx = 0;
          e.vy = 0;
          if (d < effectiveDetect * 0.6 && e.timer <= 0) {
            const dx = this.player.x - e.x;
            const dy = this.player.y - e.y;
            const len = Math.hypot(dx, dy) || 1;
            e.vx = (dx / len) * e.type.speed * 6;
            e.vy = (dy / len) * e.type.speed * 6;
            e.timer = 1.6;
          }
          break;
        }
        case "ranged": {
          if (e.timer <= 0 && d < e.type.detectRadius * camoMult) {
            this.hazards.push({ x: e.x, y: e.y, radius: 70, ttl: 0.4, dps: e.type.damage * 2, color: "#4fd1ff" });
            this.spawnBurst(e.x, e.y, "#4fd1ff", 10);
            e.timer = 2.2;
          } else if (e.timer <= 0) {
            e.timer = 0.5;
          }
          const angle = (e.id * 0.37 + this.elapsed) % (Math.PI * 2);
          e.vx = Math.cos(angle) * e.type.speed * 0.4;
          e.vy = Math.sin(angle) * e.type.speed * 0.4;
          break;
        }
        case "hunter": {
          if (d < effectiveDetect) {
            const dx = this.player.x - e.x;
            const dy = this.player.y - e.y;
            const len = Math.hypot(dx, dy) || 1;
            e.vx = (dx / len) * e.type.speed;
            e.vy = (dy / len) * e.type.speed;
          } else {
            if (e.timer <= 0) {
              const angle = this.rng() * Math.PI * 2;
              e.vx = Math.cos(angle) * e.type.speed * 0.4;
              e.vy = Math.sin(angle) * e.type.speed * 0.4;
              e.timer = 1.5;
            }
          }
          break;
        }
      }

      e.x = clamp(e.x + e.vx * dt, 10, BALANCE.ARENA_WIDTH - 10);
      e.y = clamp(e.y + e.vy * dt, 10, BALANCE.ARENA_HEIGHT - 10);

      if (!this.encounteredCreatures.has(e.type.id)) {
        if (d < 400) {
          this.encounteredCreatures.add(e.type.id);
          this.cb.onCreatureDiscovered?.(e.type.id);
        }
      }

      // contact resolution
      if (d < absorbRadius) {
        const canEat = canAbsorb(
          this.player.mass,
          { mass: e.mass, armored: e.type.armored },
          new Set(this.mutations.keys()),
        );
        if (canEat) {
          this.player.mass += e.mass;
          e.alive = false;
          this.spawnBurst(e.x, e.y, e.type.color, 16);
          this.cb.onAbsorb?.("enemy");
          if (this.rng() < 0.2 + this.cfg.essenceChanceBonus + e.type.essenceDropChance * 0.3) {
            this.pellets.push({ id: nextId(), x: e.x, y: e.y, mass: 6, kind: "essence" });
          }
        } else if (e.type.damage > 0 && this.player.invuln <= 0) {
          this.applyDamage(e.type.damage);
          const dx = this.player.x - e.x;
          const dy = this.player.y - e.y;
          const len = Math.hypot(dx, dy) || 1;
          this.player.vx += (dx / len) * 220;
          this.player.vy += (dy / len) * 220;
        }

        if (this.mutations.has("spikes") && e.alive) {
          const level = this.mutations.get("spikes")!;
          const def = MUTATION_BY_ID.spikes;
          this.damageEnemy(e, def.params.contactDamage + (level - 1) * def.params.contactDamagePerLevel, "#ff8c42");
        }
      }
    }

    this.enemies = this.enemies.filter((e) => e.alive);
    if (this.enemies.length < 14) {
      const stage = evolutionStageForMass(this.player.mass, BALANCE.EVOLUTION_THRESHOLDS);
      this.spawnEnemy(stage);
    }
  }

  private damageEnemy(e: Enemy, dmg: number, flashColor: string) {
    e.hp -= dmg;
    e.flashTimer = 0.15;
    this.spawnBurst(e.x, e.y, flashColor, 4);
    if (e.hp <= 0 && e.alive) {
      e.alive = false;
      this.player.mass += e.mass * 0.6;
      this.spawnBurst(e.x, e.y, e.type.color, 14);
      this.cb.onAbsorb?.("enemy");
    }
  }

  private applyDamage(amount: number) {
    if (this.player.shieldCharges > 0) {
      this.player.shieldCharges -= 1;
      this.spawnBurst(this.player.x, this.player.y, "#9fd4ff", 20);
      if (this.activeCombos.has("ice_armor")) {
        for (const e of this.enemies) {
          if (dist(this.player, e) < 90) {
            e.vx *= 0.2;
            e.vy *= 0.2;
          }
        }
      }
      return;
    }
    this.player.hp -= amount;
    this.player.invuln = BALANCE.CONTACT_INVULN_SEC;
    this.player.squash = 1;
    this.cb.onDamaged?.();
  }

  private updateHazards(dt: number) {
    for (const h of this.hazards) {
      h.ttl -= dt;
      if (dist(this.player, h) < h.radius && this.player.invuln <= 0) {
        this.applyDamage(h.dps * dt * 6);
      }
      for (const e of this.enemies) {
        if (!e.alive) continue;
        if (dist(e, h) < h.radius && (h.color === "#7CFC6B" || h.color === "#9bffa0")) {
          this.damageEnemy(e, h.dps * dt * 6, "#9bffa0");
        }
      }
    }
    this.hazards = this.hazards.filter((h) => h.ttl > 0);
  }

  private spawnBurst(x: number, y: number, color: string, count: number) {
    for (let i = 0; i < count; i++) {
      if (this.particles.length >= BALANCE.MAX_PARTICLES) {
        this.particles.shift();
      }
      const angle = this.rng() * Math.PI * 2;
      const speed = 40 + this.rng() * 120;
      this.particles.push({
        x,
        y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        life: 0.5 + this.rng() * 0.4,
        maxLife: 0.9,
        color,
        size: 2 + this.rng() * 3,
      });
    }
  }

  private updateParticles(dt: number) {
    for (const p of this.particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.92;
      p.vy *= 0.92;
      p.life -= dt;
    }
    this.particles = this.particles.filter((p) => p.life > 0);
  }

  private checkEvolution() {
    const thresholds = BALANCE.EVOLUTION_THRESHOLDS;
    const stage = evolutionStageForMass(this.player.mass, thresholds);
    if (stage > this.nextEvolutionIndex) {
      this.nextEvolutionIndex = stage;
      this.cb.onEvolve?.(stage);
      const owned = Object.fromEntries(this.mutations.entries());
      const choices = rollMutationChoices(this.rng, this.cfg.unlockedMutations, owned, 3);
      if (choices.length > 0) {
        this.awaitingMutationChoice = true;
        this.cb.onMutationChoice?.(choices);
      }
    }

    if (
      this.cfg.mode === "classic" &&
      !this.bossSpawned &&
      stage >= BALANCE.BOSS_MIN_STAGE &&
      this.elapsed >= this.runDuration * BALANCE.BOSS_SPAWN_PROGRESS
    ) {
      this.spawnBoss();
    }
  }

  private spawnBoss() {
    this.bossSpawned = true;
    const point = this.randomArenaPoint(500);
    this.boss = {
      active: true,
      x: point.x,
      y: point.y,
      vx: 0,
      vy: 0,
      hp: BOSS_DEF.maxHp,
      maxHp: BOSS_DEF.maxHp,
      phase: BOSS_DEF.phases[0],
      slamTimer: BOSS_DEF.phases[0].slamCooldown,
      addsTimer: 5,
      telegraph: null,
      introTimer: 2,
      defeated: false,
      flashTimer: 0,
    };
  }

  private updateBoss(dt: number) {
    const boss = this.boss;
    if (!boss || !boss.active) return;

    if (!this.bossEncounteredFired) {
      this.bossEncounteredFired = true;
      this.cb.onBossEncountered?.();
    }

    boss.flashTimer = Math.max(0, boss.flashTimer - dt);
    if (boss.introTimer > 0) {
      boss.introTimer -= dt;
      return;
    }

    boss.phase = bossPhaseForHp(boss.hp / boss.maxHp);

    const dx = this.player.x - boss.x;
    const dy = this.player.y - boss.y;
    const len = Math.hypot(dx, dy) || 1;
    boss.vx = (dx / len) * boss.phase.moveSpeed;
    boss.vy = (dy / len) * boss.phase.moveSpeed;
    boss.x = clamp(boss.x + boss.vx * dt, 40, BALANCE.ARENA_WIDTH - 40);
    boss.y = clamp(boss.y + boss.vy * dt, 40, BALANCE.ARENA_HEIGHT - 40);

    // telegraph / slam attack
    if (boss.telegraph) {
      boss.telegraph.timer -= dt;
      if (boss.telegraph.timer <= 0) {
        if (dist(this.player, boss.telegraph) < boss.telegraph.radius && this.player.invuln <= 0) {
          this.applyDamage(boss.phase.slamDamage);
        }
        this.spawnBurst(boss.telegraph.x, boss.telegraph.y, "#ffb86c", 24);
        boss.telegraph = null;
        boss.slamTimer = boss.phase.slamCooldown;
      }
    } else {
      boss.slamTimer -= dt;
      if (boss.slamTimer <= 0) {
        boss.telegraph = {
          active: true,
          x: this.player.x,
          y: this.player.y,
          radius: boss.phase.slamRadius,
          timer: boss.phase.telegraphSec,
          duration: boss.phase.telegraphSec,
        };
      }
    }

    // summon adds
    if (boss.phase.summonsAdds) {
      boss.addsTimer -= dt;
      if (boss.addsTimer <= 0) {
        boss.addsTimer = boss.phase.addsCooldown ?? 7;
        for (let i = 0; i < 2; i++) {
          const angle = this.rng() * Math.PI * 2;
          const sx = boss.x + Math.cos(angle) * 120;
          const sy = boss.y + Math.sin(angle) * 120;
          this.enemies.push({
            id: nextId(),
            type: ENEMY_BY_ID.shadow_slime,
            x: clamp(sx, 20, BALANCE.ARENA_WIDTH - 20),
            y: clamp(sy, 20, BALANCE.ARENA_HEIGHT - 20),
            vx: 0,
            vy: 0,
            mass: ENEMY_BY_ID.shadow_slime.mass * 0.6,
            hp: 30,
            maxHp: 30,
            state: "idle",
            timer: 0,
            alive: true,
            flashTimer: 0,
          });
        }
      }
    }

    // contact damage / player offense against boss
    const d = dist(this.player, boss);
    const hitRadius = massToRadius(this.player.mass) + BOSS_DEF.radius * 0.6;
    if (d < hitRadius) {
      const canDamageBoss = this.mutations.has("spikes") || this.mutations.has("electric") || this.mutations.has("dash");
      if (canDamageBoss) {
        const dps = 14 + (this.mutations.get("spikes") ?? 0) * 8;
        this.damageBoss(dps * dt * 4);
      } else if (this.player.invuln <= 0) {
        this.applyDamage(BOSS_DEF.contactDamage * 0.4);
        const dirx = (this.player.x - boss.x) / (d || 1);
        const diry = (this.player.y - boss.y) / (d || 1);
        this.player.vx += dirx * 260;
        this.player.vy += diry * 260;
      }
    }
  }

  private damageBoss(amount: number) {
    const boss = this.boss;
    if (!boss || !boss.active || boss.defeated) return;
    boss.hp = Math.max(0, boss.hp - amount);
    boss.flashTimer = 0.1;
    if (boss.hp <= 0) {
      boss.defeated = true;
      boss.active = false;
      this.player.mass += BOSS_DEF.baseMass * 0.25;
      this.spawnBurst(boss.x, boss.y, "#ffd700", 60);
      this.cb.onBossDefeated?.();
      this.gameOver = "victory";
      this.cb.onGameOver?.("victory", this.summary());
    }
  }

  private checkTimeUp() {
    if (this.gameOver !== "none") return;
    if (this.cfg.mode === "practice") return;
    if (this.elapsed >= this.runDuration) {
      if (this.boss && this.boss.active && !this.boss.defeated) {
        // boss still alive at time limit: treat as defeat (ran out of time)
        this.gameOver = "defeat";
        this.cb.onGameOver?.("defeat", this.summary());
      } else {
        this.gameOver = "victory";
        this.cb.onGameOver?.("victory", this.summary());
      }
    }
  }

  // ---------- rendering ----------

  private render() {
    const ctx = this.ctx;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const cssW = this.canvas.clientWidth || 360;
    const cssH = this.canvas.clientHeight || 640;
    if (this.canvas.width !== Math.round(cssW * dpr) || this.canvas.height !== Math.round(cssH * dpr)) {
      this.canvas.width = Math.round(cssW * dpr);
      this.canvas.height = Math.round(cssH * dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssW, cssH);

    this.camera.x = this.player.x - cssW / 2;
    this.camera.y = this.player.y - cssH / 2;

    // background
    const grad = ctx.createLinearGradient(0, 0, 0, cssH);
    grad.addColorStop(0, "#0e2e1c");
    grad.addColorStop(1, "#163a24");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, cssW, cssH);

    const toScreen = (x: number, y: number): [number, number] => [x - this.camera.x, y - this.camera.y];

    // decorations
    for (const d of this.decorations) {
      const [sx, sy] = toScreen(d.x, d.y);
      if (sx < -60 || sy < -60 || sx > cssW + 60 || sy > cssH + 60) continue;
      this.drawDecoration(ctx, sx, sy, d);
    }

    // hazards
    for (const h of this.hazards) {
      const [sx, sy] = toScreen(h.x, h.y);
      ctx.globalAlpha = Math.min(0.55, h.ttl);
      ctx.fillStyle = h.color;
      ctx.beginPath();
      ctx.arc(sx, sy, h.radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }

    // trail
    for (const t of this.trail) {
      const [sx, sy] = toScreen(t.x, t.y);
      ctx.globalAlpha = Math.max(0, t.life) * 0.25;
      ctx.fillStyle = "#8ef0c4";
      ctx.beginPath();
      ctx.arc(sx, sy, massToRadius(this.player.mass) * 0.5, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }

    // pellets
    for (const p of this.pellets) {
      const [sx, sy] = toScreen(p.x, p.y);
      if (sx < -20 || sy < -20 || sx > cssW + 20 || sy > cssH + 20) continue;
      ctx.fillStyle = p.kind === "essence" ? "#ffe66d" : "#9be89b";
      ctx.beginPath();
      ctx.arc(sx, sy, 4 + p.mass * 0.4, 0, Math.PI * 2);
      ctx.fill();
    }

    // enemies
    for (const e of this.enemies) {
      const [sx, sy] = toScreen(e.x, e.y);
      if (sx < -80 || sy < -80 || sx > cssW + 80 || sy > cssH + 80) continue;
      this.drawEnemy(ctx, sx, sy, e);
    }

    // boss
    if (this.boss?.active) {
      const [sx, sy] = toScreen(this.boss.x, this.boss.y);
      this.drawBoss(ctx, sx, sy, this.boss);
      if (this.boss.telegraph) {
        const [tx, ty] = toScreen(this.boss.telegraph.x, this.boss.telegraph.y);
        const progress = 1 - this.boss.telegraph.timer / this.boss.telegraph.duration;
        ctx.strokeStyle = "rgba(255,90,90,0.9)";
        ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.arc(tx, ty, this.boss.telegraph.radius * Math.min(1, progress + 0.15), 0, Math.PI * 2);
        ctx.stroke();
        ctx.fillStyle = "rgba(255,90,90,0.18)";
        ctx.beginPath();
        ctx.arc(tx, ty, this.boss.telegraph.radius, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    // clone
    if (this.player.clone) {
      const [sx, sy] = toScreen(this.player.clone.x, this.player.clone.y);
      const r = massToRadius(this.player.mass * MUTATION_BY_ID.split.params.massShare);
      ctx.globalAlpha = 0.7;
      this.drawSlimeBody(ctx, sx, sy, r, 0, 0, "#7cf2c7");
      ctx.globalAlpha = 1;
    }

    // player
    {
      const [sx, sy] = toScreen(this.player.x, this.player.y);
      const r = massToRadius(this.player.mass);
      this.drawSlimeBody(ctx, sx, sy, r, this.player.facing, this.player.squash, "#59e3b0", true);
    }

    // particles
    for (const p of this.particles) {
      const [sx, sy] = toScreen(p.x, p.y);
      ctx.globalAlpha = Math.max(0, p.life / p.maxLife);
      ctx.fillStyle = p.color;
      ctx.beginPath();
      ctx.arc(sx, sy, p.size, 0, Math.PI * 2);
      ctx.fill();
      ctx.globalAlpha = 1;
    }
  }

  private drawDecoration(ctx: CanvasRenderingContext2D, x: number, y: number, d: Decoration) {
    ctx.save();
    if (d.kind === "mushroom") {
      ctx.fillStyle = `hsl(${d.hue}, 70%, 65%)`;
      ctx.beginPath();
      ctx.ellipse(x, y, d.r, d.r * 0.7, 0, Math.PI, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = "rgba(255,255,255,0.5)";
      ctx.beginPath();
      ctx.arc(x, y - d.r * 0.2, d.r * 0.25, 0, Math.PI * 2);
      ctx.fill();
    } else if (d.kind === "crystal") {
      ctx.fillStyle = `hsla(${200 + d.hue * 0.2}, 80%, 70%, 0.85)`;
      ctx.beginPath();
      ctx.moveTo(x, y - d.r);
      ctx.lineTo(x + d.r * 0.6, y);
      ctx.lineTo(x, y + d.r);
      ctx.lineTo(x - d.r * 0.6, y);
      ctx.closePath();
      ctx.fill();
    } else if (d.kind === "rock") {
      ctx.fillStyle = "#5b5b63";
      ctx.beginPath();
      ctx.arc(x, y, d.r * 0.8, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.fillStyle = `hsl(${d.hue}, 80%, 70%)`;
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2;
        ctx.beginPath();
        ctx.ellipse(x + Math.cos(a) * d.r * 0.4, y + Math.sin(a) * d.r * 0.4, d.r * 0.3, d.r * 0.18, a, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.fillStyle = "#ffd96b";
      ctx.beginPath();
      ctx.arc(x, y, d.r * 0.22, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  private drawEnemy(ctx: CanvasRenderingContext2D, x: number, y: number, e: Enemy) {
    const r = massToRadius(e.mass) * 0.9;
    ctx.save();
    ctx.globalAlpha = e.flashTimer > 0 ? 0.6 : 1;
    ctx.fillStyle = e.flashTimer > 0 ? "#ffffff" : e.type.color;
    if (e.type.glow) {
      ctx.shadowColor = e.type.glow;
      ctx.shadowBlur = 14;
    }
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    if (e.maxHp > 0 && e.hp < e.maxHp) {
      ctx.fillStyle = "rgba(0,0,0,0.4)";
      ctx.fillRect(x - r, y - r - 8, r * 2, 4);
      ctx.fillStyle = "#ff6b6b";
      ctx.fillRect(x - r, y - r - 8, (r * 2) * Math.max(0, e.hp / e.maxHp), 4);
    }
  }

  private drawBoss(ctx: CanvasRenderingContext2D, x: number, y: number, boss: BossState) {
    const r = BOSS_DEF.radius;
    ctx.save();
    ctx.fillStyle = boss.flashTimer > 0 ? "#ffffff" : "#3c2a52";
    ctx.shadowColor = "#a076ff";
    ctx.shadowBlur = 24;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    ctx.fillStyle = "rgba(0,0,0,0.5)";
    ctx.fillRect(x - r, y - r - 18, r * 2, 8);
    ctx.fillStyle = "#ff5a7a";
    ctx.fillRect(x - r, y - r - 18, r * 2 * (boss.hp / boss.maxHp), 8);
  }

  private drawSlimeBody(
    ctx: CanvasRenderingContext2D,
    x: number,
    y: number,
    r: number,
    facing: number,
    squash: number,
    color: string,
    isPlayer = false,
  ) {
    const stretch = 1 + squash * 0.25;
    const squeeze = 1 - squash * 0.18;
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(facing);
    ctx.scale(stretch, squeeze);

    const grad = ctx.createRadialGradient(-r * 0.3, -r * 0.3, r * 0.1, 0, 0, r);
    grad.addColorStop(0, "rgba(255,255,255,0.65)");
    grad.addColorStop(0.4, color);
    grad.addColorStop(1, "rgba(20,90,70,0.85)");
    ctx.fillStyle = grad;
    ctx.globalAlpha = 0.92;
    ctx.beginPath();
    ctx.arc(0, 0, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;

    // glowing core
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    ctx.shadowColor = "#fff6c4";
    ctx.shadowBlur = 16;
    ctx.beginPath();
    ctx.arc(r * 0.1, 0, r * 0.22, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;

    if (isPlayer) {
      // eyes
      const eyeOffsetX = r * 0.35;
      const eyeOffsetY = r * 0.28;
      for (const sign of [-1, 1]) {
        ctx.fillStyle = "#ffffff";
        ctx.beginPath();
        ctx.ellipse(eyeOffsetX, sign * eyeOffsetY, r * 0.16, r * 0.2, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = "#1a1a1a";
        ctx.beginPath();
        ctx.arc(eyeOffsetX + r * 0.05, sign * eyeOffsetY, r * 0.08, 0, Math.PI * 2);
        ctx.fill();
      }

      // mutation visuals
      this.drawMutationVisuals(ctx, r);
    }

    ctx.restore();
  }

  private drawMutationVisuals(ctx: CanvasRenderingContext2D, r: number) {
    if (this.mutations.has("spikes")) {
      ctx.fillStyle = "#ff8c42";
      const count = 8;
      for (let i = 0; i < count; i++) {
        const a = (i / count) * Math.PI * 2;
        ctx.beginPath();
        ctx.moveTo(Math.cos(a) * r, Math.sin(a) * r);
        ctx.lineTo(Math.cos(a - 0.08) * (r + 10), Math.sin(a - 0.08) * (r + 10));
        ctx.lineTo(Math.cos(a + 0.08) * (r + 10), Math.sin(a + 0.08) * (r + 10));
        ctx.closePath();
        ctx.fill();
      }
    }
    if (this.mutations.has("shield") && this.player.shieldCharges > 0) {
      ctx.strokeStyle = "rgba(159,212,255,0.9)";
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.arc(0, 0, r + 10, 0, Math.PI * 2);
      ctx.stroke();
    }
    if (this.mutations.has("magnet")) {
      ctx.strokeStyle = "rgba(255,120,200,0.5)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(0, 0, r + 6, 0, Math.PI * 2);
      ctx.stroke();
    }
    if (this.mutations.has("freeze")) {
      ctx.strokeStyle = "rgba(190,230,255,0.6)";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(0, 0, r + 14, 0, Math.PI * 2);
      ctx.stroke();
    }
    if (this.mutations.has("camouflage")) {
      ctx.globalAlpha = 0.6;
    }
  }
}

function dist(a: { x: number; y: number }, b: { x: number; y: number }) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function clamp(v: number, min: number, max: number) {
  return Math.max(min, Math.min(max, v));
}
