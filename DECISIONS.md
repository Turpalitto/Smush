# Decisions

<!-- PROJECT-MEMORY-KIT:GENERATED -->
Record only important decisions using the ADR format in `memory/decisions/` or below.

## ADR-001 — Project Memory protocol

Status: Accepted
Date: 2026-11-01

### Context
Agents need a portable, project-local continuity layer.

### Decision
Use Markdown, JSON, Git, and the local stdlib-only Project Memory Kit.

### Why
Readable, portable, dependency-light, and independent of external LLM APIs.

### Alternatives considered
External vector/database memory; rejected for the initial implementation.

### Consequences
Agents must follow the repository protocol and keep summaries concise.

## ADR-11011930 — Recorded decision

Status: Accepted
Date: 2026-11-01

### Decision

Owner 2026-11-01: work on main; beautiful world, relaxation, simple mechanics, gradual beautiful slime growth. Express magic physics and chemistry through sensory reactions, not complex systems. Browser ChatGPT only for image generation.

## ADR-11021923 — Recorded decision

Status: Accepted
Date: 2026-11-02

### Decision

Preserve simple gameplay and existing growth formulas; continue verification on Mac as requested; no commit or push

## ADR-11031716 — Recorded decision

Status: Accepted
Date: 2026-11-03

### Decision

Direction B Moonlit Mycelium; rendering method 2.5D painted assets (3D from code-built models rejected after owner review); logic stays 2D; Render3DSpike kept as reference only

## ADR-11041620 — Направление «Лунное озеро» (на оценке)

Status: **Accepted as direction (owner, 2026-11-04)**; конкретный план и порядок ассетов воды — `docs/production/04_LAKE_DIRECTION_PLAN.md`, план согласован владельцем 04.11.2026 и внесён в «ТЕКУЩАЯ ЗАДАЧА» (`SMUSH_AGENT_START.md`); `SMUSH_MASTER_PLAN.md` не менялся
Date: 2026-11-04

### Context
Владелец 04.11.2026: слизь должна двигаться плавно, как по воде. Рассматривается основной сеттинг «Поверхность лунного озера» в стиле концепта B «Лунный мицелий». Лес остаётся прологом/первой зоной. Идея зон: (1) росистая поляна мицелия + капли и лужицы; (2) затопленная роща; (3) поверхность лунного озера (кувшинки, лепестки, ряска, тени рыб, светящиеся корни, светлячки); (4) финал — подводная светящаяся глубина. Ощущения: слои глубины под водой/поверхность/над водой, инерция, круги и след, раздвигание ряски, рост виден по волнам, только простые визуальные реакции, дешёвый шейдер воды, поддельные отражения, текстура каустики.

### State
Сделаны только нейроконцепты (ChatGPT) — не кадры Godot, слизь на них нарисована: `art_sources/2_5d/concepts/lake_direction/` (манифест `manifest.csv`, approved=false). Сравнение рядом: `reports/production/2_5d/compare_lake_direction_v1.png` (2D-игра, поляна 2.5D, три концепта). Ассеты воды и код не переделывались; фазы в SMUSH_MASTER_PLAN.md не менялись; commit/push не выполнялись.

### Decision log
04.11.2026 владелец утвердил направление «Лунное озеро». Предложение согласовано; «ТЕКУЩАЯ ЗАДАЧА» обновлена, порядок производства воды — `docs/production/04_LAKE_DIRECTION_PLAN.md`. SMUSH_MASTER_PLAN.md (фазы) не менялся.

## ADR-11041618 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Lake direction on evaluation, not approved; no water asset rework; no phase changes; no commit/push

## ADR-11041619 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Direction lake approved; plan proposal awaiting owner OK; SMUSH_AGENT_START and MASTER_PLAN unchanged; no commit/push

## ADR-11041620 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Lake direction and plan agreed by owner; SMUSH_MASTER_PLAN phases unchanged; no commit/push

_04.11.2026, ход работ:_ шаг 0 плана (шейдер-прототип воды) выполнен в лаборатории `LakeProto25D`; ассеты воды ещё не производились; решение владельца по переходу к шагу 1 — ожидается.

## ADR-11041632 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Step 0 done; water assets not started; no commit/push

## ADR-11041702 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

No water asset production yet; owner decision for step 1 pending; no commit/push

## ADR-11041810 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Owner: stop asking, decide for game improvement; no commit/push

## ADR-11041820 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous continuation per owner; no commit/push

## ADR-11041841 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous continuation; no commit/push

## ADR-11041852 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; no commit/push

## ADR-11041945 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Compression not applied: needs device check; integration needs owner permission; no commit/push

## ADR-11041900 — Всё до внесения в игру делается в лаборатории

Status: **Accepted (owner, 2026-11-04)**
Date: 2026-11-04

### Decision
Прежде чем переносить направление «Лунное озеро» в игру, анимация, звуки, физика, гибкость (мягкие реакции растений и слизи) и остальное доводятся и проверяются в изолированной лаборатории (`LakeProto25D`); значения вроде трения слизи на воде меняются только у экземпляра лаборатории, `AudioManager`, `ArenaController`, сохранения и формулы не затрагиваются. Интеграция — только после чек-листа (раздел 13 `docs/production/04_LAKE_DIRECTION_PLAN.md`) и отдельного разрешения владельца. Агент решает сам, что лучше для игры, и не задаёт лишних вопросов (память `smush-owner-autonomy`).

## ADR-11042041 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

ADR-11041900: everything before integration in the lab; owner gate for integration; no commit/push

## ADR-11042054 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; no commit/push; Blender MCP available if needed

## ADR-11042123 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; no commit/push; Nova mapped to real enemies only on integration

## ADR-11042128 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; save/arena untouched; mutations deferred (need arena callbacks, hero hides 2D body)

## ADR-11042133 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; no commit/push; evolution XP/mutations deferred

## ADR-11042137 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; waves default on in lab, --lake-calm off; no commit/push

## ADR-11042144 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; apply_mutation avoided (writes save/analytics); synergies/split/ranged/mimicry deferred

## ADR-11042150 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; stub arena instead of editing overlay; synergies deferred

## ADR-11042223 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Autonomous; AudioManager untouched; no commit/push

## ADR-11042300 — Лаборатория озера готова к оценке владельцем

Status: **AWAITING_OWNER_DECISION** (перенос в игру не начат)
Date: 2026-11-04

### Context
Выполнен чек-лист «до интеграции» (ADR-11041900) в части, доступной без телефона и без человека: см. `docs/production/05_LAKE_READINESS.md`.

### Decision requested
Владелец смотрит кадры и играет в лаборатории, слушает звук, решает по отклонениям от концепта, даёт замер на телефоне и отдельно разрешает интеграцию. До этого игра, сохранения, `AudioManager` и фазы плана не меняются; commit/push/merge — только с разрешения.

## ADR-11042228 — Recorded decision

Status: Accepted
Date: 2026-11-04

### Decision

Lab ready for owner evaluation; integration awaits owner permission; no commit/push
