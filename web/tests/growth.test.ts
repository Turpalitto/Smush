import { describe, it, expect } from "vitest";
import { massToRadius, speedMultiplierForMass, canAbsorb, evolutionStageForMass } from "@/lib/game/growth";
import { BALANCE } from "@/lib/game/constants";

describe("massToRadius", () => {
  it("grows monotonically with mass", () => {
    const r1 = massToRadius(10);
    const r2 = massToRadius(100);
    const r3 = massToRadius(1000);
    expect(r2).toBeGreaterThan(r1);
    expect(r3).toBeGreaterThan(r2);
  });

  it("never exceeds the configured maximum radius", () => {
    expect(massToRadius(10_000_000)).toBeLessThanOrEqual(BALANCE.MAX_RADIUS);
  });

  it("handles zero/negative mass defensively", () => {
    expect(() => massToRadius(0)).not.toThrow();
    expect(() => massToRadius(-5)).not.toThrow();
  });
});

describe("speedMultiplierForMass", () => {
  it("never drops below the configured floor", () => {
    expect(speedMultiplierForMass(1_000_000)).toBeGreaterThanOrEqual(BALANCE.MIN_SPEED_MULTIPLIER);
  });

  it("is close to 1 at zero mass", () => {
    expect(speedMultiplierForMass(0)).toBeCloseTo(1, 1);
  });

  it("decreases as mass grows", () => {
    expect(speedMultiplierForMass(500)).toBeLessThan(speedMultiplierForMass(50));
  });
});

describe("canAbsorb (absorption thresholds)", () => {
  it("allows absorbing a much smaller unarmored target", () => {
    expect(canAbsorb(100, { mass: 10 }, new Set())).toBe(true);
  });

  it("rejects a target that outweighs the absorb ratio", () => {
    expect(canAbsorb(100, { mass: 95 }, new Set())).toBe(false);
  });

  it("rejects armored targets without enough mass margin", () => {
    expect(canAbsorb(100, { mass: 55, armored: true }, new Set())).toBe(false);
  });

  it("spikes mutation helps crack armored targets", () => {
    const withoutSpikes = canAbsorb(100, { mass: 50, armored: true }, new Set());
    const withSpikes = canAbsorb(100, { mass: 50, armored: true }, new Set(["spikes"]));
    expect(withSpikes).toBe(true);
    expect(withoutSpikes).toBe(false);
  });

  it("requiresAnyMutation gates absorption of protected targets", () => {
    const target = { mass: 80, requiresAnyMutation: ["electric"] };
    expect(canAbsorb(100, target, new Set())).toBe(false);
    expect(canAbsorb(100, target, new Set(["electric"]))).toBe(true);
  });
});

describe("evolutionStageForMass", () => {
  const thresholds = [10, 20, 30];
  it("returns 0 below first threshold", () => {
    expect(evolutionStageForMass(5, thresholds)).toBe(0);
  });
  it("counts how many thresholds have been crossed", () => {
    expect(evolutionStageForMass(25, thresholds)).toBe(2);
    expect(evolutionStageForMass(35, thresholds)).toBe(3);
  });
});
