import { NextRequest } from "next/server";
import { listPurchases } from "@/lib/game/db";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
  const playerId = req.nextUrl.searchParams.get("playerId");
  if (!playerId) return Response.json({ error: "playerId required" }, { status: 400 });
  const purchasedProductIds = await listPurchases(playerId);
  return Response.json({ purchases: purchasedProductIds });
}
