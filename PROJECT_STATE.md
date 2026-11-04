# Project State

## План 1.2 и переход к 2.5D — 03.11.2026

Сессия 03.11.2026 выполнила PHASE 1–3 плана 1.1:
- **PHASE 1:** концепты ChatGPT, выбрано направление **B «Лунный мицелий»** (`docs/production/01_ART_DIRECTION.md`).
- **PHASE 2:** 3D-спайк `Render3DSpike` на настоящем `PlayerSlime` (`docs/production/02_RENDER_SPIKE.md`). Android-эмулятор нестабилен, производительность NOT TESTED.
- **PHASE 3:** 4 итерации 3D-поляны из Blender-моделей (`docs/production/03_HERO_AND_FOREST.md`). Владелец счёл результат хуже текущей 2D-игры и выбрал **2.5D с нарисованными ассетами** (план 1.2).

Финальные source и PCK QA: **2333/0** каждый. Основной рантайм не изменён, ничего не закоммичено. Следующая сессия начинает с `SMUSH_AGENT_START.md` → «ТЕКУЩАЯ ЗАДАЧА».

## Лабораторное сравнение 03.11.2026

На main от `4dfc508` подготовлены три спокойные рощи и три визуальных отклика пищи в существующей ClaudeVisualLab. Свежие source/PCK QA: 2308/0 каждый; просмотрены пять стадий, контактные листы и кадр видео. Техническая проверка PASS; художественный выбор и интеграция в забег — AWAITING_OWNER_DECISION. Основной рантайм не изменён. См. `docs/production/GROVE_FOOD_STUDY_2026-11-03.md`.

## Проверка 02.11.2026

На main `6d45faf` выполнена доводка интегрированной игры по поручению «сам доделай»: мягкий пол, плавные ореолы/тени, спокойные подсказки zen, исправленные отступы карточек. Финальные source/PCK QA: 2297/0 каждый. В экспортированном Mac-приложении проверены меню, движение, рост, выбор усиления, пауза/продолжение. Последняя инструкция владельца — тестировать на Mac. См. `docs/production/RELAXATION_FINISH_2026-11-02.md`. Изменения не закоммичены; полной приёмки фаз и Android-плавности нет.

<!-- PROJECT-MEMORY-KIT:GENERATED -->
## Current status

03.11.2026: isolated grove/food study ready for owner art review in existing ClaudeVisualLab. Runtime polish from 02.11 remains the baseline. No broader phase gate declared complete.

## Working features

Final source and external PCK QA: 2297/0 each. Five growth stages, EN low-quality/narrow, RU desktop, movement video and fixed draft cards inspected. Native Mac app controls/growth/shield/pause verified; final app and APK exported.

## In progress

Owner review of grove-comparison.png and food-comparison-detail.png before integrating the opt-in art study into normal runs.

## Known issues

Pixel 3 short SurfaceFlinger samples around 8–14 FPS: not accepted. Phone gameplay worked, but ADB disconnected after a diagnostic APK was installed; restoration of the final normal APK is unverified. Capture OGG shutdown leak fixed. Full human enjoyment and sustained performance checks remain.

## Technical debt

Unknown — needs verification.

## Important constraints

Work on main per explicit owner request. No complex new mechanics. Image generation via browser ChatGPT only. Follow canonical SMUSH phase gates; no commit/push/merge/publication or default style replacement without required authorization. Preserve existing modes and gameplay formulas.

## Next priorities

Review the new lab comparison with owner. The existing macOS app contains the prior runtime only. Keep Android performance as an open issue requiring stable device access.

## Recent significant changes

- 2026-11-04: 05_LAKE_READINESS.md, final comparison frames, checklist statuses, AGENT_START state, MASTER_PLAN lines, ADR-11042300
- 2026-11-04: 4 synthesised water music loops with zone crossfade; synergies by the game's rule without save writes; 402 tests; plan 13.11
- 2026-11-04: LakeBot autoplayer; world extended upward for a real finale; focus-pause fix; 6/6 seeds reached the dive with no script errors; 376 tests; plan 13.10
- 2026-11-04: XP from eating, draft via stub arena hosting real MutationDraftOverlay, choice grants mutation without save writes; 371 tests; plan 13.9
- 2026-11-04: LakeMutations: arena hooks + 2.5D visuals for shield, electro, freeze, spikes, poison, dash, magnet, regen, speed; no save writes; 354 tests; plan 13.8
- 2026-11-04: Zone wave tables, progress-based difficulty, caps, quiet start, boss gate, despawn; 326 tests; plan 13.7
- 2026-11-04: LakeCombat absorption via AbsorptionRules, suction, mass gain, boss ram knockback; no save writes (tested); 298 tests; plan 13.6
- 2026-11-04: LakeCombat adapter hosts EnemyEntity/AncientGuardianBoss/HazardZone; Nova strikes real ones; HP bars; tests 287; plan 13.5
- 2026-11-04: LakeLegends: 6 original spirits, elusive AI, 6 auras, one-use Nova, skirmish dummies; assets in water/legend; 281 lake tests; plan 13.4
- 2026-11-04: SOLIDS circles with push-out, velocity rebound, bump fx; weak lake current; tests 242; plan 13.3
- 2026-11-04: Painted dewy plate, puddles/dew sprites, dewy flora, fade shader, glade region, puddle splash/drip/ripple, start in glade, world extended; 234 lake tests; plan 13.2
- 2026-11-04: Region streaming (grove/lake/finale) with threaded prefetch, fixed seeds, glow list pruning; memory probe; 219 lake tests; plan 13.1
- 2026-11-04: LakeAudio + 16 synthesised water sounds, water glide physics on lab instance, pad tilt, fish flee, more sway, reward event; updated SMUSH_AGENT_START, MASTER_PLAN note+checklist, DECISIONS ADR-11041900, ASSET_PIPELINE water rules, TEST_REPORT, PROGRESS, plan section 13
- 2026-11-04: texture_budget.py, set_texture_compression.py (dry-run default, not applied), docs section 12
- 2026-11-04: Painted finale plate, giants, details; reversible dive in LakeProto25D (fades, clear water shader, bubbles); 126 lake tests; docs section 11
- 2026-11-04: Painted grove transition plate, grove sprites, fireflies; shader shallow-to-deep blend by world y; 105 lake tests; docs section 10
- 2026-11-04: Painted seabed, roots, submerged stones, light rays, jellyfish wired into LakeProto25D; 50 lake tests; docs section 9
- 2026-11-04: 30 wl_ water sprites cut and wired into LakeProto25D (pads, lotus, duckweed, petals, fish shadows, reeds); docs section 8
- 2026-11-04: Painted lake plate, shore plate, caustic, ripple and foam sprites; wired into LakeProto25D; tests 36; docs section 7
- 2026-11-04: water brighter, moon column, shader duckweed parting, bigger pads, rings around slime, submerge overlay, stronger reflections; 5 more tests
- 2026-11-04: LakeProto25D lab, lake_water and lake_reflect shaders, caustic tile tool, 18 tests, comparison frame, plan section 6
- 2026-11-04: SMUSH_AGENT_START.md TEKUSHCHAYA ZADACHA replaced per 04_LAKE_DIRECTION_PLAN; DECISIONS ADR-11041620 plan agreed
- 2026-11-04: docs/production/04_LAKE_DIRECTION_PLAN.md proposal (task text replacement, water shader approach, asset order); ADR-11041620 status updated
- 2026-11-04: 3 lake concept arts (surface, flooded grove, underwater) in art_sources/2_5d/concepts/lake_direction, comparison image, ADR-11041620 AWAITING_OWNER_DECISION; earlier this session: 20 painted biomes, wind sway, zone paths, zoom 1.7 in 2.5D lab
- 2026-11-03: Concepts B Moonlit Mycelium approved; 3D spike Render3DSpike on real PlayerSlime; Blender models (slime, stump, mushrooms, stones, moss, fern, leaves, clover, grass, tree, mycelium) in resources/art/3d/moonlit; 4 glade iterations; build_pck includes .glb; plan 1.2 + handoff in SMUSH_AGENT_START.md
- 2026-11-03: Added three opt-in grove moods and bounded food echoes in ClaudeVisualLab
- 2026-11-02: Soft floor light and shared glow texture; calm zen tutorial; capture audio cleanup; fixed mutation-card horizontal overflow
- 2026-11-02: Read current diff and rendered S8 idle and movement; saved verification report and artifacts; no gameplay edits
- 2026-11-01: Tactile jelly organelle inertia, harmonious chimes, foliage wake parting
- 2026-11-01: Consolidated main, removed external worktrees, softened floor shading, decluttered zen HUD
- 2026-11-01: Switched to main at owner request; captured Pixel 3 and five growth stages; reviewed existing GLM and Claude labs; added capture mode and metadata; recorded relaxation brief and baseline
- Project Memory initialized; no code changes were made.
