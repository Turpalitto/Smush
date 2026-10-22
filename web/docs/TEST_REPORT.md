# TEST_REPORT.md

Honest record of what was actually executed in this session, and what was
not (and why). No claim here is made without having run the corresponding
command.

## Automated unit tests (executed)

```
npx vitest run
```

Result: **5 test files, 40 tests, all passing.**

| File | Tests | Covers |
|---|---|---|
| `tests/growth.test.ts` | 13 | mass→radius monotonicity & cap, speed penalty floor, **absorption thresholds** (normal/armored/mutation-gated), evolution stage calculation |
| `tests/mutations.test.ts` | 8 | **mutation rolling** (count, pool restriction, max-level exclusion, determinism with a seeded RNG), **level restrictions**, **5+ combos exist and are only active when both required mutations are owned** |
| `tests/economy.test.ts` | 7 | **run reward calculation** (abandoned=0, defeat<victory, boss bonus, non-negative), upgrade cost growth and affordability |
| `tests/save.test.ts` | 7 | default profile shape, round-trip save/load, **corrupted-save recovery** (null/undefined/garbage/negative numbers/wrong-typed arrays all repaired without throwing) |
| `tests/ads.test.ts` | 5 | **rewarded-ad reward idempotency** (first grant allowed, duplicate blocked, different slot/run allowed), ad completion eligibility gating |

Re-run after every source change in this session; last run was clean.

## Type-checking & build (executed)

```
npx next typegen        # ✓ passed
npm exec tsc -- --noEmit --pretty false   # ✓ passed, 0 errors
npm run build            # ✓ passed, all routes compiled
```

`build_and_start` (platform tool) was run **twice** in this session and
succeeded both times, including the `/api/health` check against the running
production server.

## Live integration smoke test (executed against the running server)

Using `curl` against the started app, the following were verified to
actually work end-to-end (not just unit-tested in isolation):

- `GET /api/health` → `{"ok":true}`
- `GET /` → HTTP 200
- `GET /api/profile?playerId=...` → creates and returns a fresh profile
- `POST /api/run {action:"start"}` → `{"ok":true}`
- `POST /api/run {action:"finish", result:"victory", bossDefeated:true,...}`
  → returns an updated profile with `currency` increased by the expected
  server-computed amount, `totalWins`/`totalBossKills` incremented,
  `discoveredCreatures`/`discoveredForms`/`achievements` updated
- `POST /api/ads/reward {slot:"double"}` (first call) → `{"granted":true,...}`
- `POST /api/ads/reward` with the **same** `runId`+`slot` again → `{"granted":false,"reason":"already_granted"}` — confirms the anti-double-grant DB constraint works live, not just in the unit test
- `POST /api/iap/purchase {productId:"no_ads"}` → profile now has `noAds:true`
- `GET /api/iap/restore?playerId=...` → returns `["no_ads"]`
- `POST /api/analytics` → `{"ok":true}`

## Manual gameplay verification

The game engine and UI were built and statically verified (types, build),
and the API-level game-loop effects (mass growth, boss defeat, mutation
selection, reward calculation) were exercised through the integration smoke
test above by simulating a full run's server calls. However, **this session
did not perform interactive manual playtesting with a pointer/touch device
inside a real browser** (no browser automation tool was available in this
toolset). This is explicitly called out as not yet verified:

- Visual correctness of the canvas renderer (slime squash/stretch, particle
  bursts, boss telegraph circles) — code-reviewed but not visually captured.
- Joystick drag ergonomics on an actual touchscreen.
- Full 6-minute classic run played interactively start-to-finish by a human
  or automated UI test.

**Recommended next step for a future session**: add a Playwright (or
similar) browser test that opens `/`, starts a Practice run, drives the
joystick via synthetic pointer events, and asserts the HUD mass value
increases and a mutation-choice overlay appears — this was not done here
because no browser automation tool was available in this toolset.

## Explicitly NOT executed (requires resources unavailable in this sandbox)

Per the brief's own instruction ("do not claim tests passed without running
them", "flag what needs a real device/account"), the following from the
original QA checklist require infrastructure not present here and are
**not** claimed as done:

- GUT (Godot) test suite — N/A, there is no Godot project in this
  implementation (see `README.md`/`ARCHITECTURE.md` for why).
- Real Android device testing (60/90/120Hz behavior, real FPS profiling on
  a budget device). No FPS numbers are claimed for any physical Android
  hardware.
- Real Google Mobile Ads / AdMob rewarded-ad integration test.
- Real Google Play Billing purchase/restore test with a sandbox tester
  account.
- App backgrounding/resume, OS-level interruption (phone call), and
  screen-rotation testing in a native Android shell.
- Cross-device aspect-ratio verification beyond responsive CSS review.

These are tracked as open items in `RELEASE_CHECKLIST.md` and `PROGRESS.md`.
