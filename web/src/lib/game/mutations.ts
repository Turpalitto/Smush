import { RNG, pickWeighted } from "./rng";
import canonicalSynergies from "../../../../resources/data/synergies.json";

// Keep existing web save IDs while using the Android catalog for combo recipes.
export const GODOT_TO_WEB_MUTATION: Record<string, string> = {
  speed_boost: "haste", regeneration: "regen", ranged_absorb: "vacuum",
  electro_discharge: "electric", mimicry: "camouflage",
};

function comboRequirements(id: string): [string, string] {
  const canonicalId = id === "storm_emp" ? "em_storm" : id;
  const recipe = canonicalSynergies.synergies.find((s) => s.id === canonicalId);
  if (!recipe || recipe.required_mutations.length !== 2) {
    throw new Error(`Missing two-mutation synergy: ${canonicalId}`);
  }
  return recipe.required_mutations.map((id) => GODOT_TO_WEB_MUTATION[id] ?? id) as [string, string];
}

export type Rarity = "common" | "rare" | "epic";

export interface MutationDef {
  id: string;
  nameRu: string;
  nameEn: string;
  descRu: string;
  descEn: string;
  rarity: Rarity;
  icon: string;
  maxLevel: number;
  // Free-form balance params consumed by the game engine.
  params: Record<string, number>;
  visualTag: string;
}

export const MUTATIONS: MutationDef[] = [
  {
    id: "magnet",
    nameRu: "Магнит",
    nameEn: "Magnet",
    descRu: "Притягивает мелкие объекты и эссенцию в радиусе действия.",
    descEn: "Pulls small objects and essence within range.",
    rarity: "common",
    icon: "🧲",
    maxLevel: 3,
    params: { radius: 90, radiusPerLevel: 35, pullForce: 260 },
    visualTag: "magnet_ring",
  },
  {
    id: "haste",
    nameRu: "Ускорение",
    nameEn: "Haste",
    descRu: "Увеличивает скорость передвижения слизи.",
    descEn: "Increases the slime's movement speed.",
    rarity: "common",
    icon: "👟",
    maxLevel: 3,
    params: { speedMult: 0.16, speedMultPerLevel: 0.08 },
    visualTag: "speed_trail",
  },
  {
    id: "spikes",
    nameRu: "Шипы",
    nameEn: "Spikes",
    descRu: "Наносят урон при контакте и помогают пробивать броню.",
    descEn: "Deal contact damage and help crack armored enemies.",
    rarity: "common",
    icon: "🦔",
    maxLevel: 3,
    params: { contactDamage: 10, contactDamagePerLevel: 6 },
    visualTag: "body_spikes",
  },
  {
    id: "poison_trail",
    nameRu: "Ядовитый след",
    nameEn: "Poison trail",
    descRu: "Оставляет за слизью ядовитый след, повреждающий преследователей.",
    descEn: "Leaves a toxic trail behind the slime, hurting pursuers.",
    rarity: "rare",
    icon: "☠️",
    maxLevel: 2,
    params: { dps: 8, dpsPerLevel: 6, tickRadius: 40 },
    visualTag: "poison_puddles",
  },
  {
    id: "split",
    nameRu: "Разделение",
    nameEn: "Split",
    descRu: "Создаёт временного двойника, который помогает поглощать цели.",
    descEn: "Spawns a temporary clone that helps absorb targets.",
    rarity: "epic",
    icon: "🫧",
    maxLevel: 1,
    params: { duration: 12, massShare: 0.35, cooldown: 25 },
    visualTag: "clone",
  },
  {
    id: "shield",
    nameRu: "Щит",
    nameEn: "Shield",
    descRu: "Блокирует одну входящую атаку, затем перезаряжается.",
    descEn: "Blocks one incoming hit, then recharges.",
    rarity: "rare",
    icon: "🛡️",
    maxLevel: 2,
    params: { cooldown: 20, cooldownPerLevel: -5 },
    visualTag: "shield_ring",
  },
  {
    id: "regen",
    nameRu: "Регенерация",
    nameEn: "Regeneration",
    descRu: "Постепенно восстанавливает здоровье слизи.",
    descEn: "Gradually restores the slime's health.",
    rarity: "common",
    icon: "💚",
    maxLevel: 3,
    params: { hpPerSec: 1.2, hpPerSecPerLevel: 0.8 },
    visualTag: "heal_glow",
  },
  {
    id: "dash",
    nameRu: "Рывок",
    nameEn: "Dash",
    descRu: "Позволяет совершить быстрый рывок в сторону движения.",
    descEn: "Lets the slime dash quickly in the movement direction.",
    rarity: "common",
    icon: "💨",
    maxLevel: 2,
    params: { cooldown: 4.5, cooldownPerLevel: -1, power: 620 },
    visualTag: "dash_streak",
  },
  {
    id: "vacuum",
    nameRu: "Поглощение на расстоянии",
    nameEn: "Long-range absorb",
    descRu: "Втягивает ослабленные и мелкие цели издалека.",
    descEn: "Vacuums in weak and small targets from a distance.",
    rarity: "epic",
    icon: "🌀",
    maxLevel: 2,
    params: { radius: 140, radiusPerLevel: 40 },
    visualTag: "vacuum_swirl",
    // locked behind meta-progression unlock by default (see constants.ts)
  },
  {
    id: "electric",
    nameRu: "Электроразряд",
    nameEn: "Electric discharge",
    descRu: "Периодически поражает ближайших врагов электрическим разрядом.",
    descEn: "Periodically zaps nearby enemies with an electric discharge.",
    rarity: "rare",
    icon: "⚡",
    maxLevel: 2,
    params: { interval: 3.5, intervalPerLevel: -0.6, radius: 160, damage: 18 },
    visualTag: "spark_aura",
  },
  {
    id: "freeze",
    nameRu: "Заморозка",
    nameEn: "Freeze",
    descRu: "Временно замедляет цели поблизости.",
    descEn: "Temporarily slows nearby targets.",
    rarity: "rare",
    icon: "❄️",
    maxLevel: 2,
    params: { radius: 130, slowFactor: 0.45, interval: 4 },
    visualTag: "frost_aura",
  },
  {
    id: "camouflage",
    nameRu: "Мимикрия",
    nameEn: "Camouflage",
    descRu: "Снижает радиус обнаружения слизи враждебными существами.",
    descEn: "Reduces the detection radius enemies use to spot the slime.",
    rarity: "epic",
    icon: "🕶️",
    maxLevel: 1,
    params: { detectionMult: 0.55 },
    visualTag: "camo_shimmer",
  },
];

export const MUTATION_BY_ID: Record<string, MutationDef> = Object.fromEntries(
  MUTATIONS.map((m) => [m.id, m]),
);

export interface ComboDef {
  id: string;
  requires: [string, string];
  nameRu: string;
  nameEn: string;
  descRu: string;
  descEn: string;
  icon: string;
}

export const COMBOS: ComboDef[] = [
  {
    id: "storm_emp",
    requires: comboRequirements("storm_emp"),
    nameRu: "Электромагнитная буря",
    nameEn: "Electromagnetic storm",
    descRu: "Магнит стягивает врагов, а разряд поражает их группой.",
    descEn: "Magnet pulls enemies together, then the discharge hits them all.",
    icon: "🌩️",
  },
  {
    id: "toxic_clones",
    requires: comboRequirements("toxic_clones"),
    nameRu: "Токсичные двойники",
    nameEn: "Toxic clones",
    descRu: "Двойники тоже оставляют ядовитый след.",
    descEn: "Clones also leave behind a toxic trail.",
    icon: "🧪",
  },
  {
    id: "piercing_strike",
    requires: comboRequirements("piercing_strike"),
    nameRu: "Пробивающий удар",
    nameEn: "Piercing strike",
    descRu: "Рывок наносит урон шипами всем на пути.",
    descEn: "Dashing deals spike damage to everything in the path.",
    icon: "🗡️",
  },
  {
    id: "ice_armor",
    requires: comboRequirements("ice_armor"),
    nameRu: "Ледяная броня",
    nameEn: "Ice armor",
    descRu: "Щит замораживает атакующего при блокировании удара.",
    descEn: "The shield freezes the attacker when it blocks a hit.",
    icon: "🧊",
  },
  {
    id: "bio_vampirism",
    requires: comboRequirements("bio_vampirism"),
    nameRu: "Биологический вампиризм",
    nameEn: "Biological vampirism",
    descRu: "Поглощение на расстоянии дополнительно восстанавливает здоровье.",
    descEn: "Long-range absorbs also heal the slime.",
    icon: "🩸",
  },
];

const RARITY_WEIGHT: Record<Rarity, number> = { common: 60, rare: 30, epic: 10 };

/**
 * Rolls `count` distinct mutation choices from the unlocked pool, excluding
 * mutations already at max level, weighted by rarity.
 */
export function rollMutationChoices(
  rng: RNG,
  unlockedPool: string[],
  ownedLevels: Record<string, number>,
  count = 3,
): MutationDef[] {
  const candidates = MUTATIONS.filter((m) => {
    if (!unlockedPool.includes(m.id)) return false;
    const owned = ownedLevels[m.id] ?? 0;
    return owned < m.maxLevel;
  });

  const pool = [...candidates];
  const result: MutationDef[] = [];
  const pickCount = Math.min(count, pool.length);

  for (let i = 0; i < pickCount; i++) {
    const weighted = pool.map((item) => ({ item, weight: RARITY_WEIGHT[item.rarity] }));
    const picked = pickWeighted(rng, weighted);
    result.push(picked);
    pool.splice(pool.indexOf(picked), 1);
  }

  return result;
}

/** Returns combo definitions whose both mutations are owned. */
export function detectActiveCombos(ownedIds: Iterable<string>): ComboDef[] {
  const owned = new Set(ownedIds);
  return COMBOS.filter((c) => c.requires.every((id) => owned.has(id)));
}
