import "server-only";
import { db } from "@/db";
import { players, runs, analyticsEvents, adRewardGrants, purchases } from "@/db/schema";
import { eq, and } from "drizzle-orm";
import { defaultProfile, sanitizeProfile, type PlayerProfile } from "./save";
import type { AdRewardSlot } from "./ads";

export async function getOrCreateProfile(id: string): Promise<PlayerProfile> {
  const rows = await db.select().from(players).where(eq(players.id, id)).limit(1);
  if (rows.length === 0) {
    const fresh = defaultProfile(id);
    await db.insert(players).values({
      id,
      currency: fresh.currency,
      totalRuns: fresh.totalRuns,
      totalWins: fresh.totalWins,
      totalBossKills: fresh.totalBossKills,
      bestMass: fresh.bestMass,
      bestDurationSec: fresh.bestDurationSec,
      upgrades: fresh.upgrades,
      unlockedMutations: fresh.unlockedMutations,
      discoveredCreatures: fresh.discoveredCreatures,
      discoveredForms: fresh.discoveredForms,
      achievements: fresh.achievements,
      settings: fresh.settings,
      noAds: fresh.noAds,
      ownedCosmetics: fresh.ownedCosmetics,
      equippedCosmetic: fresh.equippedCosmetic,
    });
    return fresh;
  }
  await db.update(players).set({ lastSeenAt: new Date() }).where(eq(players.id, id));
  return sanitizeProfile(id, rows[0]);
}

export async function saveProfilePatch(id: string, patch: Partial<PlayerProfile>) {
  const current = await getOrCreateProfile(id);
  const merged = sanitizeProfile(id, { ...current, ...patch });
  await db
    .update(players)
    .set({
      currency: merged.currency,
      totalRuns: merged.totalRuns,
      totalWins: merged.totalWins,
      totalBossKills: merged.totalBossKills,
      bestMass: merged.bestMass,
      bestDurationSec: merged.bestDurationSec,
      upgrades: merged.upgrades,
      unlockedMutations: merged.unlockedMutations,
      discoveredCreatures: merged.discoveredCreatures,
      discoveredForms: merged.discoveredForms,
      achievements: merged.achievements,
      settings: merged.settings,
      noAds: merged.noAds,
      ownedCosmetics: merged.ownedCosmetics,
      equippedCosmetic: merged.equippedCosmetic,
      lastSeenAt: new Date(),
    })
    .where(eq(players.id, id));
  return merged;
}

export async function recordRunStart(playerId: string, runId: string, mode: string) {
  await db.insert(runs).values({ id: runId, playerId, mode }).onConflictDoNothing();
}

export async function recordRunFinish(
  playerId: string,
  runId: string,
  data: {
    result: "victory" | "defeat" | "abandoned";
    massReached: number;
    durationSec: number;
    mutationsChosen: string[];
    bossDefeated: boolean;
    currencyEarned: number;
  },
) {
  await db
    .update(runs)
    .set({
      endedAt: new Date(),
      result: data.result,
      massReached: data.massReached,
      durationSec: data.durationSec,
      mutationsChosen: data.mutationsChosen,
      bossDefeated: data.bossDefeated,
      currencyEarned: data.currencyEarned,
    })
    .where(and(eq(runs.id, runId), eq(runs.playerId, playerId)));
}

export async function logAnalyticsEvent(
  playerId: string,
  eventName: string,
  payload: Record<string, unknown>,
) {
  await db.insert(analyticsEvents).values({ playerId, eventName, payload });
}

export async function grantAdReward(
  playerId: string,
  runId: string,
  slot: AdRewardSlot,
): Promise<boolean> {
  try {
    await db.insert(adRewardGrants).values({ playerId, runId, slot });
    if (slot === "revive") {
      await db.update(runs).set({ rewardedReviveUsed: true }).where(eq(runs.id, runId));
    } else if (slot === "double") {
      await db.update(runs).set({ rewardedDoubleUsed: true }).where(eq(runs.id, runId));
    }
    return true;
  } catch {
    // Unique constraint violation on (runId, slot) -> already granted.
    return false;
  }
}

export async function recordPurchase(playerId: string, productId: string) {
  await db.insert(purchases).values({ playerId, productId, status: "completed" });
}

export async function listPurchases(playerId: string) {
  const rows = await db.select().from(purchases).where(eq(purchases.playerId, playerId));
  return rows.map((r) => r.productId);
}
