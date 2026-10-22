import { NextRequest } from "next/server";
import { getOrCreateProfile, recordRunFinish, recordRunStart, saveProfilePatch } from "@/lib/game/db";
import { calcRunReward } from "@/lib/game/economy";
import { BALANCE } from "@/lib/game/constants";
import { evolutionStageForMass } from "@/lib/game/growth";

export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  const body = await req.json();

  if (body.action === "start") {
    const { playerId, runId, mode } = body as { playerId: string; runId: string; mode: string };
    if (!playerId || !runId || !mode) {
      return Response.json({ error: "playerId, runId and mode are required" }, { status: 400 });
    }
    await recordRunStart(playerId, runId, mode);
    return Response.json({ ok: true });
  }

  if (body.action === "finish") {
    const {
      playerId,
      runId,
      result,
      massReached,
      durationSec,
      mutationsChosen,
      bossDefeated,
      creaturesDiscovered,
    } = body as {
      playerId: string;
      runId: string;
      result: "victory" | "defeat" | "abandoned";
      massReached: number;
      durationSec: number;
      mutationsChosen: string[];
      bossDefeated: boolean;
      creaturesDiscovered: string[];
    };

    if (!playerId || !runId || !result) {
      return Response.json({ error: "playerId, runId and result are required" }, { status: 400 });
    }

    const currencyEarned = calcRunReward({
      massReached: massReached ?? 0,
      durationSec: durationSec ?? 0,
      bossDefeated: !!bossDefeated,
      result,
    });

    await recordRunFinish(playerId, runId, {
      result,
      massReached: massReached ?? 0,
      durationSec: durationSec ?? 0,
      mutationsChosen: mutationsChosen ?? [],
      bossDefeated: !!bossDefeated,
      currencyEarned,
    });

    const profile = await getOrCreateProfile(playerId);
    const stage = evolutionStageForMass(massReached ?? 0, BALANCE.EVOLUTION_THRESHOLDS);
    const newForms = Array.from(new Set([...profile.discoveredForms, ...Array.from({ length: stage + 1 }, (_, i) => i)]));
    const newCreatures = Array.from(new Set([...profile.discoveredCreatures, ...(creaturesDiscovered ?? [])]));

    const achievements = new Set(profile.achievements);
    if (result === "victory") achievements.add("first_victory");
    if (bossDefeated) achievements.add("guardian_slayer");
    if ((massReached ?? 0) >= 1000) achievements.add("colossal_slime");
    if (profile.totalRuns + 1 >= 5) achievements.add("persistent_slime");

    const updated = await saveProfilePatch(playerId, {
      currency: profile.currency + currencyEarned,
      totalRuns: profile.totalRuns + 1,
      totalWins: profile.totalWins + (result === "victory" ? 1 : 0),
      totalBossKills: profile.totalBossKills + (bossDefeated ? 1 : 0),
      bestMass: Math.max(profile.bestMass, massReached ?? 0),
      bestDurationSec: Math.max(profile.bestDurationSec, durationSec ?? 0),
      discoveredForms: newForms,
      discoveredCreatures: newCreatures,
      achievements: Array.from(achievements),
    });

    return Response.json({ profile: updated, currencyEarned });
  }

  return Response.json({ error: "unknown action" }, { status: 400 });
}
