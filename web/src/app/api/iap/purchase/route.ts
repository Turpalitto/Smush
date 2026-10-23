import { NextRequest } from "next/server";
import { getOrCreateProfile, recordPurchase, saveProfilePatch } from "@/lib/game/db";

export const dynamic = "force-dynamic";

// Sandbox / test purchase products. No real Google Play Billing is wired up
// in this environment — see MONETIZATION.md for the production plan.
const PRODUCTS: Record<string, { kind: "no_ads" | "cosmetic"; cosmeticId?: string }> = {
  no_ads: { kind: "no_ads" },
  cosmetic_crystal: { kind: "cosmetic", cosmeticId: "crystal" },
  cosmetic_shadow: { kind: "cosmetic", cosmeticId: "shadow" },
  cosmetic_golden: { kind: "cosmetic", cosmeticId: "golden" },
};

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { playerId, productId } = body as { playerId?: string; productId?: string };
  if (!playerId || !productId || !PRODUCTS[productId]) {
    return Response.json({ error: "invalid playerId/productId" }, { status: 400 });
  }

  const product = PRODUCTS[productId];
  const profile = await getOrCreateProfile(playerId);

  if (product.kind === "no_ads") {
    if (!profile.noAds) {
      await recordPurchase(playerId, productId);
    }
    const updated = await saveProfilePatch(playerId, { noAds: true });
    return Response.json({ ok: true, profile: updated });
  }

  if (product.kind === "cosmetic" && product.cosmeticId) {
    if (!profile.ownedCosmetics.includes(product.cosmeticId)) {
      await recordPurchase(playerId, productId);
    }
    const owned = Array.from(new Set([...profile.ownedCosmetics, product.cosmeticId]));
    const updated = await saveProfilePatch(playerId, { ownedCosmetics: owned });
    return Response.json({ ok: true, profile: updated });
  }

  return Response.json({ error: "unhandled product" }, { status: 400 });
}
