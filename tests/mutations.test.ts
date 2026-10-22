import { describe, it, expect } from "vitest";
import { mulberry32 } from "@/lib/game/rng";
import { rollMutationChoices, detectActiveCombos, MUTATIONS, COMBOS } from "@/lib/game/mutations";
import { DEFAULT_UNLOCKED_MUTATIONS } from "@/lib/game/constants";

describe("rollMutationChoices", () => {
  it("returns the requested number of distinct mutations", () => {
    const rng = mulberry32(42);
    const choices = rollMutationChoices(rng, DEFAULT_UNLOCKED_MUTATIONS, {}, 3);
    expect(choices).toHaveLength(3);
    const ids = choices.map((c) => c.id);
    expect(new Set(ids).size).toBe(3);
  });

  it("only returns mutations from the unlocked pool", () => {
    const rng = mulberry32(7);
    const pool = ["magnet", "haste"];
    const choices = rollMutationChoices(rng, pool, {}, 5);
    expect(choices.length).toBe(2);
    for (const c of choices) expect(pool).toContain(c.id);
  });

  it("excludes mutations already at max level", () => {
    const rng = mulberry32(1);
    const maxed = Object.fromEntries(MUTATIONS.map((m) => [m.id, m.maxLevel]));
    const choices = rollMutationChoices(rng, DEFAULT_UNLOCKED_MUTATIONS, maxed, 3);
    expect(choices).toHaveLength(0);
  });

  it("is deterministic for a fixed seed", () => {
    const a = rollMutationChoices(mulberry32(99), DEFAULT_UNLOCKED_MUTATIONS, {}, 3).map((m) => m.id);
    const b = rollMutationChoices(mulberry32(99), DEFAULT_UNLOCKED_MUTATIONS, {}, 3).map((m) => m.id);
    expect(a).toEqual(b);
  });
});

describe("level restrictions", () => {
  it("every mutation has a positive max level", () => {
    for (const m of MUTATIONS) {
      expect(m.maxLevel).toBeGreaterThan(0);
    }
  });
});

describe("combos", () => {
  it("there are at least five combos defined", () => {
    expect(COMBOS.length).toBeGreaterThanOrEqual(5);
  });

  it("detects a combo only when both required mutations are owned", () => {
    expect(detectActiveCombos(["magnet"])).toHaveLength(0);
    const active = detectActiveCombos(["magnet", "electric"]);
    expect(active.map((c) => c.id)).toContain("storm_emp");
  });

  it("every combo references two valid mutation ids", () => {
    const ids = new Set(MUTATIONS.map((m) => m.id));
    for (const combo of COMBOS) {
      expect(ids.has(combo.requires[0])).toBe(true);
      expect(ids.has(combo.requires[1])).toBe(true);
    }
  });
});
