"use client";

import type { AdPlaybackResult, AdRewardSlot } from "./ads";
import type { AnalyticsEventName } from "./analyticsEvents";

const DEVICE_ID_KEY = "slime_rush_device_id";

export function getDeviceId(): string {
  if (typeof window === "undefined") return "server";
  let id = window.localStorage.getItem(DEVICE_ID_KEY);
  if (!id) {
    id = crypto.randomUUID();
    window.localStorage.setItem(DEVICE_ID_KEY, id);
  }
  return id;
}

export async function trackEvent(name: AnalyticsEventName, payload: Record<string, unknown> = {}) {
  try {
    await fetch("/api/analytics", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ playerId: getDeviceId(), eventName: name, payload }),
      keepalive: true,
    });
  } catch {
    // Analytics must never break gameplay; swallow network errors.
  }
}

/**
 * TEST rewarded-ad adapter. This is NOT a real ad SDK integration — there is
 * no Android/Google Mobile Ads environment available in this sandbox. The
 * interface matches what a real "rewarded ad" callback would report
 * (completed vs. closed early / no fill), so swapping in a production SDK
 * (e.g. Google Mobile Ads / AdMob) later only means replacing this module.
 * See MONETIZATION.md.
 */
export async function playTestRewardedAd(): Promise<AdPlaybackResult> {
  // Simulate network + playback latency.
  await new Promise((r) => setTimeout(r, 1400));
  // Simulate an occasional no-fill to exercise the "ad unavailable, game
  // continues normally" path.
  const noFillRoll = Math.random();
  if (noFillRoll < 0.04) {
    return { completed: false, reason: "no_fill" };
  }
  return { completed: true };
}

export async function confirmRewardedAd(runId: string, slot: AdRewardSlot) {
  const res = await fetch("/api/ads/reward", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ playerId: getDeviceId(), runId, slot }),
  });
  if (!res.ok) return { granted: false as const };
  return (await res.json()) as { granted: boolean; currency?: number };
}

/**
 * TEST billing adapter. This simulates Google Play Billing in sandbox mode
 * (there is no real Play Console / merchant account wired up here). All
 * purchases are recorded server-side and are idempotent per product for
 * non-consumables. See MONETIZATION.md for the production integration plan.
 */
export async function purchaseTestProduct(productId: string) {
  await trackEvent("purchase_started", { productId });
  await new Promise((r) => setTimeout(r, 700));
  const res = await fetch("/api/iap/purchase", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ playerId: getDeviceId(), productId }),
  });
  const data = await res.json();
  if (res.ok) await trackEvent("purchase_completed", { productId });
  return data;
}

export async function restorePurchases() {
  const res = await fetch(`/api/iap/restore?playerId=${encodeURIComponent(getDeviceId())}`);
  if (!res.ok) return { purchases: [] as string[] };
  return (await res.json()) as { purchases: string[] };
}
