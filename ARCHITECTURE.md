# ARCHITECTURE.md

## Why Next.js instead of Godot

This sandbox provides a Next.js (App Router) + PostgreSQL/Drizzle template
and a validation pipeline built around it (`next typegen`, `tsc`, `next
build`, `build_and_start` → `/api/health`). There is no Godot binary,
Android SDK/NDK, emulator, or packaging toolchain available here, and no way
to produce an installable APK/AAB in this sandbox. See `README.md` for the
adaptation rationale.

The implementation below is organized so that **porting to Godot 4 is a
translation exercise, not a redesign**: game data, balance numbers, and
state-machine logic are isolated from rendering/input, mirroring Godot's own
separation of `Resource` data, `Node` scenes, and `Autoload` singletons.

## Current (web) project layout

```
src/
  db/
    schema.ts         Drizzle tables: players, runs, analytics_events,
                       ad_reward_grants (unique runId+slot), purchases
    index.ts           Postgres pool + drizzle client
  lib/game/
    constants.ts        BALANCE table, upgrade defs, mutation unlock costs
    rng.ts               seeded PRNG (mulberry32) for reproducible rolls
    growth.ts            mass<->radius, speed penalty, canAbsorb, HP
    mutations.ts         12 mutation defs + 5 combo defs + weighted rolling
    enemies.ts           8 enemy type defs (FSM behavior tags + stats)
    boss.ts              3-phase boss definition
    economy.ts           run reward + upgrade cost/afford helpers
    save.ts              PlayerProfile type, defaults, sanitize/repair
    ads.ts               reward-slot idempotency + ad-result eligibility
    i18n.ts              ru/en dictionary
    analyticsEvents.ts   the 14 required event names
    engine.ts            the actual real-time game engine (Canvas2D),
                         "use client" — pure game loop + renderer, no React
    sound.ts             Web Audio synthesized SFX manager
    client.ts            device id, analytics POSTs, test ad/IAP adapters
    db.ts                server-only DB access functions ("server-only")
  hooks/useProfile.ts     client hook: fetch/patch the player's profile
  components/game/
    GameApp.tsx           top-level screen state machine
    PlayScreen.tsx         hosts <canvas>, HUD, joystick, all run overlays
    Joystick.tsx            fixed/floating one-thumb virtual joystick
    MenuScreens.tsx         MainMenu, ModeSelect, Upgrades, Collection,
                            Settings, Shop, Privacy
  app/
    page.tsx               renders <GameApp/>
    layout.tsx              metadata/viewport (mobile-first, no zoom)
    api/
      profile/route.ts      GET/POST anonymous device profile
      run/route.ts           POST start/finish a run, computes rewards
      analytics/route.ts      POST one of the 14 analytics events
      ads/reward/route.ts      POST confirm a rewarded-ad grant (idempotent)
      iap/purchase/route.ts    POST sandbox purchase (no_ads, cosmetics)
      iap/restore/route.ts     GET restore purchases
      health/route.ts         unchanged platform health check
tests/                     Vitest unit tests (40 tests, see TEST_REPORT.md)
```

### Separation of concerns (mirrors the brief's requested Godot layout)

| Brief's Godot folder | Web equivalent |
|---|---|
| `resources/` (mutation/enemy/boss data) | `src/lib/game/{mutations,enemies,boss,constants}.ts` |
| `systems/` (economy, save, analytics, ads) | `src/lib/game/{economy,save,ads,analyticsEvents,client,db}.ts` |
| `entities/`, `enemies/`, `bosses/` (behavior) | state handled inside `engine.ts` update loop, keyed by the same data ids |
| `ui/` | `src/components/game/*` |
| `scenes/` (composition) | `GameApp.tsx` screen router + `PlayScreen.tsx` |
| `addons/` (ad/billing plugins) | `src/lib/game/client.ts` test adapters + API routes |
| `tests/` (GUT) | `tests/*.test.ts` (Vitest) |

### Engine internals

`SlimeRushEngine` (`src/lib/game/engine.ts`) owns all simulation state
(player, enemies, pellets, hazards, particles, boss, decorations) and runs
its own `requestAnimationFrame` loop independent of React — React only
polls a cheap `getSnapshot()` every 120ms for the HUD, and renders overlays
(mutation choice / pause / revive / result) driven by callbacks
(`onMutationChoice`, `onGameOver`, etc.). This keeps the hot path
(60 FPS target) free of React re-renders, which is the same reasoning that
would apply to keeping Godot's `_physics_process` free of UI work.

Performance techniques actually implemented (not just claimed):
- **Object pooling-style reuse**: particles are capped (`MAX_PARTICLES`) and
  the oldest is evicted (`shift()`) instead of growing unbounded.
- **Entity caps**: `MAX_ENEMIES`, `MAX_PELLETS` bound simulation cost.
- **Off-screen culling**: rendering skips decorations/pellets/enemies whose
  screen-space position falls outside the viewport + margin.
- **Minimal per-frame allocation**: hot loops mutate existing objects
  in-place rather than creating new ones where practical.
- A true spatial grid (as requested for "nearest target" queries) is not
  needed at the current entity caps (≤36 enemies) and was intentionally not
  added to avoid "architectural complexity for its own sake" (brief rule
  #14); it is called out in `PROGRESS.md` as the first optimization to add
  if enemy counts increase.

### Data flow for meta-progression

1. Client generates a random UUID on first load, stored in
   `localStorage['slime_rush_device_id']` — this is the only "account" the
   anonymous game needs.
2. `useProfile()` fetches/creates a `players` row via `/api/profile`.
3. `PlayScreen` posts `/api/run` with `action:"start"` when a run begins and
   `action:"finish"` when it ends; the server computes the currency reward
   (`calcRunReward`) and the achievement/collection updates, so the client
   cannot forge rewards.
4. Rewarded-ad grants and purchases are **always confirmed server-side**
   (`/api/ads/reward`, `/api/iap/purchase`) and are idempotent via a unique
   `(runId, slot)` database index — verified in `tests/ads.test.ts` and via
   a live duplicate-request smoke test (see `TEST_REPORT.md`).

## Path to a real Godot 4 / Android build

If/when a Godot-capable environment is available, port in this order
(all game data above is already in a Godot-portable shape — JSON/typed
tables that map directly onto `Resource` classes):

1. **Project skeleton**: `project.godot`, `res://scenes`, `res://scripts`,
   `res://systems`, `res://entities`, `res://mutations`, `res://enemies`,
   `res://bosses`, `res://ui`, `res://resources`, `res://shaders`,
   `res://audio`, `res://localization`, `res://tests` (GUT), `res://addons`.
2. Re-express `constants.ts`, `mutations.ts`, `enemies.ts`, `boss.ts` as
   Godot `Resource` (`.tres`)/`class_name` data files — the field names and
   values carry over directly.
3. Re-implement `engine.ts`'s update loop as a `CharacterBody2D` player +
   `Area2D`-based absorption checks + a `Node2D` per enemy type driven by a
   `StateMachine` autoload (matches the behavior tags already defined per
   enemy).
4. Re-implement `canvas` rendering as `Sprite2D`/`AnimatedSprite2D` +
   `GPUParticles2D` + a `CanvasItem` shader for the slime body
   (squash/stretch + Fresnel glow instead of manual `ctx.scale`).
5. Replace the synthesized Web Audio SFX with short original recordings or
   procedurally-generated `AudioStreamWAV` assets using the same event list.
6. Replace `src/lib/game/client.ts` test ad/IAP adapters with a maintained
   Godot Android plugin for Google Mobile Ads (rewarded) and the Google
   Play Billing plugin, keeping the same interface
   (`playTestRewardedAd`/`purchaseTestProduct` signatures) so the rest of
   the game logic is untouched.
7. Local save becomes a Godot `ConfigFile`/JSON in `user://`, reusing the
   exact `sanitizeProfile` repair logic ported to GDScript.
8. Android export: application id, icon, splash, keystore, target SDK per
   current Play requirements — tracked as open items in
   `RELEASE_CHECKLIST.md`.

This is explicitly flagged as **not completed** in this session — it
requires a Godot-enabled environment, Android SDK, and (for store
submission) a real Google Play developer account, none of which are
available here.
