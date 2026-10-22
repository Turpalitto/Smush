# MONETIZATION.md

## Status: TEST adapters, not production ad/billing SDKs

There is no Android/Google Mobile Ads SDK, no AdMob account, and no Google
Play Console/Billing account configured in this sandbox. Every ad and
purchase flow described below is implemented with a **test adapter**
(`src/lib/game/client.ts`) that:

- Mimics the real callback shape of a rewarded-ad SDK
  (`completed: true/false`, with `reason` like `no_fill` / `closed_early`),
  including an occasional simulated no-fill so the "ad unavailable → game
  continues normally" path is exercised.
- Always confirms the reward **server-side** (`/api/ads/reward`,
  `/api/iap/purchase`) — the client never grants currency/entitlements by
  itself, matching "reward only after SDK-confirmed success".
- Is idempotent: a unique `(runId, slot)` database constraint
  (`ad_reward_grants`) guarantees a reward slot can only be granted once,
  even under client retries or multiple taps — verified by
  `tests/ads.test.ts` and a live duplicate-request check (`TEST_REPORT.md`).

**No fake/fraudulent ad impressions are shown as if they were real** — the
UI explicitly labels the shop as a sandbox ("⚠️ Тестовый режим покупок...")
and rewarded-ad buttons show a "🎬" film icon with a visible 1.4s simulated
playback delay rather than pretending to be a real ad network.

## Rewarded ads (voluntary, never forced)

Three reward slots, each grantable **at most once per run** (slot name is
part of the DB uniqueness key):

1. `revive` — offered once, immediately when HP reaches 0, before the run
   is finalized as a defeat. Declining proceeds straight to the Defeat
   screen with no penalty beyond the already-incurred loss.
2. `double` — offered on the Victory/Defeat results screen; doubles the
   already-computed, server-calculated currency reward for that run.
3. `extra_mutation` — offered inside the mutation-choice screen at every
   evolution threshold; adds a 4th rolled option on top of the normal 3.

If the simulated ad reports "no fill" or the player closes early, no reward
is granted and the run continues exactly as if the player had declined —
the game never blocks progress waiting on an ad.

## In-app purchases (sandbox)

| Product id | Type | Effect |
|---|---|---|
| `no_ads` | non-consumable | Sets `players.no_ads = true`. |
| `cosmetic_crystal` / `cosmetic_shadow` / `cosmetic_golden` | non-consumable | Adds a cosmetic skin id to `players.owned_cosmetics`. Purely visual — different slime body palette, no gameplay effect. |

Purchases are recorded in a `purchases` ledger table and are **not**
re-inserted on repeat purchase attempts of an already-owned non-consumable,
and `/api/iap/restore` returns the full list of owned product ids for a
device, standing in for the platform's "restore purchases" mechanism.

### What exactly does "No Ads" disable?

This game only ever shows **voluntary, player-initiated rewarded ads** —
there are no interstitials and no forced video ads blocking gameplay. To
give the purchase concrete, honest value, the UI additionally includes a
small non-intrusive **banner placeholder** on the Shop screen that is only
shown to players who have **not** purchased "No Ads". Buying "No Ads":

- **Removes**: the banner placeholder on the Shop/main screens.
- **Does NOT remove**: the voluntary rewarded-ad options (revive / double /
  extra mutation). Those stay available because they are strictly optional
  player benefits, not something a paying player should lose access to;
  removing them would be a worse outcome for the player. This exact
  behavior must be restated in the real Play Store listing per Google
  Play's transparency requirements for subscriptions/IAP.

No pay-to-win: no purchase affects starting mass, enemy difficulty, mutation
odds, or boss stats. Only cosmetics and the ad-banner removal are sold.

## Anti-pattern checklist (explicitly avoided)

- ❌ No countdown timers pressuring purchases.
- ❌ No fake "your reward is waiting!" dialogs without a real action.
- ❌ No disguised purchase buttons or pre-checked upsells.
- ❌ No simulated transactions pretending to be real money charges outside
  of the clearly labeled sandbox banner.
- ❌ No ads during active gameplay (mid-run) — only at natural breakpoints
  (evolution choice, defeat, results).

## Production integration plan (for a real Android build)

1. Replace `playTestRewardedAd()` with a real Google Mobile Ads (AdMob)
   rewarded-ad load/show flow (Godot Android plugin or, if staying on web,
   an AdMob Web/AdSense-for-games equivalent is **not** viable for a Play
   Store listing — this must happen after the Godot/Android port described
   in `ARCHITECTURE.md`).
2. Replace `purchaseTestProduct()`/`restorePurchases()` with the Google Play
   Billing Library (v6+) purchase flow, including purchase acknowledgment
   and server-side receipt verification against the Play Developer API.
3. Keep the exact same reward-slot idempotency contract
   (`canGrantReward`/unique `(runId, slot)`) so existing anti-fraud logic
   carries over unchanged.
4. Add a Data Safety / ads disclosure entry in the Play Console matching
   this document (see `RELEASE_CHECKLIST.md`).
