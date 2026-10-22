import { describe, it, expect } from "vitest";
import { canGrantReward, isRewardEligible } from "@/lib/game/ads";

describe("rewarded ad grants", () => {
  it("allows the first grant for a run/slot pair", () => {
    expect(canGrantReward([], "run-1", "revive")).toBe(true);
  });

  it("blocks a second grant for the same run/slot pair", () => {
    const existing = [{ runId: "run-1", slot: "revive" as const }];
    expect(canGrantReward(existing, "run-1", "revive")).toBe(false);
  });

  it("allows different slots on the same run", () => {
    const existing = [{ runId: "run-1", slot: "revive" as const }];
    expect(canGrantReward(existing, "run-1", "double")).toBe(true);
  });

  it("allows the same slot on a different run", () => {
    const existing = [{ runId: "run-1", slot: "revive" as const }];
    expect(canGrantReward(existing, "run-2", "revive")).toBe(true);
  });

  it("only grants rewards for genuinely completed ad playback", () => {
    expect(isRewardEligible({ completed: true })).toBe(true);
    expect(isRewardEligible({ completed: false, reason: "closed_early" })).toBe(false);
    expect(isRewardEligible({ completed: false, reason: "no_fill" })).toBe(false);
  });
});
