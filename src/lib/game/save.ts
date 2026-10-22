import { DEFAULT_UNLOCKED_MUTATIONS } from "./constants";

export interface PlayerSettings {
  joystickMode: "fixed" | "floating";
  sfxVolume: number;
  musicVolume: number;
  autoAbsorb: boolean;
  language: "ru" | "en";
}

export interface PlayerProfile {
  id: string;
  currency: number;
  totalRuns: number;
  totalWins: number;
  totalBossKills: number;
  bestMass: number;
  bestDurationSec: number;
  upgrades: Record<string, number>;
  unlockedMutations: string[];
  discoveredCreatures: string[];
  discoveredForms: number[];
  achievements: string[];
  settings: PlayerSettings;
  noAds: boolean;
  ownedCosmetics: string[];
  equippedCosmetic: string | null;
}

export function defaultSettings(): PlayerSettings {
  return {
    joystickMode: "floating",
    sfxVolume: 0.8,
    musicVolume: 0,
    autoAbsorb: true,
    language: "ru",
  };
}

export function defaultProfile(id: string): PlayerProfile {
  return {
    id,
    currency: 0,
    totalRuns: 0,
    totalWins: 0,
    totalBossKills: 0,
    bestMass: 0,
    bestDurationSec: 0,
    upgrades: {},
    unlockedMutations: [...DEFAULT_UNLOCKED_MUTATIONS],
    discoveredCreatures: [],
    discoveredForms: [],
    achievements: [],
    settings: defaultSettings(),
    noAds: false,
    ownedCosmetics: [],
    equippedCosmetic: null,
  };
}

function isStringArray(v: unknown): v is string[] {
  return Array.isArray(v) && v.every((x) => typeof x === "string");
}

function isNumberArray(v: unknown): v is number[] {
  return Array.isArray(v) && v.every((x) => typeof x === "number" && Number.isFinite(x));
}

/**
 * Repairs a possibly-corrupted/partial save payload (e.g. missing fields,
 * wrong types from an older schema version, truncated JSON) by merging it
 * on top of sane defaults. Never throws.
 */
export function sanitizeProfile(id: string, raw: unknown): PlayerProfile {
  const fallback = defaultProfile(id);
  if (!raw || typeof raw !== "object") return fallback;
  const r = raw as Record<string, unknown>;

  const settingsRaw = (r.settings && typeof r.settings === "object" ? r.settings : {}) as Record<
    string,
    unknown
  >;

  const settings: PlayerSettings = {
    joystickMode: settingsRaw.joystickMode === "fixed" ? "fixed" : "floating",
    sfxVolume:
      typeof settingsRaw.sfxVolume === "number" && settingsRaw.sfxVolume >= 0 && settingsRaw.sfxVolume <= 1
        ? settingsRaw.sfxVolume
        : fallback.settings.sfxVolume,
    musicVolume:
      typeof settingsRaw.musicVolume === "number" &&
      settingsRaw.musicVolume >= 0 &&
      settingsRaw.musicVolume <= 1
        ? settingsRaw.musicVolume
        : fallback.settings.musicVolume,
    autoAbsorb: typeof settingsRaw.autoAbsorb === "boolean" ? settingsRaw.autoAbsorb : true,
    language: settingsRaw.language === "en" ? "en" : "ru",
  };

  return {
    id,
    currency: typeof r.currency === "number" && r.currency >= 0 ? Math.floor(r.currency) : 0,
    totalRuns: typeof r.totalRuns === "number" && r.totalRuns >= 0 ? Math.floor(r.totalRuns) : 0,
    totalWins: typeof r.totalWins === "number" && r.totalWins >= 0 ? Math.floor(r.totalWins) : 0,
    totalBossKills:
      typeof r.totalBossKills === "number" && r.totalBossKills >= 0 ? Math.floor(r.totalBossKills) : 0,
    bestMass: typeof r.bestMass === "number" && r.bestMass >= 0 ? Math.floor(r.bestMass) : 0,
    bestDurationSec:
      typeof r.bestDurationSec === "number" && r.bestDurationSec >= 0 ? Math.floor(r.bestDurationSec) : 0,
    upgrades:
      r.upgrades && typeof r.upgrades === "object" && !Array.isArray(r.upgrades)
        ? (r.upgrades as Record<string, number>)
        : {},
    unlockedMutations: isStringArray(r.unlockedMutations)
      ? Array.from(new Set([...r.unlockedMutations, ...DEFAULT_UNLOCKED_MUTATIONS]))
      : fallback.unlockedMutations,
    discoveredCreatures: isStringArray(r.discoveredCreatures) ? r.discoveredCreatures : [],
    discoveredForms: isNumberArray(r.discoveredForms) ? r.discoveredForms : [],
    achievements: isStringArray(r.achievements) ? r.achievements : [],
    settings,
    noAds: typeof r.noAds === "boolean" ? r.noAds : false,
    ownedCosmetics: isStringArray(r.ownedCosmetics) ? r.ownedCosmetics : [],
    equippedCosmetic: typeof r.equippedCosmetic === "string" ? r.equippedCosmetic : null,
  };
}
