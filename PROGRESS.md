# PROGRESS.md

## Current stage

Stage 6 (QA & release) — core game, commercial scaffolding, and
documentation are complete for the web-adapted implementation. Native
Android packaging is blocked on tooling not present in this sandbox (see
below).

## Implemented this session

- Full database schema: `players`, `runs`, `analytics_events`,
  `ad_reward_grants` (idempotent via unique `(runId, slot)`), `purchases`.
- Pure, unit-tested game-logic modules: growth/absorption math, 12
  mutations + 5 combos with weighted random rolling, 8 enemy types, 3-phase
  boss, economy (run rewards + upgrade costs), save sanitization/corrupted
  save recovery, rewarded-ad idempotency, i18n (ru/en), analytics event
  constants.
- A real-time Canvas2D game engine (`SlimeRushEngine`) implementing the
  full run loop: movement/inertia, mutation passive/active effects, enemy
  AI, hazards, particles, evolution gating, boss phases/telegraphs, win/
  lose conditions, revive-after-ad.
- Full UI: Main menu, Mode select, Play screen (HUD, joystick, mutation
  choice, pause, revive offer, result screen with double-reward ad),
  Upgrades (stats + mutation unlocks), Collection, Settings, Shop
  (sandbox IAP), Privacy/About.
- API routes: profile get/patch, run start/finish (server-computed
  rewards + achievements + collection updates), analytics logging,
  rewarded-ad grant (idempotent), IAP purchase/restore (sandbox).
- Synthesized Web Audio SFX (no external audio assets); music off by
  default per the brief.
- 40 Vitest unit tests, all passing. Type-check, `next typegen`, and
  production build all passing. `build_and_start` succeeded twice. Live
  curl-based integration smoke test of every API route passed, including a
  verified duplicate-ad-reward rejection.

## Known issues / explicitly not done

1. **No native Godot/Android project exists.** This sandbox has no Godot
   engine, Android SDK, or emulator. See `README.md`/`ARCHITECTURE.md` for
   the documented porting plan and why a web reimplementation was chosen
   instead of stopping at documentation-only.
2. **No forced first-run tutorial sequence.** `tutorial_started`/
   `tutorial_completed` analytics events are defined and ready to fire but
   nothing currently triggers them — Practice mode is the de facto
   tutorial today.
3. **No spatial-partitioning grid** for nearest-neighbor enemy queries —
   not needed yet at the current entity cap (≤36 enemies simultaneously);
   flagged as the first optimization to add if enemy density increases.
4. **No interactive/browser-automated gameplay test** (e.g. Playwright)
   was run in this session — no such tool was available. Game logic was
   verified via unit tests + a full API-level integration smoke test that
   exercises the same server-side effects a real run would trigger.
5. **Real ad/IAP SDKs, real device QA, Play Console submission** are all
   blocked on resources not available here (no Android device, no AdMob/
   Play Console account, no Godot toolchain). Full list in
   `RELEASE_CHECKLIST.md`.

## Next steps for a future session

1. If a Godot-capable environment becomes available, start the port using
   the step-by-step plan in `ARCHITECTURE.md` — the data (mutations,
   enemies, boss, balance constants) can be translated almost verbatim.
2. Add a short guided first-run tutorial overlay (3–5 steps: move, absorb,
   evolve, mutation choice) firing the existing analytics events.
3. Add Playwright-based interactive UI tests once a browser automation tool
   is available, covering: first launch, a full Practice run, a full
   Classic run through boss defeat, and a defeat→revive→retry flow.
4. When real AdMob/Play Billing credentials exist, swap the adapters in
   `src/lib/game/client.ts` per the plan in `MONETIZATION.md`, keeping the
   existing idempotent grant contract unchanged.
5. Add a spatial grid in `engine.ts` if enemy/pellet counts are increased
   beyond current caps.

## Blocking dependencies (cannot be resolved by an autonomous agent alone)

- Godot 4 engine + Android SDK/NDK + export templates (not installable in
  this sandbox).
- A real Android device or emulator for hardware QA and FPS profiling.
- Google Play Console developer account + AdMob account (require real
  registration, payment, and identity verification by the owner).
- A release keystore, generated and stored securely by the owner outside
  of version control.
- Legal review/sign-off on the privacy policy and store listing.
- Explicit owner approval before any publish/release action.
