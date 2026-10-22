export type EnemyBehavior =
  | "passive"
  | "flee"
  | "erratic"
  | "armored"
  | "hazard"
  | "ambush"
  | "ranged"
  | "hunter";

export interface EnemyTypeDef {
  id: string;
  nameRu: string;
  nameEn: string;
  behavior: EnemyBehavior;
  mass: number;
  speed: number;
  detectRadius: number;
  damage: number;
  rewardCurrency: number;
  essenceDropChance: number;
  armored?: boolean;
  color: string;
  glow?: string;
  minStage: number; // earliest evolution stage it can appear at
}

export const ENEMY_TYPES: EnemyTypeDef[] = [
  {
    id: "small_mushroom",
    nameRu: "Маленький гриб",
    nameEn: "Small mushroom",
    behavior: "passive",
    mass: 6,
    speed: 0,
    detectRadius: 0,
    damage: 0,
    rewardCurrency: 1,
    essenceDropChance: 0.1,
    color: "#f2c2e0",
    glow: "#ffd9f0",
    minStage: 0,
  },
  {
    id: "forest_beetle",
    nameRu: "Лесной жук",
    nameEn: "Forest beetle",
    behavior: "flee",
    mass: 14,
    speed: 95,
    detectRadius: 160,
    damage: 0,
    rewardCurrency: 2,
    essenceDropChance: 0.15,
    color: "#8a5a3b",
    minStage: 0,
  },
  {
    id: "firefly",
    nameRu: "Светлячок",
    nameEn: "Firefly",
    behavior: "erratic",
    mass: 9,
    speed: 150,
    detectRadius: 120,
    damage: 0,
    rewardCurrency: 3,
    essenceDropChance: 0.3,
    color: "#fff1a6",
    glow: "#fff8cc",
    minStage: 0,
  },
  {
    id: "stone_slug",
    nameRu: "Каменный слизень",
    nameEn: "Stone slug",
    behavior: "armored",
    mass: 60,
    speed: 30,
    detectRadius: 80,
    damage: 6,
    rewardCurrency: 6,
    essenceDropChance: 0.35,
    armored: true,
    color: "#7c7c86",
    minStage: 1,
  },
  {
    id: "poison_toad",
    nameRu: "Ядовитая жаба",
    nameEn: "Poison toad",
    behavior: "hazard",
    mass: 34,
    speed: 55,
    detectRadius: 140,
    damage: 10,
    rewardCurrency: 5,
    essenceDropChance: 0.25,
    color: "#6fae4a",
    minStage: 1,
  },
  {
    id: "predator_flower",
    nameRu: "Хищный цветок",
    nameEn: "Predator flower",
    behavior: "ambush",
    mass: 45,
    speed: 0,
    detectRadius: 110,
    damage: 16,
    rewardCurrency: 7,
    essenceDropChance: 0.3,
    color: "#c23b5a",
    minStage: 2,
  },
  {
    id: "electric_beetle",
    nameRu: "Электрический жук",
    nameEn: "Electric beetle",
    behavior: "ranged",
    mass: 38,
    speed: 70,
    detectRadius: 170,
    damage: 14,
    rewardCurrency: 8,
    essenceDropChance: 0.3,
    color: "#4fd1ff",
    glow: "#b6f0ff",
    minStage: 2,
  },
  {
    id: "shadow_slime",
    nameRu: "Теневая слизь",
    nameEn: "Shadow slime",
    behavior: "hunter",
    mass: 50,
    speed: 115,
    detectRadius: 220,
    damage: 18,
    rewardCurrency: 10,
    essenceDropChance: 0.4,
    color: "#2b2140",
    glow: "#7a5cff",
    minStage: 3,
  },
];

export const ENEMY_BY_ID: Record<string, EnemyTypeDef> = Object.fromEntries(
  ENEMY_TYPES.map((e) => [e.id, e]),
);
