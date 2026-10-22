import { NextRequest } from "next/server";
import { getOrCreateProfile, saveProfilePatch } from "@/lib/game/db";
import type { PlayerProfile } from "@/lib/game/save";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
  const playerId = req.nextUrl.searchParams.get("playerId");
  if (!playerId) return Response.json({ error: "playerId required" }, { status: 400 });
  const profile = await getOrCreateProfile(playerId);
  return Response.json({ profile });
}

export async function POST(req: NextRequest) {
  const body = (await req.json()) as { playerId?: string; patch?: Partial<PlayerProfile> };
  if (!body.playerId) return Response.json({ error: "playerId required" }, { status: 400 });
  const profile = await saveProfilePatch(body.playerId, body.patch ?? {});
  return Response.json({ profile });
}
