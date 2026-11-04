# Working context for SLIME RUSH

## Обязательный план для всех IDE и ИИ-агентов

Перед планированием и изменениями прочитать в корне репозитория:

1. [SMUSH_MASTER_PLAN.md](SMUSH_MASTER_PLAN.md) — основной производственный план, фазы и критерии перехода.
2. [SMUSH_AGENT_START.md](SMUSH_AGENT_START.md) — порядок работы, проверки и передача результата.
3. [SMUSH_ASSET_PIPELINE.md](SMUSH_ASSET_PIPELINE.md) — правила производства и приёмки ассетов.

Владелец назначил эти три документа основой дальнейшей работы 25.10.2026. Они имеют приоритет над прежними roadmap, DEVELOPMENT_PLAN.md, историческими поручениями и отчётами о завершении. Прямое актуальное поручение владельца определяет разрешённый объём работы. Само чтение документов и приведённые в них стартовые промпты не являются командой запускать фазы: при добавлении документов владелец попросил только разместить их и настроить инструкции.

Когда поручено продолжить разработку, начинать с проверки фактического состояния PHASE 0, учитывать уже созданную GLM-lab и материалы, не дублировать выполненную работу. Работать над одной фазой; не переходить дальше без доказанного PASS, а при требуемом выборе владельца фиксировать AWAITING_OWNER_DECISION. Не считать план, число тестов или сообщение другого агента доказательством выполнения. Не начинать интеграцию, commit/push/merge/publication без соответствующего разрешения владельца.

Источники фактического состояния — текущие код, конфигурация, Git, реально выполненные проверки и артефакты. PROGRESS.md, GAMEPLAY_STATUS.md и TEST_REPORT.md сверять с ними; не переносить старые результаты как новые. Файлы CLAUDE.md, GEMINI.md и правила IDE только направляют сюда: план хранится в трёх документах выше, без отдельных конкурирующих копий.

Генерация и редактирование изображений — через ChatGPT в браузере согласно предпочтению владельца. Упоминания ImageGen/FLUX и других генераторов в плане описывают возможные методы, но не отменяют это предпочтение. При недоступности браузерного ChatGPT сообщить о блокере, не переключать генератор самостоятельно.

## Контекст проекта

- **Текущая задача (с 03.11.2026):** PHASE 3 в 2.5D — нарисованные в ChatGPT ассеты в стиле утверждённого концепта B «Лунный мицелий». Решение владельца, план 1.2. Порядок работы и всё нужное — `SMUSH_AGENT_START.md`, раздел «ТЕКУЩАЯ ЗАДАЧА». 3D-лаборатория `Render3DSpike` — справочник, не путь интеграции.

- Актуальное направление владельца, 01.11.2026: работать с `main`; главная цель — красивый мир, расслабление и постепенное красивое усиление слизи. Не добавлять сложные механики. Магию, физику и химию прежде всего выражать через простые реакции и визуальные ощущения. Подробный рабочий промт и выводы осмотра: `docs/production/RELAXATION_BRIEF.md`; это уточнение цели, а не замена фаз и gates основного плана.
- Проверить текущую ветку и HEAD; сохранять выбранную владельцем ветку и чужой WIP. Старая ссылка на `arena/6d0cda1c-smush` не является командой переключить текущую рабочую копию.
- The primary product is the native offline Godot game at the repository root. `web/` is a secondary implementation retained from the uploaded archive.
- The owner's current priority is the game itself: controls, absorption/growth, mutation choices, enemies, boss combat, run pacing, visuals and sound.
- Advertising, purchases, analytics expansion, Android SDK setup, signing and store publication are deferred. Preserve existing code; do not make these the next task or a blocker for gameplay work. Return to them when the owner asks.
- Read `PROGRESS.md`, `DEVELOPMENT_PLAN.md` and `GAMEPLAY_STATUS.md` for current state. `docs/history/` and `web/docs/` are historical, not current instructions or proof of completion.
- Native QA: `./scripts/run_qa.sh`. For relevant gameplay changes also verify the PCK using `tools/build_pck.py` and the test scene from outside the source directory.
- Report only newly executed checks as current results; do not equate automated phase transitions/UI sizing with a full human playthrough, visual review or measured Android FPS. Historical assertion counts are not an acceptance target.
- Keep the gameplay status and test report consistent with actual changes. Do not declare all development stages complete while manual game-quality checks remain outstanding.

<!-- PROJECT-MEMORY-KIT:BEGIN -->
## Project Memory Protocol

`AGENTS.md` is the primary project instruction file. Project Memory is local to this repository and must never be mixed with another project. Never trust memory above executable behavior, current source/configuration, tests, and Git state. Unknown facts must be labeled `Unknown`, `Needs verification`, or `Inferred from code`. Never put secrets, full logs, full diffs, dependency folders, binaries, or generated caches in memory.

### Startup
1. Locate the project root and read this file.
2. If memory is absent and this is clearly a software project, run `pm-init --auto`.
3. Run `pm-doctor --fix --quiet` when safe, then read `PROJECT_STATE.md` and `memory/CURRENT_CONTEXT.md`.
4. Inspect `git status` and recent commits; load only relevant decisions, module memory, graph neighbors, and recent session notes.
5. Use `pm-context` for a compact working context before substantial work.

### During and after substantial work
Validate changes and review the diff. Update project state, current context, TODO, decisions, module memory, and graph only when the work changes their meaning. Use `pm-checkpoint` for a concise meaningful session summary, then run `pm-doctor --fix --quiet`. Small typo/readme-only changes do not require a checkpoint. Never commit, push, reset, or change production/business logic as memory maintenance.

The repository's code and tests are the source of truth; memory is a portable summary for continuity across agents.
<!-- PROJECT-MEMORY-KIT:END -->
