// Central balance table. Keeping every tunable number here makes the game
// a lot easier to rebalance without touching engine/rendering code.
export const BALANCE = {
  BASE_MASS: 10,
  BASE_RADIUS: 16,
  RADIUS_GROWTH_EXPONENT: 0.33,
  MAX_RADIUS: 150,
  // A target can be absorbed if targetMass <= playerMass * ABSORB_MASS_RATIO
  ABSORB_MASS_RATIO: 0.85,
  MOVE_BASE_SPEED: 185, // px / s at base mass
  MIN_SPEED_MULTIPLIER: 0.42,
  SPEED_MASS_HALF_LIFE: 420, // mass at which speed penalty reaches ~50%
  ACCELERATION: 1100,
  FRICTION: 7.5,
  EVOLUTION_THRESHOLDS: [35, 80, 150, 260, 420, 640, 920, 1300],
  CLASSIC_RUN_DURATION_SEC: 360,
  PRACTICE_RUN_DURATION_SEC: 180,
  BOSS_MIN_STAGE: 4,
  BOSS_SPAWN_PROGRESS: 0.55,
  ARENA_WIDTH: 3400,
  ARENA_HEIGHT: 3400,
  MAX_ENEMIES: 36,
  MAX_PELLETS: 90,
  MAX_PARTICLES: 240,
  PLAYER_BASE_HP: 100,
  HP_PER_MASS: 0.07,
  CONTACT_INVULN_SEC: 0.6,
  AUTO_ABSORB_RADIUS_BONUS: 1.35,
} as const;

export const UPGRADE_DEFS = [
  {
    key: "startMass",
    nameRu: "Стартовая масса",
    nameEn: "Starting mass",
    descRu: "Увеличивает начальную массу слизи в каждом забеге.",
    descEn: "Increases the slime's starting mass in every run.",
    maxLevel: 10,
    baseCost: 40,
    costGrowth: 1.35,
    effectPerLevel: 3,
  },
  {
    key: "moveSpeed",
    nameRu: "Скорость движения",
    nameEn: "Movement speed",
    descRu: "Повышает базовую скорость перемещения.",
    descEn: "Raises the base movement speed.",
    maxLevel: 8,
    baseCost: 55,
    costGrowth: 1.4,
    effectPerLevel: 0.025,
  },
  {
    key: "essenceChance",
    nameRu: "Шанс эссенции",
    nameEn: "Essence chance",
    descRu: "Повышает шанс выпадения эссенции с поглощённых существ.",
    descEn: "Increases the chance that absorbed creatures drop essence.",
    maxLevel: 8,
    baseCost: 50,
    costGrowth: 1.32,
    effectPerLevel: 0.03,
  },
] as const;

export type UpgradeKey = (typeof UPGRADE_DEFS)[number]["key"];

export function upgradeCost(key: UpgradeKey, currentLevel: number): number {
  const def = UPGRADE_DEFS.find((u) => u.key === key)!;
  if (currentLevel >= def.maxLevel) return Infinity;
  return Math.round(def.baseCost * Math.pow(def.costGrowth, currentLevel));
}

export const MUTATION_UNLOCK_COST: Record<string, number> = {
  electric: 180,
  freeze: 220,
  camouflage: 160,
  vacuum: 260,
};

export const DEFAULT_UNLOCKED_MUTATIONS = [
  "magnet",
  "haste",
  "spikes",
  "poison_trail",
  "split",
  "shield",
  "regen",
  "dash",
];
