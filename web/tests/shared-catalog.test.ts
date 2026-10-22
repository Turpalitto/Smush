import { describe, it, expect } from "vitest";
import synergies from "../../resources/data/synergies.json";
import mutations from "../../resources/data/mutations.json";
import { COMBOS, MUTATIONS, GODOT_TO_WEB_MUTATION, detectActiveCombos } from "@/lib/game/mutations";

describe("shared Godot/browser catalog", () => {
  it("maps every native mutation to exactly one existing browser mutation", () => {
    const mapped = mutations.mutations.map((m) => GODOT_TO_WEB_MUTATION[m.id] ?? m.id);
    expect([...mapped].sort()).toEqual(MUTATIONS.map((m) => m.id).sort());
  });

  it("activates every native recipe in the browser without changing existing save IDs", () => {
    expect(COMBOS).toHaveLength(synergies.synergies.length);
    for (const recipe of synergies.synergies) {
      const webId = recipe.id === "em_storm" ? "storm_emp" : recipe.id;
      const requirements = recipe.required_mutations.map((id) => GODOT_TO_WEB_MUTATION[id] ?? id);
      expect(detectActiveCombos(requirements).map((c) => c.id)).toContain(webId);
      expect(detectActiveCombos(requirements.slice(0, 1)).map((c) => c.id)).not.toContain(webId);
    }
  });
});
