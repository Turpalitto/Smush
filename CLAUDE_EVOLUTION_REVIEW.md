# CLAUDE V8: EVOLUTION REVIEW

> Branch: `experiment/claude-slime-v8` | Base: `247a11e`
> QA: **2292 passed, 0 failed** | No commits/merges performed

## 1. What Was Implemented

### Evolution System (PHASE 2+3) — COMPLETE
- **9 new shader uniforms** controlling structural evolution from `growth_t`:
  - `evo_membrane` — membrane thickness and fold depth
  - `evo_core_cx` — core complexity (single dot → multi-lobe nucleus)
  - `evo_vesicles` — vesicle density (0 at S1 → full field at S15)
  - `evo_fibrils` — light fibril network density
  - `evo_biolum` — bioluminescence intensity
  - `evo_organelles` — organelle (ER, mitochondria) visibility
  - `evo_asym` — silhouette organic asymmetry
  - `evo_opacity` — body transparency (clear baby → opaque apex)
  - `evo_eye_scale` — eye proportional size (bigger baby → proportional apex)

### 6 Artistic Chapters
All stages use continuous `smoothstep()` interpolation from `growth_t`, not discrete switches:

| Chapter | Stages | Key Visual Changes |
|---------|--------|--------------------|
| Primordial Drop | 1–2 | Transparent sphere, smooth membrane, big eyes, faint dot nucleus |
| Awakening | 3–5 | First membrane folds, vesicles appear, core brightens |
| Adaptation | 6–8 | Full crescent core, iridescence, visible fibrils, glow pool |
| Predator | 9–11 | Thicker membrane, deeper folds, secondary core lobe, turbulent currents |
| Apex Mutation | 12–14 | Dense vesicle field, organelles visible, strong asymmetry, complex nucleus |
| Perfect Form | 15 | Maximum complexity: multi-chamber nucleus, rich organelles, pearlescent body |

### Ring Physics Evolution
- **Baby**: High damping (6.5), low stiffness (55) → soft, wobbly
- **Apex**: Low damping (4.0), high stiffness (92) → confident, cohesive
- Organic per-node asymmetric rest offsets scale with stage

### Breathing
- Amplitude: 0.35× at baby → 1.0× at apex (gentle newborn → deep predator)

### Ground Effects
- Shadow intensity: 0.4× at baby → 1.0× at apex
- Bioluminescent glow pool scales with evolution

### Existing Mutations (PHASE 5)
- **ranged_absorb (tentacles)**: Working ✅
- **shield**: Working ✅
- **electro_discharge**: Working ✅
- Other 9 mutations render via base class visuals — no regressions

## 2. Tools Used

| Tool | Purpose |
|------|---------|
| Godot 4.5 stable (Metal) | Shader compilation, rendering, lab scene |
| GDScript | Evolution param driver, ring physics, eye scaling |
| GLSL (canvas_item) | Body/eyes/shield shaders |
| Python (claude_crop.py) | Image post-processing |
| Bash (claude_shot.sh) | Capture automation |

## 3. Files Modified

| File | Change |
|------|--------|
| `entities/SlimeVisual.gd` | +3 bool hooks (from previous session, unchanged) |
| `shaders/slime_body_claude.gdshader` | +9 evolution uniforms, parametric silhouette/membrane/core/vesicles/fibrils/organelles |
| `entities/claude/SlimeVisualClaude.gd` | +30 lines: evolution param curves, eye scaling, breath scaling, ring evolution |
| `entities/claude/ClaudeRing.gd` | +25 lines: set_evolution(), asymmetric offsets, scaled dynamics |

## 4. Results

### QA
- **2292 passed, 0 failed** (no regressions from evolution changes)
- All 3 shaders compile without errors
- All 15 stages render correctly
- All 3 mutation combos render correctly

### Visual Evolution Progression
- Stage 1 is clearly a baby: transparent, smooth, big-eyed, minimal glow
- Stage 8 is the showcase: crescent core, membrane folds, vesicles, iridescence
- Stage 15 is distinctly apex: opaque pearl body, asymmetric, multi-lobe nucleus, organelles, strong glow

## 5. Tests Passed

| Suite | Assertions |
|-------|-----------|
| MassAndAbsorption | 22 |
| MutationsAndSynergies | 64 |
| SaveAndProgression | 38 |
| MonetizationAndAnalytics | 41 |
| DifficultyAndRecords | 128 |
| GrowthLadder | 610 |
| GameModes | 90 |
| AudioChimes | 156 |
| FullGameIntegration | 755 |
| VisualLab | 388 |
| **TOTAL** | **2292 / 0** |

## 6. What Did Not Work / Compromises

- **Vesicle scatter on hurt/absorb**: Not implemented — would require passing event timing to shader. Current vesicles orbit on fixed paths with lag. Low priority.
- **Per-stage fibril COUNT**: Currently fibrils scale in brightness but not in angular count (always 6-arm pattern). Would need shader restructuring for dynamic arm count.
- **Android performance**: Not tested on real device. Desktop M5 runs comfortably at 60 FPS. Quality=0 (Low) disables refraction, marbling, and limits vesicles for mobile.
- **Remaining mutations**: 9 of 12 mutations use base class visuals (not organic styled). Three priority mutations (tentacles, shield, electro) have full organic visuals.

## 7. Artistic Compromises

- **Asymmetry cap at 0.25**: Stronger asymmetry looked damaged rather than organic. Subtle is better.
- **Eye size doesn't shrink below 1.0×**: Tried smaller eyes at apex, lost cuteness. Eyes stay proportional but gain iris detail.
- **Crescent core peaks at S8**: The "signature" crescent moon is most prominent at the midpoint; early and late stages use round/multi-lobe nuclei. This gives S8 its unique identity.
- **No external PNG textures**: Everything is procedural shader + GDScript draw. This is intentional — resolution-independent and maintainable. External painted textures could add more personality but would need artist pipeline.

## 8. Integration Readiness

| Criterion | Status |
|-----------|--------|
| QA passes | ✅ |
| No game balance changes | ✅ |
| No save format changes | ✅ |
| Base class minimal hooks (3 bools) | ✅ |
| Style is opt-in only (not in VisualStyle.gd) | ✅ |
| Original + GLM organic unchanged | ✅ |
| All 15 stages render | ✅ |
| 3 priority mutations styled | ✅ |
| 9 remaining mutations work via base | ✅ |
| No commits/merges | ✅ |

**Ready for owner review of lab-quality visual result.**
Not yet recommended for main integration without:
- Real Android device performance test
- Owner artistic sign-off on evolution progression
- Decision on remaining 9 mutation organic visuals
