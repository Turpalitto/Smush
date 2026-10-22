import { describe, it, expect } from "vitest";
import { defaultProfile, sanitizeProfile } from "@/lib/game/save";

describe("save/load", () => {
  it("defaultProfile produces a valid starter profile", () => {
    const p = defaultProfile("device-1");
    expect(p.currency).toBe(0);
    expect(p.unlockedMutations.length).toBeGreaterThan(0);
  });

  it("sanitizeProfile round-trips a valid profile unchanged", () => {
    const original = defaultProfile("device-2");
    original.currency = 150;
    original.unlockedMutations.push("electric");
    const restored = sanitizeProfile("device-2", original);
    expect(restored.currency).toBe(150);
    expect(restored.unlockedMutations).toContain("electric");
  });
});

describe("corrupted save recovery", () => {
  it("falls back to defaults for null/undefined", () => {
    expect(sanitizeProfile("device-3", null)).toEqual(defaultProfile("device-3"));
    expect(sanitizeProfile("device-3", undefined)).toEqual(defaultProfile("device-3"));
  });

  it("recovers from a completely malformed payload", () => {
    const result = sanitizeProfile("device-4", "not even an object");
    expect(result.currency).toBe(0);
  });

  it("clamps invalid negative currency to zero", () => {
    const result = sanitizeProfile("device-5", { currency: -999 });
    expect(result.currency).toBe(0);
  });

  it("drops malformed array fields instead of crashing", () => {
    const result = sanitizeProfile("device-6", { discoveredCreatures: [1, 2, 3], achievements: "nope" });
    expect(result.discoveredCreatures).toEqual([]);
    expect(result.achievements).toEqual([]);
  });

  it("keeps valid partial data while repairing the rest", () => {
    const result = sanitizeProfile("device-7", { currency: 42, settings: { sfxVolume: 2 } });
    expect(result.currency).toBe(42);
    // invalid volume (out of 0..1 range) falls back to default
    expect(result.settings.sfxVolume).toBeCloseTo(0.8);
  });
});
