export type AdRewardSlot = "revive" | "double" | "extra_mutation";

export interface AdGrantRecord {
  runId: string;
  slot: AdRewardSlot;
}

/**
 * Pure anti-double-grant check: a given (runId, slot) pair may only be
 * rewarded once. Mirrors the unique DB constraint on ad_reward_grants so
 * the rule can be unit tested without a database.
 */
export function canGrantReward(
  existingGrants: readonly AdGrantRecord[],
  runId: string,
  slot: AdRewardSlot,
): boolean {
  return !existingGrants.some((g) => g.runId === runId && g.slot === slot);
}

/** Simulated ad SDK result. A real integration would report this from the
 * provider's callback (e.g. onUserEarnedReward). */
export interface AdPlaybackResult {
  completed: boolean;
  reason?: "closed_early" | "network_unavailable" | "no_fill";
}

export function isRewardEligible(result: AdPlaybackResult): boolean {
  return result.completed === true;
}
