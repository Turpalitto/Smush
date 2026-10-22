"use client";

import { useEffect, useRef, useState, useCallback, type ReactNode } from "react";
import { SlimeRushEngine, type GameMode, type Snapshot, type RunResultSummary } from "@/lib/game/engine";
import type { MutationDef, ComboDef } from "@/lib/game/mutations";
import { applyUpgradeEffects } from "@/lib/game/economy";
import { soundManager } from "@/lib/game/sound";
import { Joystick } from "./Joystick";
import { getDeviceId, trackEvent, playTestRewardedAd, confirmRewardedAd } from "@/lib/game/client";
import type { PlayerProfile } from "@/lib/game/save";
import { t } from "@/lib/game/i18n";

interface PlayScreenProps {
  mode: GameMode;
  profile: PlayerProfile;
  onExit: (updatedProfile: PlayerProfile | null) => void;
}

type OverlayState =
  | { kind: "none" }
  | { kind: "mutation"; choices: MutationDef[]; extraUsed: boolean }
  | { kind: "paused" }
  | { kind: "revive-offer" }
  | { kind: "result"; result: "victory" | "defeat"; summary: RunResultSummary; currencyEarned: number; doubled: boolean };

export function PlayScreen({ mode, profile, onExit }: PlayScreenProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<SlimeRushEngine | null>(null);
  const runIdRef = useRef<string>(crypto.randomUUID());
  const lang = profile.settings.language;

  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [overlay, setOverlay] = useState<OverlayState>({ kind: "none" });
  const [comboToast, setComboToast] = useState<ComboDef | null>(null);
  const [adBusy, setAdBusy] = useState(false);

  useEffect(() => {
    soundManager.setSfxVolume(profile.settings.sfxVolume);
    soundManager.setMusicVolume(profile.settings.musicVolume);
  }, [profile.settings.sfxVolume, profile.settings.musicVolume]);

  useEffect(() => {
    void trackEvent("run_started", { mode });
    fetch("/api/run", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "start", playerId: getDeviceId(), runId: runIdRef.current, mode }),
    }).catch(() => {});
  }, [mode]);

  const finishRun = useCallback(
    async (result: "victory" | "defeat" | "abandoned", summary: RunResultSummary) => {
      void trackEvent("run_duration", { durationSec: summary.durationSec });
      void trackEvent("run_finished", { result, mode, massReached: summary.massReached });
      try {
        const res = await fetch("/api/run", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action: "finish",
            playerId: getDeviceId(),
            runId: runIdRef.current,
            result,
            massReached: summary.massReached,
            durationSec: summary.durationSec,
            mutationsChosen: summary.mutationsChosen,
            bossDefeated: summary.bossDefeated,
            creaturesDiscovered: Array.from(engineRef.current?.getSnapshot().encounteredCreatures ?? []),
          }),
        });
        const data = await res.json();
        return { profile: data.profile as PlayerProfile, currencyEarned: data.currencyEarned as number };
      } catch {
        return { profile: null, currencyEarned: 0 };
      }
    },
    [mode],
  );

  useEffect(() => {
    if (!canvasRef.current) return;
    const effects = applyUpgradeEffects(profile.upgrades);
    const engine = new SlimeRushEngine(
      canvasRef.current,
      {
        mode,
        seed: Math.floor(Math.random() * 1_000_000_000),
        startMassBonus: effects.startMassBonus,
        speedMultBonus: effects.speedMultBonus,
        essenceChanceBonus: effects.essenceChanceBonus,
        unlockedMutations: profile.unlockedMutations,
        autoAbsorb: profile.settings.autoAbsorb,
      },
      {
        onMutationChoice: (choices) => {
          soundManager.play("evolve");
          setOverlay({ kind: "mutation", choices, extraUsed: false });
        },
        onComboUnlocked: (combo) => {
          soundManager.play("mutation");
          setComboToast(combo);
          setTimeout(() => setComboToast(null), 3200);
        },
        onEvolve: () => soundManager.play("evolve"),
        onAbsorb: (kind) => soundManager.play(kind === "enemy" ? "absorb_big" : "absorb"),
        onDamaged: () => soundManager.play("damage"),
        onBossEncountered: () => {
          soundManager.play("boss");
          void trackEvent("boss_encountered");
        },
        onBossDefeated: () => void trackEvent("boss_defeated"),
        onPlayerDowned: () => {
          soundManager.play("damage");
          setOverlay({ kind: "revive-offer" });
        },
        onGameOver: async (result, summary) => {
          soundManager.play(result === "victory" ? "victory" : "defeat");
          const { currencyEarned } = await finishRun(result, summary);
          setOverlay({ kind: "result", result, summary, currencyEarned, doubled: false });
        },
        onCreatureDiscovered: () => {},
      },
    );
    engineRef.current = engine;
    engine.start();

    const interval = setInterval(() => {
      setSnapshot(engine.getSnapshot());
    }, 120);

    return () => {
      clearInterval(interval);
      engine.stop();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleJoystick = useCallback((x: number, y: number) => {
    engineRef.current?.setInputVector(x, y);
  }, []);

  const handleDash = useCallback(() => {
    engineRef.current?.requestDash();
  }, []);

  const togglePause = () => {
    if (overlay.kind === "paused") {
      setOverlay({ kind: "none" });
      engineRef.current?.setPaused(false);
    } else if (overlay.kind === "none") {
      soundManager.play("click");
      engineRef.current?.setPaused(true);
      setOverlay({ kind: "paused" });
    }
  };

  const chooseMutation = (id: string) => {
    soundManager.play("mutation");
    engineRef.current?.chooseMutation(id);
    void trackEvent("mutation_selected", { mutationId: id });
    setOverlay({ kind: "none" });
  };

  const requestExtraMutation = async () => {
    if (overlay.kind !== "mutation" || adBusy) return;
    setAdBusy(true);
    void trackEvent("rewarded_ad_offered", { slot: "extra_mutation" });
    const result = await playTestRewardedAd();
    if (result.completed) {
      const confirm = await confirmRewardedAd(runIdRef.current, "extra_mutation");
      if (confirm.granted) {
        void trackEvent("rewarded_ad_completed", { slot: "extra_mutation" });
        const { rollMutationChoices } = await import("@/lib/game/mutations");
        const { mulberry32 } = await import("@/lib/game/rng");
        const extra = rollMutationChoices(mulberry32(Date.now() % 1_000_000), profile.unlockedMutations, {}, 1);
        setOverlay((prev) =>
          prev.kind === "mutation" ? { kind: "mutation", choices: [...prev.choices, ...extra], extraUsed: true } : prev,
        );
      }
    }
    setAdBusy(false);
  };

  const requestRevive = async () => {
    if (adBusy) return;
    setAdBusy(true);
    void trackEvent("rewarded_ad_offered", { slot: "revive" });
    const result = await playTestRewardedAd();
    if (result.completed) {
      const confirm = await confirmRewardedAd(runIdRef.current, "revive");
      if (confirm.granted) {
        void trackEvent("rewarded_ad_completed", { slot: "revive" });
        engineRef.current?.reviveWithAd();
        setOverlay({ kind: "none" });
      }
    }
    setAdBusy(false);
  };

  const declineRevive = () => {
    engineRef.current?.finalizeDefeat();
  };

  const requestDoubleReward = async () => {
    if (overlay.kind !== "result" || adBusy || overlay.doubled) return;
    setAdBusy(true);
    void trackEvent("rewarded_ad_offered", { slot: "double" });
    const result = await playTestRewardedAd();
    if (result.completed) {
      const res = await fetch("/api/ads/reward", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          playerId: getDeviceId(),
          runId: runIdRef.current,
          slot: "double",
          baseReward: overlay.currencyEarned,
        }),
      });
      const data = await res.json();
      if (data.granted) {
        void trackEvent("rewarded_ad_completed", { slot: "double" });
        setOverlay((prev) =>
          prev.kind === "result" ? { ...prev, currencyEarned: prev.currencyEarned + data.currencyBonus, doubled: true } : prev,
        );
      }
    }
    setAdBusy(false);
  };

  const exitToMenu = async () => {
    void trackEvent("session_end");
    const res = await fetch(`/api/profile?playerId=${encodeURIComponent(getDeviceId())}`);
    const data = await res.json();
    onExit(data.profile ?? null);
  };

  const abandonRun = async () => {
    engineRef.current?.abandon();
    await finishRun("abandoned", {
      massReached: snapshot?.mass ?? 0,
      durationSec: snapshot?.elapsed ?? 0,
      bossDefeated: false,
      mutationsChosen: snapshot?.mutations.map((m) => m.id) ?? [],
    });
    await exitToMenu();
  };

  return (
    <div className="relative h-dvh w-full overflow-hidden bg-black">
      <canvas ref={canvasRef} className="h-full w-full" />

      {/* HUD */}
      {snapshot && overlay.kind !== "result" && (
        <div className="pointer-events-none absolute inset-x-0 top-0 flex flex-col gap-2 p-3">
          <div className="flex items-center gap-3">
            <button
              onClick={togglePause}
              className="pointer-events-auto grid h-10 w-10 place-items-center rounded-full bg-black/50 text-lg text-white backdrop-blur"
            >
              ⏸
            </button>
            <div className="flex-1 rounded-full bg-black/40 px-3 py-1.5 backdrop-blur">
              <div className="flex items-center justify-between text-[11px] text-emerald-100">
                <span>{t("mass", lang)}: {snapshot.mass}</span>
                <span>⏱ {Math.floor(snapshot.timeLeft / 60)}:{String(snapshot.timeLeft % 60).padStart(2, "0")}</span>
              </div>
              <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full bg-emerald-400 transition-[width]"
                  style={{ width: `${snapshot.evolutionProgress * 100}%` }}
                />
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <div className="h-2.5 flex-1 overflow-hidden rounded-full bg-black/40">
              <div
                className="h-full rounded-full bg-rose-500 transition-[width]"
                style={{ width: `${Math.max(0, (snapshot.hp / snapshot.maxHp) * 100)}%` }}
              />
            </div>
            <span className="rounded-full bg-black/40 px-2 py-0.5 text-[11px] text-white">
              {snapshot.hp}/{snapshot.maxHp}
            </span>
          </div>

          {snapshot.mutations.length > 0 && (
            <div className="flex flex-wrap gap-1.5">
              {snapshot.mutations.map((m) => (
                <span key={m.id} className="rounded-full bg-black/40 px-2 py-0.5 text-sm">
                  {getMutationIcon(m.id)}
                  {m.level > 1 ? <sup className="ml-0.5 text-[9px]">{m.level}</sup> : null}
                </span>
              ))}
            </div>
          )}

          {snapshot.bossActive && (
            <div className="mx-auto mt-1 w-full max-w-sm rounded-xl bg-black/50 px-3 py-1.5 backdrop-blur">
              <div className="text-center text-[11px] text-purple-200">{snapshot.bossNameRu}</div>
              <div className="mt-1 h-2 w-full overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full bg-purple-400 transition-[width]"
                  style={{ width: `${snapshot.bossHpFraction * 100}%` }}
                />
              </div>
            </div>
          )}
        </div>
      )}

      {comboToast && (
        <div className="absolute left-1/2 top-24 -translate-x-1/2 rounded-xl bg-indigo-900/90 px-4 py-2 text-center text-white shadow-lg">
          <div className="text-lg">{comboToast.icon} {comboToast.nameRu}</div>
          <div className="text-xs text-indigo-200">{comboToast.descRu}</div>
        </div>
      )}

      {/* Joystick layer, hidden while an overlay needs taps */}
      {overlay.kind === "none" && (
        <div className="absolute inset-0 bottom-0 top-24">
          <Joystick mode={profile.settings.joystickMode} onChange={handleJoystick} onDashTap={handleDash} />
        </div>
      )}

      {overlay.kind === "paused" && (
        <Backdrop>
          <Panel>
            <h2 className="text-xl font-bold text-white">{t("pause", lang)}</h2>
            <MenuButton onClick={togglePause}>{t("resume", lang)}</MenuButton>
            <MenuButton onClick={abandonRun} variant="ghost">
              {t("exitToMenu", lang)}
            </MenuButton>
          </Panel>
        </Backdrop>
      )}

      {overlay.kind === "mutation" && (
        <Backdrop>
          <div className="w-full max-w-sm px-4">
            <h2 className="mb-3 text-center text-lg font-bold text-white">Выбери мутацию</h2>
            <div className="flex flex-col gap-3">
              {overlay.choices.map((c) => (
                <button
                  key={c.id}
                  onClick={() => chooseMutation(c.id)}
                  className={`rounded-2xl border-2 p-3 text-left shadow-lg transition active:scale-95 ${rarityStyle(c.rarity)}`}
                >
                  <div className="flex items-center gap-2 text-white">
                    <span className="text-2xl">{c.icon}</span>
                    <span className="font-semibold">{c.nameRu}</span>
                    <span className="ml-auto rounded-full bg-black/30 px-2 py-0.5 text-[10px] uppercase">{c.rarity}</span>
                  </div>
                  <p className="mt-1 text-xs text-white/80">{c.descRu}</p>
                </button>
              ))}
            </div>
            {!overlay.extraUsed && (
              <button
                disabled={adBusy}
                onClick={requestExtraMutation}
                className="mt-3 w-full rounded-full bg-amber-500/90 py-2 text-sm font-semibold text-black disabled:opacity-50"
              >
                {adBusy ? "..." : "🎬 Доп. вариант (реклама)"}
              </button>
            )}
          </div>
        </Backdrop>
      )}

      {overlay.kind === "revive-offer" && (
        <Backdrop>
          <Panel>
            <h2 className="text-xl font-bold text-rose-300">Слизь повержена</h2>
            <p className="text-sm text-white/70">Продолжить за рекламу?</p>
            <MenuButton onClick={requestRevive} disabled={adBusy}>
              {adBusy ? "..." : `🎬 ${t("watchAdRevive", lang)}`}
            </MenuButton>
            <MenuButton onClick={declineRevive} variant="ghost">
              {t("skip", lang)}
            </MenuButton>
          </Panel>
        </Backdrop>
      )}

      {overlay.kind === "result" && (
        <Backdrop>
          <Panel>
            <h2 className={`text-2xl font-extrabold ${overlay.result === "victory" ? "text-emerald-300" : "text-rose-300"}`}>
              {overlay.result === "victory" ? t("victory", lang) : t("defeat", lang)}
            </h2>
            <div className="w-full space-y-1 rounded-xl bg-black/30 p-3 text-sm text-white/90">
              <div className="flex justify-between"><span>{t("mass", lang)}</span><span>{overlay.summary.massReached}</span></div>
              <div className="flex justify-between"><span>{t("time", lang)}</span><span>{Math.floor(overlay.summary.durationSec / 60)}:{String(overlay.summary.durationSec % 60).padStart(2, "0")}</span></div>
              <div className="flex justify-between"><span>Босс повержен</span><span>{overlay.summary.bossDefeated ? "Да" : "Нет"}</span></div>
              <div className="flex justify-between font-semibold text-amber-300"><span>{t("currencyEarned", lang)}</span><span>+{overlay.currencyEarned}</span></div>
            </div>
            {!overlay.doubled && (
              <MenuButton onClick={requestDoubleReward} disabled={adBusy}>
                {adBusy ? "..." : `🎬 ${t("watchAdDouble", lang)}`}
              </MenuButton>
            )}
            <MenuButton onClick={exitToMenu} variant="ghost">
              {t("exitToMenu", lang)}
            </MenuButton>
          </Panel>
        </Backdrop>
      )}
    </div>
  );
}

function getMutationIcon(mutationId: string) {
  const icons: Record<string, string> = {
    magnet: "🧲", haste: "👟", spikes: "🦔", poison_trail: "☠️", split: "🫧", shield: "🛡️",
    regen: "💚", dash: "💨", vacuum: "🌀", electric: "⚡", freeze: "❄️", camouflage: "🕶️",
  };
  return icons[mutationId] ?? "✨";
}

function rarityStyle(rarity: string) {
  if (rarity === "epic") return "border-fuchsia-400 bg-fuchsia-900/60";
  if (rarity === "rare") return "border-sky-400 bg-sky-900/60";
  return "border-emerald-400 bg-emerald-900/60";
}

function Backdrop({ children }: { children: ReactNode }) {
  return <div className="absolute inset-0 z-20 flex items-center justify-center bg-black/70 backdrop-blur-sm">{children}</div>;
}

function Panel({ children }: { children: ReactNode }) {
  return <div className="flex w-full max-w-xs flex-col items-center gap-3 rounded-3xl bg-slate-900/90 p-6 text-center shadow-2xl">{children}</div>;
}

function MenuButton({
  children,
  onClick,
  variant = "solid",
  disabled,
}: {
  children: ReactNode;
  onClick: () => void;
  variant?: "solid" | "ghost";
  disabled?: boolean;
}) {
  return (
    <button
      onClick={() => {
        soundManager.play("click");
        onClick();
      }}
      disabled={disabled}
      className={`w-full rounded-full py-2.5 text-sm font-semibold transition active:scale-95 disabled:opacity-50 ${
        variant === "solid" ? "bg-emerald-500 text-black" : "bg-white/10 text-white"
      }`}
    >
      {children}
    </button>
  );
}
