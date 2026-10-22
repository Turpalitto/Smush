import { UPGRADE_DEFS, DEFAULT_UNLOCKED_MUTATIONS } from "./constants";

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
function nonnegativeInteger(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.min(Math.floor(value), Number.MAX_SAFE_INTEGER) : 0;
}

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
    currency: nonnegativeInteger(r.currency),
    totalRuns: nonnegativeInteger(r.totalRuns),
    totalWins: nonnegativeInteger(r.totalWins),
    totalBossKills: nonnegativeInteger(r.totalBossKills),
    bestMass: nonnegativeInteger(r.bestMass),
    bestDurationSec: nonnegativeInteger(r.bestDurationSec),
    upgrades: sanitizeUpgrades(r.upgrades),
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

function sanitizeUpgrades(raw: unknown): Record<string, number> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const source = raw as Record<string, unknown>;
  return Object.fromEntries(UPGRADE_DEFS.filter((def) => def.key in source).map((def) => [
    def.key, Math.min(nonnegativeInteger(source[def.key]), def.maxLevel),
  ]));
}
