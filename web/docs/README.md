# SLIME RUSH: EVOLUTION

A top-down 2D "grow by absorbing" game about a small slime that eats
creatures and objects, mutates, and eventually fights the **Ancient Forest
Guardian**. Designed as a short (5–8 minute) mobile session game with a
mutation-driven evolution system, honest rewarded-ad monetization, and a
local/offline-first meta-progression loop.

## ⚠️ Important: platform adaptation notice

The master brief asked for a **Godot 4 / Android** game. This sandbox is a
**Next.js + PostgreSQL (Drizzle ORM) web application template** — there is no
Godot engine, no Android SDK/NDK, no emulator, and no app-store tooling
available in this environment, and the platform's own build/validation
pipeline (`next typegen`, `tsc`, `next build`, `build_and_start` →
`/api/health`) is specific to Next.js.

Rather than deliver only design documents or non-functional placeholders, we
made a deliberate, documented engineering decision:

> **Re-implement the full game design as a real, playable browser game**
> (Canvas2D + TypeScript game engine) inside this Next.js app, with the
> PostgreSQL database powering meta-progression, analytics, and
> monetization bookkeeping — while keeping every subsystem architected so it
> maps 1:1 onto the original Godot/Android plan (same mutation data, same
> enemy/boss state machines, same monetization rules, same analytics
> events). See `ARCHITECTURE.md` for the mapping table and the concrete
> steps required to port this to Godot/Android for a real Play Store release.

This is a fully working, commercially-structured product within the
constraints of the sandbox — not a prototype or a stub. Every mechanic listed
in the brief (growth, absorption rules, 12 mutations, 5 combos, 8 enemy
types, a 3-phase boss, runs, meta-progression, rewarded ads, IAP, analytics,
settings, collection, etc.) is implemented and testable today by opening the
app.

## What's implemented

- **Core loop**: one-thumb virtual joystick (fixed/floating), inertia-based
  movement, non-linear mass→size curve, speed penalty at high mass,
  absorption rules that are *not* pure "bigger wins" (armor, mutation gates).
- **Evolution**: 8 mass thresholds, 3-choice mutation picks, 12 mutations (6
  are behavior-changing, not just stat buffs), 5 data-driven combos.
- **World**: procedurally scattered "Enchanted Forest" biome (mushrooms,
  crystals, rocks, flowers), bounded arena, pellet respawn, object pooling
  for particles.
- **Enemies**: 8 creature types, each with a distinct finite-state behavior
  (passive / flee / erratic / armored / hazard-dropping / ambush / ranged /
  hunter).
- **Boss**: "Ancient Forest Guardian" with 3 phases (pursuit → summons →
  enrage), telegraphed AoE slam attacks, offense gated by mutation choice.
- **Runs**: Classic (6 min, boss) and Practice (3 min, no rewards) modes,
  win/lose/pause/restart, results screen, one voluntary rewarded revive per
  run, rewarded "double reward", rewarded "extra mutation option".
- **Meta-progression**: currency, 3 permanent upgrade tracks, 4 mutations
  unlockable with currency, creature/forms collection, achievements — all
  persisted server-side (PostgreSQL) keyed by an anonymous device id.
- **Sound**: every SFX is synthesized at runtime via the Web Audio API (no
  third-party audio assets, zero licensing risk). Music is off by default,
  as required by the brief.
- **Monetization**: rewarded-ad **test adapter** and Google-Play-Billing
  **test adapter**, both server-confirmed and idempotent (anti-double-grant
  via a unique DB constraint). Clearly labeled as sandbox/test in the UI —
  see `MONETIZATION.md`.
- **Analytics**: all 14 events from the brief, logged to Postgres.
- **Automated tests**: 40 Vitest unit tests covering mass/growth math,
  absorption thresholds, mutation rolls & combos, level caps, run rewards,
  save/load + corrupted-save recovery, and rewarded-ad idempotency.

## Running locally

```bash
npm install
npx drizzle-kit push   # applies schema to DATABASE_URL
npm run dev
```

Open the printed URL on a phone or in a narrow desktop window (the UI is
designed mobile-first, portrait).

## Testing

```bash
npx vitest run           # 40 unit tests, see TEST_REPORT.md
npx next typegen
npm exec tsc -- --noEmit
npm run build
```

## Documentation map

- `GAME_DESIGN.md` — full design: mutations, combos, enemies, boss, economy.
- `ARCHITECTURE.md` — code layout + the Godot/Android porting plan.
- `MONETIZATION.md` — ad/IAP rules, what "No Ads" disables, test vs. prod.
- `TEST_REPORT.md` — what was actually executed and the results.
- `RELEASE_CHECKLIST.md` — Android release checklist + manual/blocked items.
- `DEVELOPMENT_PLAN.md` — staged plan (as requested in the brief) + status.
- `PROGRESS.md` — current state, open issues, next steps for a future agent.
