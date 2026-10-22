import { UPGRADE_DEFS, UpgradeKey, upgradeCost } from "./constants";

export interface RunSummary {
  massReached: number;
  durationSec: number;
  bossDefeated: boolean;
  result: "victory" | "defeat" | "abandoned";
}

/** Deterministic currency reward for a finished run. */
export function calcRunReward(run: RunSummary): number {
  if (run.result === "abandoned") return 0;
  const massReward = Math.round(run.massReached * 0.35);
  const timeReward = Math.round(run.durationSec * 0.12);
  const bossBonus = run.bossDefeated ? 120 : 0;
  const defeatPenalty = run.result === "defeat" ? 0.6 : 1;
  return Math.max(0, Math.round((massReward + timeReward + bossBonus) * defeatPenalty));
}

export { UPGRADE_DEFS, upgradeCost };
export type { UpgradeKey };

export function applyUpgradeEffects(upgrades: Record<string, number>) {
  const startMassLevel = upgrades.startMass ?? 0;
  const moveSpeedLevel = upgrades.moveSpeed ?? 0;
  const essenceChanceLevel = upgrades.essenceChance ?? 0;

  const startMassDef = UPGRADE_DEFS.find((u) => u.key === "startMass")!;
  const moveSpeedDef = UPGRADE_DEFS.find((u) => u.key === "moveSpeed")!;
  const essenceDef = UPGRADE_DEFS.find((u) => u.key === "essenceChance")!;

  return {
    startMassBonus: startMassLevel * startMassDef.effectPerLevel,
    speedMultBonus: moveSpeedLevel * moveSpeedDef.effectPerLevel,
    essenceChanceBonus: essenceChanceLevel * essenceDef.effectPerLevel,
  };
}

export function canAffordUpgrade(currency: number, key: UpgradeKey, currentLevel: number): boolean {
  return currency >= upgradeCost(key, currentLevel);
}
