# GLM — 03. Имплементация

Ветка: `feature/glm-organic-visual-lab` (от `main` @ `ff93ee1`). Никаких правок
`main`, баланса, сохранений, монетизации, Android-настроек.

## 1. Файлы

### Новые
| Файл | Назначение |
| --- | --- |
| `shaders/slime_body_organic.gdshader` | экспериментальное органическое тело (альтернатива `slime_body.gdshader`) |
| `shaders/organic_shield.gdshader` | мембрана щита: вмятина, рябь, провисание и восстановление |
| `entities/SlimeVisualOrganic.gd` | класс стиля: таблица анатомии 15 стадий, инерция, глотки, проводка органических нод |
| `entities/OrganicTendrils.gd` | псевдоподии `ranged_absorb` |
| `entities/OrganicShield.gd` | нода щита (квад + шейдер), impact/recovery |
| `entities/OrganicElectro.gd` | дуги разряда между целями |
| `scripts/labs/EvolutionVisualLab.gd` | вся лаборатория: UI, демо-слизь, добыча, поглощение, env-хуки |
| `scenes/labs/EvolutionVisualLab.tscn` | сцена лаборатории (корень + скрипт, остальное строится кодом) |
| `tests/test_visual_lab.gd` | сьюта `VisualLabSuite` (388 assertions) |
| `deliverables/glm_visual_lab/shots/*.png` | сравнительные кадры (15 шт.) |
| `deliverables/glm_visual_lab/clips/*.avi` | движение и поглощение, 6 с, 30 fps |

### Изменённые (минимально)
- `entities/SlimeVisual.gd` — три поля-флага `organic_tendrils / organic_shield /
  organic_electro = false` и три guard-условия вокруг базовой отрисовки щупалец,
  купола щита и искр электроразряда. По умолчанию всё выключено: исходный стиль
  рисуется побитово как раньше (покрыто прежними сьютами).
- `tests/TestRunner.gd` — регистрация `VisualLabSuite`.

Не изменялись: `EvolutionStages.gd`, `MassSystem.gd`, `AbsorptionRules.gd`,
`PlayerSlime.gd`, `ArenaController.gd`, `mutations.json`, `synergies.json`,
враги, боссы, UI игры, сохранения, монетизация, `slime_body.gdshader`.

## 2. Ключевые решения

- **Наследование вместо веток в базовом классе.** `SlimeVisualOrganic extends
  SlimeVisual`: переиспользуются squash/stretch, след, тень, глаза, косм metastas
  и вся палитра; переопределяются только шейдер, `_process`-дополнения и
  `_draw_foreground` (призраки глотков поверх базового).
- **`u_time` вместо `TIME`.** Время накапливается на CPU, поэтому «Стоп» и
  slow-mo в лаборатории честно замораживают анатомию (заморозка через
  `Engine.time_scale`, восстановление — в `_exit_tree`, покрыто тестом).
- **Инерция одним сигналом.** `lag_vec = velocity − EMA(velocity)` — покрывает и
  ускорение, и торможение (знак переворачивается сам), CPU-цена — один lerp.
- **Лаборатория без `PlayerSlime`.** Демо-слизь — голый `Node2D` с визуалом;
  `complete_absorption`, статы и аналитика не вызываются, сохранение не трогается.
  Проверка съедобности всё же идёт через настоящий `AbsorptionRules`-контекст —
  сильная добыча демонстративно убегает.
- **Презентационная камера** (zoom 1.6) — чтобы анатомия оценивалась в размере,
  сопоставимом с игрой; UI живёт в `CanvasLayer` и не зависит от неё.

## 3. Лаборатория: как пользоваться

Запуск: `godot --path . res://scenes/labs/EvolutionVisualLab.tscn`
(или открыть `scenes/labs/EvolutionVisualLab.tscn` в редакторе и F5 в ней).

- **Стадия/Масса** — два связанных ползунка; преобразование точно инвертирует
  `EvolutionStages.t_for_mass`, пороги не смещаются (тест roundtrip).
- **Стиль** — «Исходный» / «Органический»; переключение на живом объекте.
- **Кач-во** — Low/Med/High: слои органелл, рефракция экрана, детальность.
- **Движение** — автономное плавание по Лиссажу (реагируют squash, след, инерция).
- **Поглотить** — гарантирует добычу; далее цепочка «контакт → рябь → втягивание →
  призрак → растворение → плавный рост» с проверкой `AbsorptionRules`.
- **Урон** — вспышка/сжатие; при включённом щите — вмятина мембраны и X_X.
- **Стоп / ×скорость** — `Engine.time_scale` 0 или 0.25–1.5.
- **Мутации** — 12 чекбоксов (уровень — ползунком 1..5); уровни живут только в
  лаборатории, `SaveData` не пишется.
- Клавиши: `Space` — добыча, `X` — урон, `P` — стоп, `M` — движение.

### Автоматизация (для снимков/замеров)
```
LAB_SHOT=out.png LAB_STAGE=8 LAB_STYLE=organic LAB_MUT=ranged_absorb,shield \
LAB_MLEVEL=3 LAB_QUALITY=2 LAB_MASS=52 LAB_PREY=3 LAB_WAIT=1.0 \
LAB_SEQ=absorb|tendril|electro|hurt LAB_MOVE=1 LAB_SIZE=540x1200 \
  godot --path . res://scenes/labs/EvolutionVisualLab.tscn

LAB_PERF=1 LAB_STAGE=8 ...   # сетка стиль×качество, avg/min/max ms, vsync off
```

## 4. Интеграция нового стиля в основную игру (проект, требует одобрения — см. 05)

1. В `PlayerSlime._ready` — выбор класса визуала по настройке:
   `visual = SlimeVisualOrganic.new() if style == "organic" else SlimeVisual.new()`.
   Контракт совпадает (тот же набор полей и методов), `_sync_mass_metrics` без изменений.
2. Глотки: в `complete_absorption` после `visual.trigger_gulp()` добавить
   `visual.trigger_swallow(world_pos - global_position, цвет цели, размер цели)` —
   только если визуал органический (или добавить no-op в базовый класс).
3. Щит: на `Events.player_shield_triggered` вызвать
   `visual.trigger_shield_impact(dir)`; активность уже идёт через
   `visual.shield_active`.
4. Электро: на существующем таймере `_electro_timer` рядом с
   `arena_ref.call("trigger_electro_pulse", ...)` вызвать `trigger_electro_flash()`
   и `fire_discharge(локальные позиции целей)`; заряд в шейдере уже циклится сам.
5. Качество: пробросить настройку графики в `SlimeVisualOrganic.set_quality`.

Все шаги — аддитивные вызовы визуала; игровая логика не меняется.

## 5. Известные упрощения прототипа

- Лабораторный фон не заменяет лес; рефракция оценена на подставке.
- Тон/яркость шейдера подобраны на кадрах лаборатории; на реальном
  WorldMood-грейде (тёплый золотой свет верхних стадий) потребует сверки.
- Дуги разряда рисуются от тела к локальным целям; выбор целей в игре остаётся за
  `ArenaController.trigger_electro_pulse`.
- `LAB_DEBUG`-печать состояния добычи при `LAB_SEQ=tendril` оставлена намеренно
  (диагностика снимков, как в `tools/quick_capture.gd`).
