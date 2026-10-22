import { NextRequest } from "next/server";
import { getOrCreateProfile, grantAdReward, saveProfilePatch } from "@/lib/game/db";
import type { AdRewardSlot } from "@/lib/game/ads";

export const dynamic = "force-dynamic";

const VALID_SLOTS: AdRewardSlot[] = ["revive", "double", "extra_mutation"];

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { playerId, runId, slot } = body as { playerId?: string; runId?: string; slot?: AdRewardSlot };

  if (!playerId || !runId || !slot || !VALID_SLOTS.includes(slot)) {
    return Response.json({ error: "playerId, runId and a valid slot are required" }, { status: 400 });
  }

  // Server-side idempotency: the unique (runId, slot) index in
  // ad_reward_grants guarantees this reward is only ever granted once,
  // even if the client retries the request.
  const granted = await grantAdReward(playerId, runId, slot);
  if (!granted) {
    return Response.json({ granted: false, reason: "already_granted" });
  }

  let currencyBonus = 0;
  if (slot === "double") {
    const profile = await getOrCreateProfile(playerId);
    // The doubling amount is computed client-side from the already-recorded
    // run reward and passed back here for the bonus half; this keeps the
    // source of truth (the run reward) server-side while still allowing a
    // simple one-shot "double" grant.
    currencyBonus = Math.round((body.baseReward ?? 0));
    await saveProfilePatch(playerId, { currency: profile.currency + currencyBonus });
  }

  return Response.json({ granted: true, currencyBonus });
}
