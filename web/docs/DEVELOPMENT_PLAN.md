# DEVELOPMENT_PLAN.md

Staged plan as requested by the brief (Stage 0 → 6), with actual status in
this web-adapted implementation (see `README.md` for why it's web, not
Godot).

## Stage 0 — Environment audit ✅ Done

- Repository found to be a clean Next.js 16 + PostgreSQL/Drizzle template,
  no Godot/Android tooling present or installable in this sandbox.
- Decision recorded: implement the full game design as a browser game
  inside the given stack, architected for a later Godot/Android port.
- Constraints documented in `README.md`/`ARCHITECTURE.md`.

## Stage 1 — Core loop ✅ Done

- One-thumb joystick (fixed/floating), inertia-based movement, camera
  follow, bounded arena, non-linear mass→size growth, non-"bigger always
  wins" absorption rules, basic collisions. Fully playable prototype.

## Stage 2 — Evolution ✅ Done

- 12 mutations (8 locked/unlocked split), weighted random 3-choice picks at
  8 mass thresholds, 5 data-driven combos, mutation-specific visuals on the
  slime body, balance constants centralized and unit-tested.

## Stage 3 — Content ✅ Done

- Enchanted Forest biome (procedurally scattered decorations), 8 enemy
  types with distinct FSM behaviors, 3-phase boss with telegraphed attacks,
  Classic/Practice run modes, win/lose/pause/restart, meta-progression
  (currency, upgrades, mutation unlocks, collection, achievements).

## Stage 4 — Polish ✅ Done (web-appropriate scope)

- Canvas-rendered slime with squash/stretch, glowing core, eyes, mutation
  overlays, particle bursts, telegraphed boss attacks, HUD (mass/HP/time/
  evolution bar/boss bar), synthesized SFX (no licensed/third-party audio),
  Russian-first UI with an English-ready i18n layer, mobile-first responsive
  layout with `touch-action:none`/no-zoom viewport.
- Not done: a dedicated interactive tutorial flow (the brief's
  `tutorial_started`/`tutorial_completed` analytics events exist and are
  wired for future use, but there is no forced first-run tutorial sequence
  yet — Practice mode currently serves as the de facto tutorial). Flagged in
  `PROGRESS.md` as the top "nice to have" follow-up.

## Stage 5 — Commercial features ✅ Done (as test adapters)

- Shop (No Ads + 3 cosmetics), rewarded-ad flows (revive/double/extra
  mutation) with server-confirmed, idempotent grants, all 14 analytics
  events, privacy screen + draft policy. Clearly labeled as sandbox/test —
  see `MONETIZATION.md` for the real-SDK integration plan.

## Stage 6 — QA & release ⚠️ Partially done / blocked

- Done: 40 automated unit tests, type-check, production build,
  `build_and_start` + `/api/health`, and a live API integration smoke test
  (see `TEST_REPORT.md`).
- Blocked (needs resources unavailable here): Godot/Android export, real
  device QA, real ad/billing sandbox testing, Play Console submission
  materials finalization. Full list in `RELEASE_CHECKLIST.md`.

## Summary

Every mechanic from the brief is implemented and verified to the extent
possible without Godot/Android tooling or a real device. The remaining work
is almost entirely **porting + platform/account work**, not game design or
core engineering — tracked explicitly in `ARCHITECTURE.md` and
`RELEASE_CHECKLIST.md` so a future session (ideally with Godot/Android
access) can continue directly from here.
