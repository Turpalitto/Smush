import { NextRequest } from "next/server";
import { logAnalyticsEvent } from "@/lib/game/db";
import { ANALYTICS_EVENTS } from "@/lib/game/analyticsEvents";

export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { playerId, eventName, payload } = body as {
      playerId?: string;
      eventName?: string;
      payload?: Record<string, unknown>;
    };
    if (!playerId || !eventName || !(ANALYTICS_EVENTS as readonly string[]).includes(eventName)) {
      return Response.json({ ok: false }, { status: 400 });
    }
    await logAnalyticsEvent(playerId, eventName, payload ?? {});
    return Response.json({ ok: true });
  } catch {
    return Response.json({ ok: false }, { status: 500 });
  }
}
