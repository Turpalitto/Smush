# RELEASE_CHECKLIST.md

This checklist mirrors the brief's Android release section. Items are
marked **Done**, **Simulated/Test**, or **Blocked** (needs a resource not
available in this sandbox — real device, real account, real secret, or
human/legal sign-off).

## Build artifacts

- [x] Working web build (`npm run build`) — **Done**.
- [ ] Android `application id` — **Blocked**: needs the owner to choose and
  register a reverse-DNS id (e.g. `com.yourstudio.slimerush`); not a
  technical blocker, a decision requiring the owner.
- [ ] App icon / splash screen (Android) — not produced; this build is a
  responsive web UI, icon/splash assets would be authored during the Godot
  port (`ARCHITECTURE.md`). **Blocked** (depends on the port).
- [ ] Debug APK — **Blocked**: requires Android SDK/Gradle/Godot export
  templates, unavailable in this sandbox.
- [ ] Release AAB — **Blocked**: same as above, plus a signing keystore.
- [ ] Signing configuration & keystore — **Blocked**: must be generated and
  stored by the owner outside of version control (see "Secrets" below);
  never committed to Git in any case.

## Store listing materials

- [x] Short/long description drafts — see below.
- [ ] Screenshots — **Blocked**: requires a rendered Android build or
  device/emulator capture; this web build's screens are feature-complete
  and screenshot-ready once a capture environment exists.
- [x] Privacy policy draft — in-app (`Privacy` screen) and reproduced below;
  **requires legal review before publishing**, as required by the brief.
- [x] Data Safety checklist draft — below.
- [x] Content rating checklist draft — below.
- [ ] Final Play Console content rating questionnaire submission —
  **Blocked**: requires a real Play Console account.

### Short description (RU, draft)

> Поглощай, расти, эволюционируй! SLIME RUSH — динамичная 2D-аркада про
> слизь, которая поглощает лес и превращается в могущественное существо.

### Short description (EN, draft)

> Absorb, grow, evolve! A fast 2D slime-growth arcade game with mutations,
> an evolving forest biome, and a 3-phase boss fight.

### Privacy policy (draft — see also the in-app Privacy screen)

> SLIME RUSH: EVOLUTION works offline. The game stores an anonymous,
> randomly generated device identifier to persist progress (currency,
> upgrades, collection). We do not collect name, email, phone number, or
> precise location. With user consent, the game may send anonymized
> analytics events (e.g. "run started", "mutation selected", "rewarded ad
> viewed") to improve balance and retention; these events contain no
> personal data. Voluntary rewarded ads and in-app purchases are currently
> processed through sandbox/test adapters in this build (see
> `MONETIZATION.md`); a production release will use Google Mobile Ads SDK
> and Google Play Billing under their respective policies. **This is a
> draft and requires legal review before publication.**

### Data Safety checklist (draft, Play Console mapping)

| Data type | Collected? | Shared? | Purpose |
|---|---|---|---|
| Device/anonymous identifiers | Yes (random UUID) | No | App functionality (save progress) |
| App interactions (analytics events) | Yes, if consented | No (processed internally) | Analytics |
| Personal info (name/email/phone) | No | No | — |
| Location | No | No | — |
| Financial info | No (handled entirely by Google Play Billing, not stored by the app) | — | — |

### Content rating checklist (draft)

- Violence: mild, cartoon/fantasy creature absorption, no blood/gore.
- No real-world weapons, no gambling mechanics, no user-generated content,
  no chat/social features.
- Expected rating bracket: Everyone / PEGI 3 — **must be confirmed via the
  actual Play Console questionnaire**, not asserted here.

## Testing & QA

- [x] Automated unit tests executed (`TEST_REPORT.md`) — 40/40 passing.
- [x] Type-check, lint-equivalent, and production build executed — passing.
- [x] Live API/integration smoke test against the running server — passing.
- [ ] Manual playtest on a real Android device — **Blocked**, no device
  available in this sandbox.
- [ ] 60/90/120Hz behavior verification — **Blocked**, requires physical
  hardware; the web engine uses delta-time scaling (`dt` clamped to 50ms)
  which is hardware-refresh-rate-agnostic by design, but this has not been
  measured on real high-refresh hardware.
- [ ] Rewarded ad / IAP sandbox testing with real Google accounts —
  **Blocked**, no AdMob/Play Console account configured.

## Secrets & signing (process, not yet executed — no secrets exist yet)

1. Generate a keystore (`keytool -genkeypair -v -keystore release.keystore
   -alias slimerush -keyalg RSA -keysize 2048 -validity 10000`) **once a
   Godot/Android export pipeline exists**.
2. Store `release.keystore`, the key alias, and both passwords in a secret
   manager or CI secret store — **never commit them to Git**. Add
   `*.keystore`, `*.jks`, and any `key.properties` file to `.gitignore`
   immediately when they are introduced.
3. Keep a secure, access-controlled backup; Google Play cannot recover a
   lost signing key for apps enrolled before Play App Signing, so register
   for Play App Signing when creating the app listing.

## Explicit list of owner/manual actions required before this can ship

1. Decide the Android `applicationId` and app display name for the store
   listing.
2. Provide (or approve generation of) a Google Play Console developer
   account and an AdMob account.
3. Perform the Godot/Android port described in `ARCHITECTURE.md` (requires
   a Godot-capable environment, which this sandbox does not have).
4. Replace the test ad/IAP adapters with real SDK integrations
   (`MONETIZATION.md`).
5. Run the full manual QA matrix from the original brief (first launch,
   full run, boss victory, defeat, restart, offline behavior, app
   backgrounding, resolution/aspect-ratio changes) on real Android hardware.
6. Have the privacy policy and store listing reviewed by legal counsel
   before publishing.
7. Generate and securely store the release keystore; never check it into
   version control.
8. Only publish after the owner's explicit sign-off — this session does not
   publish anything, per the brief's own restriction on taking
   publishing/payment/account actions without explicit permission.
