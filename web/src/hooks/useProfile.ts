"use client";

import { useCallback, useEffect, useState } from "react";
import { getDeviceId, trackEvent } from "@/lib/game/client";
import { defaultProfile, sanitizeProfile, type PlayerProfile } from "@/lib/game/save";

async function fetchProfile(): Promise<PlayerProfile> {
  const id = getDeviceId();
  try {
    const res = await fetch(`/api/profile?playerId=${encodeURIComponent(id)}`);
    if (!res.ok) throw new Error("Profile unavailable");
    const data = await res.json();
    return sanitizeProfile(id, data.profile);
  } catch {
    return defaultProfile(id);
  }
}

export function useProfile() {
  const [profile, setProfile] = useState<PlayerProfile | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setProfile(await fetchProfile());
    setLoading(false);
  }, []);

  useEffect(() => {
    let cancelled = false;
    const isFirstLaunch = !window.localStorage.getItem("slime_rush_launched");
    fetchProfile().then((data) => {
      if (cancelled) return;
      setProfile(data);
      setLoading(false);
      if (isFirstLaunch) {
        window.localStorage.setItem("slime_rush_launched", "1");
        void trackEvent("first_launch");
      }
    });
    return () => { cancelled = true; };
  }, []);

  const patchProfile = useCallback(async (patch: Partial<PlayerProfile>) => {
    const id = getDeviceId();
    const res = await fetch("/api/profile", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ playerId: id, patch }),
    });
    if (!res.ok) throw new Error("Profile update failed");
    const data = await res.json();
    const updated = sanitizeProfile(id, data.profile);
    setProfile(updated);
    return updated;
  }, []);

  return { profile, loading, refresh, patchProfile, setProfile };
}
