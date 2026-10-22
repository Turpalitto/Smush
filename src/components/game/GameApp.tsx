"use client";

import { useCallback, useState } from "react";
import { useProfile } from "@/hooks/useProfile";
import { PlayScreen } from "./PlayScreen";
import { MainMenu, ModeSelect, UpgradesScreen, CollectionScreen, SettingsScreen, ShopScreen, PrivacyScreen } from "./MenuScreens";
import type { GameMode } from "@/lib/game/engine";
import type { PlayerProfile } from "@/lib/game/save";
import { defaultProfile } from "@/lib/game/save";

type Screen = "menu" | "mode-select" | "playing" | "upgrades" | "collection" | "settings" | "shop" | "privacy";

export function GameApp() {
  const { profile, loading, patchProfile, setProfile } = useProfile();
  const [screen, setScreen] = useState<Screen>("menu");
  const [mode, setMode] = useState<GameMode>("classic");

  const handleBuyUpgrade = useCallback(
    (key: string) => {
      if (!profile) return;
      const level = profile.upgrades[key] ?? 0;
      import("@/lib/game/economy").then(({ upgradeCost }) => {
        const cost = upgradeCost(key as never, level);
        if (!Number.isFinite(cost) || profile.currency < cost) return;
        void patchProfile({
          currency: profile.currency - cost,
          upgrades: { ...profile.upgrades, [key]: level + 1 },
        });
      });
    },
    [profile, patchProfile],
  );

  const handleUnlockMutation = useCallback(
    async (id: string) => {
      if (!profile) return;
      const { MUTATION_UNLOCK_COST } = await import("@/lib/game/constants");
      const cost = MUTATION_UNLOCK_COST[id] ?? 0;
      if (profile.currency < cost || profile.unlockedMutations.includes(id)) return;
      void patchProfile({
        currency: profile.currency - cost,
        unlockedMutations: [...profile.unlockedMutations, id],
      });
    },
    [profile, patchProfile],
  );

  if (loading || !profile) {
    return (
      <div className="grid min-h-dvh place-items-center bg-slate-950 text-white">
        <div className="animate-pulse text-lg">🟢 Загрузка...</div>
      </div>
    );
  }

  if (screen === "playing") {
    return (
      <PlayScreen
        mode={mode}
        profile={profile}
        onExit={(updated) => {
          if (updated) setProfile(updated);
          setScreen("menu");
        }}
      />
    );
  }

  switch (screen) {
    case "mode-select":
      return (
        <ModeSelect
          onBack={() => setScreen("menu")}
          onStart={(m) => {
            setMode(m);
            setScreen("playing");
          }}
        />
      );
    case "upgrades":
      return (
        <UpgradesScreen
          profile={profile}
          onBack={() => setScreen("menu")}
          onBuyUpgrade={handleBuyUpgrade}
          onUnlockMutation={handleUnlockMutation}
        />
      );
    case "collection":
      return <CollectionScreen profile={profile} onBack={() => setScreen("menu")} />;
    case "settings":
      return (
        <SettingsScreen
          profile={profile}
          onBack={() => setScreen("menu")}
          onChange={(settings) => void patchProfile({ settings })}
          onReset={() => void patchProfile(defaultProfile(profile.id) as Partial<PlayerProfile>)}
        />
      );
    case "shop":
      return <ShopScreen profile={profile} onBack={() => setScreen("menu")} onProfileUpdate={setProfile} />;
    case "privacy":
      return <PrivacyScreen onBack={() => setScreen("menu")} />;
    default:
      return <MainMenu profile={profile} onNavigate={(s) => setScreen(s)} />;
  }
}
