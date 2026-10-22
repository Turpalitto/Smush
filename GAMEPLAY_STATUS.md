# Игровые требования и их реализация

Рабочая ветка — `arena/6d0cda1c-smush`. Здесь сопоставлен исходный MASTER PROMPT
с текущей Godot-игрой. Основные решения геймдизайна: [GAME_DESIGN.md](GAME_DESIGN.md).
Наличие реализации и успешной автоматики отделяется от ручной оценки качества.

| Требование | Реализация | Что проверено / что дальше |
| --- | --- | --- |
| Джойстик, инерция, fixed/floating | [VirtualJoystick](ui/VirtualJoystick.gd), [PlayerSlime](entities/PlayerSlime.gd), [HUD](ui/GameHUD.gd) | Сброс при паузе проверен; ощущения и touch требуют ручного запуска |
| Поглощение с учётом брони и способностей | [AbsorptionRules](systems/AbsorptionRules.gd), [ArenaController](scenes/ArenaController.gd), [EnemyEntity](enemies/EnemyEntity.gd) | Пороги проверены; зрелищность и читаемость требуют оценки |
| Нелинейный рост и ограничения массы | [MassSystem](systems/MassSystem.gd) | Формулы и узкие проходы проверены; игровой баланс требует прохождения |
| 12 мутаций | [MutationManager](mutations/MutationManager.gd), [конфигурация](resources/data/mutations.json), [PlayerSlime](entities/PlayerSlime.gd) | Выдача, уровни и последовательные выборы проверены; полезность каждой — ручная задача |
| 5 комбинаций | [конфигурация синергий](resources/data/synergies.json), [MutationManager](mutations/MutationManager.gd) | Активация проверена; эффекты и баланс проверить в бою |
| Зачарованный лес, безопасный старт | [WorldGenerator](systems/WorldGenerator.gd) | Структура и стартовая зона проверены; композиция и проходимость — ручная оценка |
| 8 базовых противников | [EnemyEntity](enemies/EnemyEntity.gd), [EnemyFSM](enemies/EnemyFSM.gd), [конфигурация](resources/data/enemies.json) | Спавн/FSM проверены; эскалация опасности требует забега |
| Мини-босс и трёхфазный босс | [ArenaController](scenes/ArenaController.gd), [AncientGuardianBoss](bosses/AncientGuardianBoss.gd) | Переходы фаз и победа проверены принудительным damage; честное прохождение ещё не проверено |
| Пауза, поражение, результат, рестарт | [GameManager](systems/GameManager.gd), [OverlaysController](ui/OverlaysController.gd), [ArenaController](scenes/ArenaController.gd) | Автоматические сценарии проходят; новая игра сбрасывает таймеры |
| Постоянная прогрессия и сохранения | [SaveManager](systems/SaveManager.gd), [конфигурация](resources/data/meta_progression.json) | Запись/repair/backup проверены; темп первых открытий требует ручного забега |
| Анимация, частицы и мутации на теле | [SlimeVisual](entities/SlimeVisual.gd), [шейдер](shaders/slime_body.gdshader), [BurstFX](entities/BurstFX.gd) | Код присутствует; визуальный аудит пока не выполнен |
| UI, обучение, RU/EN | [MenuScreens](ui/MenuScreens.gd), [MutationDraftOverlay](ui/MutationDraftOverlay.gd), [TutorialManager](systems/TutorialManager.gd), [локализация](localization/LocalizationManager.gd) | Контейнеры и кнопки проверены; телефонная читаемость требует просмотра |
| Звук и отключённая по умолчанию музыка | [AudioManager](systems/AudioManager.gd), [сохранения](systems/SaveManager.gd) | Настройки и события существуют; громкость и ощущения требуют прослушивания |
| Ограничения нагрузки | [ObjectPool](systems/ObjectPool.gd), [SpatialHashGrid](systems/SpatialHashGrid.gd) | Headless CPU-проверка проходит; реальный FPS не измерен |

## Состав последнего прогона

| Набор | Assertions |
| --- | ---: |
| Масса и поглощение | 20 |
| Мутации и синергии | 64 |
| Сохранения и прогрессия | 38 |
| Сохранённые коммерческие/аналитические regression tests | 41 |
| Игровая интеграция и UI | 123 |
| **Всего** | **286** |

286 — число всех assertions, а не число отдельных игровых механик.
Оба зафиксированных прогона (source/PCK) завершились без failures.
Логи и условия: [TEST_REPORT.md](TEST_REPORT.md).

## Как продолжать

Следовать [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md). Первым делом — обычный
забег без тестовых усилений, затем конкретные игровые улучшения по наблюдениям.
Рекламу, платежи, SDK и выпуск сейчас не развивать. Статус релиза хранится отдельно
в [RELEASE_STATUS.md](RELEASE_STATUS.md) и не задаёт текущую очередь работы.
