"use client";

import type { ReactNode } from "react";

import { useState } from "react";
import type { PlayerProfile } from "@/lib/game/save";
import { UPGRADE_DEFS, MUTATION_UNLOCK_COST } from "@/lib/game/constants";
import { upgradeCost, canAffordUpgrade } from "@/lib/game/economy";
import { MUTATIONS } from "@/lib/game/mutations";
import { ENEMY_TYPES } from "@/lib/game/enemies";
import { BOSS_DEF } from "@/lib/game/boss";
import { soundManager } from "@/lib/game/sound";
import { purchaseTestProduct, restorePurchases } from "@/lib/game/client";

function click() {
  soundManager.play("click");
}

export function Shell({ title, onBack, children }: { title: string; onBack?: () => void; children: ReactNode }) {
  return (
    <div className="min-h-dvh bg-gradient-to-b from-emerald-950 via-slate-950 to-slate-950 px-4 pb-10 pt-6 text-white">
      <div className="mx-auto flex max-w-md items-center gap-3 pb-4">
        {onBack && (
          <button
            onClick={() => {
              click();
              onBack();
            }}
            className="grid h-9 w-9 place-items-center rounded-full bg-white/10 active:scale-95"
          >
            ←
          </button>
        )}
        <h1 className="text-lg font-bold">{title}</h1>
      </div>
      <div className="mx-auto max-w-md">{children}</div>
    </div>
  );
}

export function BigButton({
  children,
  onClick,
  subtitle,
  emoji,
}: {
  children: ReactNode;
  onClick: () => void;
  subtitle?: string;
  emoji?: string;
}) {
  return (
    <button
      onClick={() => {
        click();
        onClick();
      }}
      className="flex w-full items-center gap-3 rounded-2xl bg-white/10 p-4 text-left shadow-lg transition active:scale-95 hover:bg-white/15"
    >
      {emoji && <span className="text-2xl">{emoji}</span>}
      <div>
        <div className="font-semibold">{children}</div>
        {subtitle && <div className="text-xs text-white/60">{subtitle}</div>}
      </div>
    </button>
  );
}

export function MainMenu({
  profile,
  onNavigate,
}: {
  profile: PlayerProfile;
  onNavigate: (screen: "mode-select" | "upgrades" | "collection" | "shop" | "settings" | "privacy") => void;
}) {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-between bg-gradient-to-b from-emerald-900 via-emerald-950 to-slate-950 px-6 py-10 text-white">
      <div className="w-full max-w-sm text-center">
        <div className="text-6xl">🟢</div>
        <h1 className="mt-3 text-3xl font-extrabold tracking-tight">SLIME RUSH</h1>
        <p className="text-emerald-300">: EVOLUTION</p>
        <div className="mt-4 inline-flex items-center gap-2 rounded-full bg-black/30 px-4 py-1.5 text-sm">
          <span>💎</span>
          <span>{profile.currency}</span>
        </div>
      </div>

      <div className="flex w-full max-w-sm flex-col gap-3">
        <BigButton emoji="▶️" onClick={() => onNavigate("mode-select")}>Играть</BigButton>
        <BigButton emoji="⬆️" onClick={() => onNavigate("upgrades")} subtitle="Прокачка и мутации">Улучшения</BigButton>
        <BigButton emoji="📖" onClick={() => onNavigate("collection")} subtitle="Существа и формы">Коллекция</BigButton>
        <BigButton emoji="🛒" onClick={() => onNavigate("shop")}>Магазин</BigButton>
        <div className="grid grid-cols-2 gap-3">
          <BigButton emoji="⚙️" onClick={() => onNavigate("settings")}>Настройки</BigButton>
          <BigButton emoji="🔒" onClick={() => onNavigate("privacy")}>Конфиденц.</BigButton>
        </div>
      </div>

      <p className="text-center text-[11px] text-white/40">v0.1.0 · Android target · офлайн-геймплей</p>
    </div>
  );
}

export function ModeSelect({ onBack, onStart }: { onBack: () => void; onStart: (mode: "classic" | "practice") => void }) {
  return (
    <Shell title="Выбор режима" onBack={onBack}>
      <div className="flex flex-col gap-4">
        <button
          onClick={() => {
            click();
            onStart("classic");
          }}
          className="rounded-3xl bg-gradient-to-br from-emerald-600 to-emerald-900 p-5 text-left shadow-xl active:scale-95"
        >
          <div className="text-xl font-bold">🌲 Классический забег</div>
          <p className="mt-1 text-sm text-white/80">
            6 минут, Зачарованный лес, мутации, опасные существа и финальная битва с Древним стражем леса.
          </p>
        </button>
        <button
          onClick={() => {
            click();
            onStart("practice");
          }}
          className="rounded-3xl bg-gradient-to-br from-sky-700 to-sky-950 p-5 text-left shadow-xl active:scale-95"
        >
          <div className="text-xl font-bold">🧪 Тренировка</div>
          <p className="mt-1 text-sm text-white/80">
            3 минуты без босса и наград — удобно, чтобы опробовать мутации и управление.
          </p>
        </button>
      </div>
    </Shell>
  );
}

export function UpgradesScreen({
  profile,
  onBack,
  onBuyUpgrade,
  onUnlockMutation,
}: {
  profile: PlayerProfile;
  onBack: () => void;
  onBuyUpgrade: (key: string) => void;
  onUnlockMutation: (id: string) => void;
}) {
  const [tab, setTab] = useState<"stats" | "mutations">("stats");
  return (
    <Shell title="Улучшения" onBack={onBack}>
      <div className="mb-2 flex items-center justify-end gap-1 text-sm text-amber-300">💎 {profile.currency}</div>
      <div className="mb-4 flex gap-2 rounded-full bg-white/10 p-1">
        {(["stats", "mutations"] as const).map((key) => (
          <button
            key={key}
            onClick={() => {
              click();
              setTab(key);
            }}
            className={`flex-1 rounded-full py-2 text-sm font-semibold ${tab === key ? "bg-emerald-500 text-black" : "text-white/70"}`}
          >
            {key === "stats" ? "Характеристики" : "Мутации"}
          </button>
        ))}
      </div>

      {tab === "stats" && (
        <div className="flex flex-col gap-3">
          {UPGRADE_DEFS.map((def) => {
            const level = profile.upgrades[def.key] ?? 0;
            const cost = upgradeCost(def.key, level);
            const maxed = level >= def.maxLevel;
            const afford = canAffordUpgrade(profile.currency, def.key, level);
            return (
              <div key={def.key} className="rounded-2xl bg-white/10 p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-semibold">{def.nameRu}</div>
                    <div className="text-xs text-white/60">{def.descRu}</div>
                  </div>
                  <div className="text-sm">{level}/{def.maxLevel}</div>
                </div>
                <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-black/30">
                  <div className="h-full bg-emerald-400" style={{ width: `${(level / def.maxLevel) * 100}%` }} />
                </div>
                <button
                  disabled={maxed || !afford}
                  onClick={() => {
                    click();
                    onBuyUpgrade(def.key);
                  }}
                  className="mt-3 w-full rounded-full bg-emerald-500 py-2 text-sm font-semibold text-black disabled:bg-white/10 disabled:text-white/40"
                >
                  {maxed ? "Максимум" : `Улучшить · 💎 ${cost}`}
                </button>
              </div>
            );
          })}
        </div>
      )}

      {tab === "mutations" && (
        <div className="grid grid-cols-1 gap-3">
          {MUTATIONS.map((m) => {
            const unlocked = profile.unlockedMutations.includes(m.id);
            const cost = MUTATION_UNLOCK_COST[m.id];
            return (
              <div key={m.id} className="flex items-center justify-between rounded-2xl bg-white/10 p-3">
                <div className="flex items-center gap-2">
                  <span className="text-2xl">{m.icon}</span>
                  <div>
                    <div className="text-sm font-semibold">{m.nameRu}</div>
                    <div className="text-xs text-white/60">{m.descRu}</div>
                  </div>
                </div>
                {unlocked ? (
                  <span className="rounded-full bg-emerald-500/20 px-2 py-1 text-xs text-emerald-300">Открыто</span>
                ) : (
                  <button
                    disabled={profile.currency < (cost ?? 0)}
                    onClick={() => {
                      click();
                      onUnlockMutation(m.id);
                    }}
                    className="rounded-full bg-amber-500 px-3 py-1.5 text-xs font-semibold text-black disabled:bg-white/10 disabled:text-white/40"
                  >
                    💎 {cost}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </Shell>
  );
}

export function CollectionScreen({ profile, onBack }: { profile: PlayerProfile; onBack: () => void }) {
  return (
    <Shell title="Коллекция" onBack={onBack}>
      <h2 className="mb-2 text-sm font-semibold text-white/70">Существа</h2>
      <div className="mb-6 grid grid-cols-2 gap-3">
        {ENEMY_TYPES.map((e) => {
          const found = profile.discoveredCreatures.includes(e.id);
          return (
            <div key={e.id} className={`rounded-2xl p-3 text-center ${found ? "bg-white/10" : "bg-white/5 opacity-50"}`}>
              <div className="text-3xl">{found ? "🟢" : "❔"}</div>
              <div className="mt-1 text-xs font-semibold">{found ? e.nameRu : "???"}</div>
            </div>
          );
        })}
        <div className={`rounded-2xl p-3 text-center ${profile.totalBossKills > 0 ? "bg-purple-500/20" : "bg-white/5 opacity-50"}`}>
          <div className="text-3xl">{profile.totalBossKills > 0 ? "🐉" : "❔"}</div>
          <div className="mt-1 text-xs font-semibold">{profile.totalBossKills > 0 ? BOSS_DEF.nameRu : "???"}</div>
        </div>
      </div>

      <h2 className="mb-2 text-sm font-semibold text-white/70">Формы слизи</h2>
      <div className="grid grid-cols-4 gap-2">
        {Array.from({ length: 8 }, (_, i) => {
          const found = profile.discoveredForms.includes(i);
          return (
            <div key={i} className={`grid aspect-square place-items-center rounded-xl text-xl ${found ? "bg-emerald-500/20" : "bg-white/5 opacity-40"}`}>
              {found ? "🟢" : "?"}
            </div>
          );
        })}
      </div>

      <h2 className="mb-2 mt-6 text-sm font-semibold text-white/70">Достижения</h2>
      <div className="flex flex-wrap gap-2">
        {profile.achievements.length === 0 && <p className="text-xs text-white/50">Пока нет достижений</p>}
        {profile.achievements.map((a) => (
          <span key={a} className="rounded-full bg-amber-500/20 px-3 py-1 text-xs text-amber-300">🏆 {a}</span>
        ))}
      </div>
    </Shell>
  );
}

export function SettingsScreen({
  profile,
  onBack,
  onChange,
  onReset,
}: {
  profile: PlayerProfile;
  onBack: () => void;
  onChange: (settings: PlayerProfile["settings"]) => void;
  onReset: () => void;
}) {
  const s = profile.settings;
  return (
    <Shell title="Настройки" onBack={onBack}>
      <div className="flex flex-col gap-4">
        <Row label="Джойстик">
          <div className="flex gap-2">
            {(["floating", "fixed"] as const).map((mode) => (
              <button
                key={mode}
                onClick={() => onChange({ ...s, joystickMode: mode })}
                className={`rounded-full px-3 py-1.5 text-xs font-semibold ${s.joystickMode === mode ? "bg-emerald-500 text-black" : "bg-white/10"}`}
              >
                {mode === "floating" ? "Плавающий" : "Фиксированный"}
              </button>
            ))}
          </div>
        </Row>
        <Row label="Авто-поглощение">
          <Toggle checked={s.autoAbsorb} onChange={(v) => onChange({ ...s, autoAbsorb: v })} />
        </Row>
        <Row label={`Громкость эффектов: ${Math.round(s.sfxVolume * 100)}%`}>
          <input type="range" min={0} max={1} step={0.05} value={s.sfxVolume} onChange={(e) => onChange({ ...s, sfxVolume: Number(e.target.value) })} className="w-full" />
        </Row>
        <Row label={`Громкость музыки: ${Math.round(s.musicVolume * 100)}% (музыка не включена в эту версию)`}>
          <input type="range" min={0} max={1} step={0.05} value={s.musicVolume} onChange={(e) => onChange({ ...s, musicVolume: Number(e.target.value) })} className="w-full" />
        </Row>
        <Row label="Язык / Language">
          <div className="flex gap-2">
            {(["ru", "en"] as const).map((lng) => (
              <button
                key={lng}
                onClick={() => onChange({ ...s, language: lng })}
                className={`rounded-full px-3 py-1.5 text-xs font-semibold ${s.language === lng ? "bg-emerald-500 text-black" : "bg-white/10"}`}
              >
                {lng.toUpperCase()}
              </button>
            ))}
          </div>
        </Row>
        <button
          onClick={() => {
            click();
            if (window.confirm("Сбросить весь прогресс?")) onReset();
          }}
          className="mt-4 rounded-full bg-rose-600/80 py-2.5 text-sm font-semibold"
        >
          Сбросить прогресс
        </button>
      </div>
    </Shell>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="rounded-2xl bg-white/10 p-3">
      <div className="mb-2 text-sm text-white/80">{label}</div>
      {children}
    </div>
  );
}

function Toggle({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      onClick={() => onChange(!checked)}
      className={`h-7 w-12 rounded-full transition ${checked ? "bg-emerald-500" : "bg-white/20"}`}
    >
      <span className={`block h-6 w-6 translate-y-0.5 rounded-full bg-white transition ${checked ? "translate-x-5" : "translate-x-0.5"}`} />
    </button>
  );
}

export function ShopScreen({ profile, onBack, onProfileUpdate }: { profile: PlayerProfile; onBack: () => void; onProfileUpdate: (p: PlayerProfile) => void }) {
  const [busy, setBusy] = useState<string | null>(null);

  const buy = async (productId: string) => {
    setBusy(productId);
    const data = await purchaseTestProduct(productId);
    if (data.profile) onProfileUpdate(data.profile);
    setBusy(null);
  };

  const restore = async () => {
    setBusy("restore");
    await restorePurchases();
    setBusy(null);
  };

  const cosmetics = [
    { id: "cosmetic_crystal", nameRu: "Кристальная слизь", emoji: "💎" },
    { id: "cosmetic_shadow", nameRu: "Теневая слизь", emoji: "🌑" },
    { id: "cosmetic_golden", nameRu: "Золотая слизь", emoji: "✨" },
  ];

  return (
    <Shell title="Магазин" onBack={onBack}>
      <div className="mb-4 rounded-xl bg-amber-500/15 p-3 text-xs text-amber-200">
        ⚠️ Тестовый режим покупок: реальный Google Play Billing не подключён в этой песочнице. Покупки ниже — симуляция для проверки логики.
      </div>

      <div className="mb-4 rounded-2xl bg-white/10 p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="font-semibold">🚫 Без рекламы</div>
            <p className="mt-1 text-xs text-white/60">
              Убирает баннер на главном экране и экране результатов. Добровольная реклама за награды (возрождение,
              удвоение, доп. мутация) остаётся доступной по желанию — это бонус, а не навязанная реклама.
            </p>
          </div>
        </div>
        <button
          disabled={profile.noAds || busy === "no_ads"}
          onClick={() => buy("no_ads")}
          className="mt-3 w-full rounded-full bg-emerald-500 py-2 text-sm font-semibold text-black disabled:bg-white/10 disabled:text-white/40"
        >
          {profile.noAds ? "Куплено" : busy === "no_ads" ? "..." : "199 ₽ (симуляция)"}
        </button>
      </div>

      {!profile.noAds && (
        <div className="mb-4 rounded-xl bg-black/30 p-3 text-center text-[11px] text-white/50">рекламный баннер (заглушка)</div>
      )}

      <h2 className="mb-2 text-sm font-semibold text-white/70">Косметика</h2>
      <div className="grid grid-cols-1 gap-3">
        {cosmetics.map((c) => {
          const owned = profile.ownedCosmetics.includes(c.id.replace("cosmetic_", ""));
          return (
            <div key={c.id} className="flex items-center justify-between rounded-2xl bg-white/10 p-3">
              <div className="flex items-center gap-2">
                <span className="text-2xl">{c.emoji}</span>
                <span className="text-sm font-semibold">{c.nameRu}</span>
              </div>
              <button
                disabled={owned || busy === c.id}
                onClick={() => buy(c.id)}
                className="rounded-full bg-amber-500 px-3 py-1.5 text-xs font-semibold text-black disabled:bg-white/10 disabled:text-white/40"
              >
                {owned ? "Куплено" : busy === c.id ? "..." : "99 ₽"}
              </button>
            </div>
          );
        })}
      </div>

      <button onClick={restore} disabled={busy === "restore"} className="mt-6 w-full rounded-full bg-white/10 py-2.5 text-sm">
        {busy === "restore" ? "..." : "Восстановить покупки"}
      </button>
    </Shell>
  );
}

export function PrivacyScreen({ onBack }: { onBack: () => void }) {
  return (
    <Shell title="Конфиденциальность" onBack={onBack}>
      <div className="space-y-3 text-sm leading-relaxed text-white/80">
        <p>
          SLIME RUSH: EVOLUTION работает офлайн. Игра хранит анонимный идентификатор устройства, чтобы сохранять
          прогресс (валюту, улучшения, коллекцию). Мы не собираем имя, email, телефон или точные геоданные.
        </p>
        <p>
          При наличии согласия пользователя игра может отправлять обезличенные события аналитики (например, «забег
          начат», «мутация выбрана», «просмотр рекламы за награду»), чтобы улучшать баланс и удержание. События не
          содержат персональных данных.
        </p>
        <p>
          Добровольная реклама за награду и внутриигровые покупки обрабатываются через песочничные тестовые адаптеры в
          этой сборке (см. MONETIZATION.md). В продакшн-версии для Android будут использоваться Google Mobile Ads SDK
          и Google Play Billing в соответствии с их политиками.
        </p>
        <p>Это черновик политики конфиденциальности и требует юридической проверки перед публикацией в Google Play.</p>
        <p className="text-white/50">Версия приложения: 0.1.0 (прототип релизного кандидата)</p>
      </div>
    </Shell>
  );
}
