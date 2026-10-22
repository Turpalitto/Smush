# TEST REPORT — 22.10.2026

Статус: автоматические проверки Godot проходят; Android-релиз не подтверждён.
Окружение: Godot **4.6.3.stable.official.7d41c59c4**, Linux x86_64, headless.

## Реально выполнено

`./scripts/run_qa.sh`:

| Suite | Passed | Failed |
| --- | ---: | ---: |
| MassAndAbsorptionSuite | 20 | 0 |
| MutationsAndSynergiesSuite | 64 | 0 |
| SaveAndProgressionSuite | 38 | 0 |
| MonetizationAndAnalyticsSuite | 41 | 0 |
| FullGameIntegrationSuite | 123 | 0 |
| **Итого** | **286** | **0** |

PCK собран `python3 tools/build_pck.py /tmp/smush-release-candidate.pck`.
Из `/tmp` запущен `godot4 --headless --quit-after 600 --main-pack
/tmp/smush-release-candidate.pck res://tests/TestRunner.tscn`: **286 passed, 0 failed**.
Это отдельный запуск упакованной игры, без использования исходной директории.

Дополнение игровой сессии: проверены четыре последовательных выбора за 501 XP,
сохранность открытых вариантов при новом опыте, отклонение невыданной мутации,
клики по настоящим UI-кнопкам, отсутствие наложенных карточек, отпускание джойстика
при паузе и сброс способности/спавна при рестарте. Свежие логи:
`reports/gameplay-source-qa-2026-10-22.log` и `reports/gameplay-packed-qa-2026-10-22.log`.
Исторические логи предыдущей сессии сохранены отдельно.

Новые проверки покрывают:
- Повреждённые поля save с верной контрольной суммой и отсутствие временного файла после atomic rename.
- Запоздалые, повторные и параллельные callbacks рекламы и отмену ожидания при новом забеге.
- Реальные имена полей Billing 3.3.0, localized price, ack failure/retry/success,
  multi-product token, дубликаты, restore после отката local save, unknown SKU.
- Невозможность повторного bank/revive после фиксации награды.
- Session lifecycle, отдельные средние session/run, boss encounter denominator,
  различие ad opt-in/completion, неизвестный ARPDAU и незрелый D7.

Fixture-тесты native schema не вызывают Play Store и не являются тестом реальной транзакции.

## Дополнительные проверки

- SHA512 Android export templates сверена с официальным `SHA512-SUMS.txt` Godot 4.6.3.
- Installer optional AdMob 5.1.0 реально скачал два закреплённых архива, проверил SHA256,
  после Godot import загружены все десять SDK script entry points, используемых адаптером.
  Native SDK/UMP/real ads на Android не запускались. Optional add-on убран из базового
  дерева; повторная установка воспроизводится `python3 tools/install_admob.py --install`.
- Android path configuration проверена локально; preflight сборки реально запущен:
  offline export остановлен из-за отсутствующих `platform-tools/adb`, `build-tools/apksigner`;
  Gradle debug также требует полный JDK (`javac`) и platform 36. **APK не создан**.
- Подготовлены ручной Android CI с явным SDK-license input и автоматический QA workflow.
  Новый Android workflow не запускался.

## Чего эти тесты не доказывают

Тест босса принудительно наносит урон и проверяет переходы фаз; это не прохождение
полного забега человеком. Тест UI меняет размер viewport и проверяет контейнеры;
он не заменяет скриншоты и визуальную оценку. Показатель CPU (~0.2 ms на
симулированный шаг небольшой headless-сцены) не доказывает 60 FPS на телефоне.

Не выполнены: Android install/run, реальный lifecycle, FPS/тепло/память, ручная оценка
графики/звука/баланса, Google Play purchases, реальная rewarded реклама, AAB и store review.

Веб-версия в предыдущей сессии: 43 теста, typecheck/lint/Next build прошли.
В этой сессии её код не изменялся и проверки не повторялись.
