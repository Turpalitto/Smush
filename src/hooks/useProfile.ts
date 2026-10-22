"use client";

import { useCallback, useEffect, useState } from "react";
import { getDeviceId, trackEvent } from "@/lib/game/client";
import { defaultProfile, type PlayerProfile } from "@/lib/game/save";

export function useProfile() {
  const [profile, setProfile] = useState<PlayerProfile | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    const id = getDeviceId();
    try {
      const res = await fetch(`/api/profile?playerId=${encodeURIComponent(id)}`);
      const data = await res.json();
      setProfile(data.profile as PlayerProfile);
    } catch {
      setProfile(defaultProfile(id));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const isFirstLaunch = !window.localStorage.getItem("slime_rush_launched");
    refresh().then(() => {
      if (isFirstLaunch) {
        window.localStorage.setItem("slime_rush_launched", "1");
        void trackEvent("first_launch");
      }
    });
  }, [refresh]);

  const patchProfile = useCallback(async (patch: Partial<PlayerProfile>) => {
    const id = getDeviceId();
    const res = await fetch("/api/profile", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ playerId: id, patch }),
    });
    const data = await res.json();
    setProfile(data.profile as PlayerProfile);
    return data.profile as PlayerProfile;
  }, []);

  return { profile, loading, refresh, patchProfile, setProfile };
}
