import { BALANCE } from "./constants";

/** Non-linear mass -> radius curve so growth slows down at high mass. */
export function massToRadius(mass: number): number {
  const safeMass = Math.max(mass, 1);
  const radius =
    BALANCE.BASE_RADIUS * Math.pow(safeMass / BALANCE.BASE_MASS, BALANCE.RADIUS_GROWTH_EXPONENT);
  return Math.min(radius, BALANCE.MAX_RADIUS);
}

/** Bigger slimes are slower and more visible, smaller ones are nimble. */
export function speedMultiplierForMass(mass: number): number {
  const penalty = mass / (mass + BALANCE.SPEED_MASS_HALF_LIFE);
  const multiplier = 1 - penalty * (1 - BALANCE.MIN_SPEED_MULTIPLIER);
  return Math.max(BALANCE.MIN_SPEED_MULTIPLIER, multiplier);
}

export function maxHpForMass(mass: number): number {
  return Math.round(BALANCE.PLAYER_BASE_HP + mass * BALANCE.HP_PER_MASS);
}

export interface AbsorbTarget {
  mass: number;
  armored?: boolean;
  requiresAnyMutation?: string[];
}

/**
 * Decides whether the player can absorb a target. This intentionally is
 * NOT a pure "bigger wins" rule: armored targets need a high mass margin
 * or a specific mutation (e.g. spikes crack armor), and some mutations
 * let the player punch above their mass.
 */
export function canAbsorb(
  playerMass: number,
  target: AbsorbTarget,
  activeMutations: ReadonlySet<string>,
): boolean {
  if (target.requiresAnyMutation && target.requiresAnyMutation.length > 0) {
    const hasRequired = target.requiresAnyMutation.some((id) => activeMutations.has(id));
    if (!hasRequired && target.mass > playerMass * (BALANCE.ABSORB_MASS_RATIO * 0.55)) {
      return false;
    }
  }

  const ratio = target.armored ? BALANCE.ABSORB_MASS_RATIO * 0.55 : BALANCE.ABSORB_MASS_RATIO;
  const bonus = target.armored && activeMutations.has("spikes") ? 1.35 : 1;
  return target.mass <= playerMass * ratio * bonus;
}

export function evolutionStageForMass(mass: number, thresholds: readonly number[]): number {
  let stage = 0;
  for (const t of thresholds) {
    if (mass >= t) stage++;
    else break;
  }
  return stage;
}
