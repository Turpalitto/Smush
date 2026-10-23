import { describe, it, expect } from "vitest";
import { calcRunReward, upgradeCost, canAffordUpgrade } from "@/lib/game/economy";
import { UPGRADE_DEFS } from "@/lib/game/constants";

describe("calcRunReward", () => {
  it("abandoned runs earn nothing", () => {
    expect(calcRunReward({ massReached: 500, durationSec: 300, bossDefeated: true, result: "abandoned" })).toBe(0);
  });

  it("defeat earns less than an equivalent victory", () => {
    const base = { massReached: 300, durationSec: 240, bossDefeated: false } as const;
    const victory = calcRunReward({ ...base, result: "victory" });
    const defeat = calcRunReward({ ...base, result: "defeat" });
    expect(victory).toBeGreaterThan(defeat);
  });

  it("boss kill grants a bonus", () => {
    const base = { massReached: 300, durationSec: 240, result: "victory" } as const;
    const withBoss = calcRunReward({ ...base, bossDefeated: true });
    const withoutBoss = calcRunReward({ ...base, bossDefeated: false });
    expect(withBoss).toBeGreaterThan(withoutBoss);
  });

  it("never returns a negative reward", () => {
    const r = calcRunReward({ massReached: 0, durationSec: 0, bossDefeated: false, result: "defeat" });
    expect(r).toBeGreaterThanOrEqual(0);
  });
});

describe("upgradeCost / canAffordUpgrade", () => {
  it("cost increases with level", () => {
    const key = UPGRADE_DEFS[0].key;
    expect(upgradeCost(key, 1)).toBeGreaterThan(upgradeCost(key, 0));
  });

  it("returns Infinity at max level (hard cap)", () => {
    const def = UPGRADE_DEFS[0];
    expect(upgradeCost(def.key, def.maxLevel)).toBe(Infinity);
  });

  it("affordability respects currency amount", () => {
    const key = UPGRADE_DEFS[0].key;
    const cost = upgradeCost(key, 0);
    expect(canAffordUpgrade(cost, key, 0)).toBe(true);
    expect(canAffordUpgrade(cost - 1, key, 0)).toBe(false);
  });
});
