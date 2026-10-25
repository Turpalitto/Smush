# P0 security — `next@16.2.6` в `web/`

Дата: 2026-10-25. Ветка: `feature/glm-organic-visual-lab`.
Статус: **отдельный трек, в органическую лабораторию не входит, к применению не
приступал** — по требованию владельца патч подготовлен для независимого ревью.

Источник данных: `reports/security-npm-audit-web-2026-10-25.json` (живой реестр npm,
`npm audit --package-lock-only` по `web/package-lock.json`). Ничего не выдумано: все
идентификаторы и диапазоны взяты из ответа реестра.

## 1. Уязвимый пакет и версия

| Поле | Значение |
| --- | --- |
| Пакет | `next` |
| Установленная версия | **16.2.6** (точная, `web/package.json`, `web/package-lock.json`) |
| Уязвимый диапазон | `>=9.3.4-canary.0 <16.4.0` (в отчёте: `9.3.4-canary.0 - 16.4.0`) |
| Тяжесть | **critical** |
| Advisory в этом диапазоне | **20** |
| Исправленная версия | **16.4.3** (patch, `isSemVerMajor: false`) |

Рядом в том же `web/` числятся ещё 6 пакетов (28 advisories суммарно): `postcss`
8.5.8 (high, XSS в stringify и произвольное чтение файлов через `sourceMappingURL`),
`sharp` 0.34.5 (high, наследованные CVE libvips/libheif/librsvg), `esbuild`
(<=0.24.2, moderate — dev-сервер принимает запросы с любого сайта), `drizzle-kit`
и два `@esbuild-kit/*` (moderate, тянутся через `drizzle-kit`). Они **не** входят в
P0: `postcss`/`esbuild` — сборка и dev, `sharp` — транзитивно через `next`,
`drizzle-kit` — CLI миграций. Все они закрываются тем же обновлением `next` либо
обновлением своих пакетов отдельным решением.

## 2. Конкретные advisory

RCE-класс (самое опасное):

| Advisory | Что делает | CVSS |
| --- | --- | --- |
| `GHSA-p293-qw3h-jr36` | неаутентифицированный RCE на серверах под Windows | **9.0** |
| `GHSA-2xp9-vwfh-vxw4` | RCE в Image Optimization API при AVIF | — |
| `GHSA-2464-fhr4-w9xw` | RCE в Image Optimization API при SVG | — |
| `GHSA-vcvr-r3jv-pc5j` | RCE в `next/og` (`ImageResponse`) | — |
| `GHSA-673q-mjm6-r5xr` | RCE в `use cache`-функциях, возвращающих typed arrays | — |

Утечки, SSRF и кэш:

| Advisory | Что делает | CVSS |
| --- | --- | --- |
| `GHSA-6gpp-xcg3-4w24` | обход middleware/proxy в App Router с Turbopack и одной локалью | — |
| `GHSA-89xv-2m56-2m9x` | SSRF в Server Actions на кастомных серверах | — |
| `GHSA-p9j2-gv94-2wf4` | SSRF в `rewrites` через подконтрольный хост | — |
| `GHSA-cjq9-62q9-8jv4` | SSRF в Image Optimization | 6.5 |
| `GHSA-955p-x3mx-jcvp` | раскрытие внутренних Server Function endpoints без аутентификации | — |
| `GHSA-4jqv-mc3x-m676` | отравление кэша SSG/ISR при self-hosting | 5.3 |
| `GHSA-mcj8-r9mp-w47p` | подмена контента между пользователями + устойчивый DoS через кэш | 4.8 |
| `GHSA-68g3-v927-f742`, `GHSA-4633-3j49-mh5q` | перепутывание тел ответов в кэше (в т.ч. невалидный UTF-8) | — |
| `GHSA-f87g-xv8r-7p7x` | обход `dynamicParams` в metadata-роутах | 5.3 |
| `GHSA-39w2-rjm5-chcv` | раскрытие информации в MCP-endpoint dev-сервера | 5.4 |

Отказ в обслуживании:

| Advisory | Что делает |
| --- | --- |
| `GHSA-m99w-x7hq-7vfj`, `GHSA-p3m5-59mp-jv5r` | DoS в App Router через Server Actions |
| `GHSA-4c39-4ccg-62r3` | неограниченный payload Server Action в Edge runtime |
| `GHSA-q8wf-6r8g-63ch` | DoS в Image Optimization API на SVG |

## 3. Реальная эксплуатируемость (по факту этого репозитория)

Проверено по коду `web/`, а не по описанию advisory:

| Признак | Факт в `web/` | Следствие |
| --- | --- | --- |
| `middleware.ts` | **нет** | `GHSA-6gpp-xcg3-4w24` недостижим |
| Server Actions (`"use server"`) | **нет** (`grep -rln '"use server"' src` — пусто) | четыре advisory по Server Actions недостижимы |
| `next/image` | **нет** (`grep -rln 'next/image' src` — пусто) | компонент не используется; **но** маршрут `/_next/image` в `next start` всё равно существует и принимает внешние запросы |
| `rewrites` в `next.config.ts` | **нет** (только `turbopack.root` и `outputFileTracingRoot`) | `GHSA-p9j2-gv94-2wf4` недостижим |
| `next/og` | не используется | `GHSA-vcvr-r3jv-pc5j` недостижим |
| `use cache` | не используется | `GHSA-673q-mjm6-r5xr` недостижим |
| Хостинг под Windows | нет: ни `Dockerfile`, ни `vercel.json`, ни деплой-джобы в `.github/workflows` (там только `android-build.yml`, `android-package.yml`) | `GHSA-p293-qw3h-jr36` (CVSS 9.0) неприменим |
| Развёрнутый инстанс | **отсутствует.** `INTEGRATION.md`: браузерная версия «сохранена как запускаемое приложение в `web/`», запуск — локальный `npm run dev`/`next start` | публичной поверхности атаки сейчас нет |

Итог по эксплуатируемости:

- **Сейчас — не эксплуатируется**, потому что `web/` никуда не развёрнут, а
  dev-сервер слушает localhost разработчика.
- **При первом же `next start` на публичном хосте** становятся достижимы
  Image Optimization (SSRF + RCE через AVIF/SVG), кэш-отравление и DoS: это те
  маршруты, которые существуют по умолчанию, без единой строчки кода приложения.
- **На Windows-хосте** добавляется RCE с CVSS 9.0 без аутентификации.
- **Нативная Android-игра не затронута**: `next` не входит в APK, `INTEGRATION.md`
  отдельно фиксирует, что файлов `web/` в PCK нет.

## 4. Безопасный способ исправления

Только точечное обновление двух пакетов в пределах 16.x, без массового
`npm audit fix --force` и без обновления транзитивных зависимостей «заодно»:

```
cd web
npm install next@16.4.3 eslint-config-next@16.4.3 --save-exact
npm test && npm run typecheck && npm run lint && npm run build
npm audit --package-lock-only    # ожидаем: critical/high по next и postcss уходят
```

Почему это безопасно:

- `16.2.6 → 16.4.3` — **patch-релиз внутри одной мажорной ветки**;
  `fixAvailable.isSemVerMajor: false`.
- Peer-зависимости проверены живым реестром:
  `next@16.4.3` требует `react ^19.0.0` / `react-dom ^19.0.0` (в проекте 19.2.6 ✔),
  `engines.node >= 20.9.0` (в проекте Node 22 ✔).
  `eslint-config-next@16.4.3` требует `eslint >= 9.0.0` (в проекте 9.39.4 ✔).
- Конфигурация `turbopack.root` и `outputFileTracingRoot` в `next.config.ts`
  не менялась между 16.2 и 16.4; API приложения (`src/app`, `src/db`, API-роуты)
  не использует ничего из удалённого в 16.x.

## 5. Возможные несовместимости после обновления

1. **`postcss`.** `next@16.4.3` тянет свой `postcss`; в `web/` он зафиксирован
   отдельно (`8.5.8`) и используется `@tailwindcss/postcss`. После обновления
   возможна двойная версия в дереве — проверять `npm ls postcss`, при конфликте
   поднимать `postcss` до `>=8.5.23` отдельным решением (это уже не P0).
2. **`sharp`.** `next` подтягивает `sharp` для Image Optimization; версия может
   подняться вместе с `next` и изменить набор нативных бинарников. На `linux/arm64`
   и `darwin/arm64` проверять, что optional-зависимость встала (в CI — `npm ci` с
   нуля, а не инкрементально).
3. **ESLint.** `eslint-config-next@16.4.3` может включить новые правила: `npm run
   lint` способен дать новые предупреждения/ошибки на существующем коде. Это
   лечится точечными `eslint-disable` с комментарием, а не откатом версии.
4. **Кэш и ISR.** Правки кэша в 16.4 меняют поведение `revalidate`; у проекта нет
   SSG/ISR-страниц (`src/app/page.tsx` + API-роуты), поэтому влияния не ожидается.
5. **`drizzle-kit`/`esbuild`.** Остаются moderate и **не** закрываются обновлением
   `next`: это dev/CLI-цепочка. Отдельное решение владельца.

## 6. Патч для независимого ревью

Файл: `docs/security/p0-next-16.4.3.patch` — меняет **только** `web/package.json`
(две строки версий). `package-lock.json` намеренно не включён: его надо
перегенерировать командой из §4 и ревьюить отдельно, иначе дифф на десятки тысяч
строк невозможно осмысленно проверить.

Применение (после ревью, не сейчас):

```
git apply --check docs/security/p0-next-16.4.3.patch
git apply docs/security/p0-next-16.4.3.patch
cd web && npm install --package-lock-only && npm ci
```

## 7. Что я не делал

- Не обновлял зависимости и не запускал `npm audit fix` — ни в `web/`, ни где-либо.
- Не менял `web/package-lock.json`.
- Не трогал код `web/` (по условию владельца «не трогать web» в этой приёмке).
- Не ослаблял сканеры и hooks: `core.hooksPath` в репозитории пуст, pre-commit
  Mimosa не активен; блокер `tools/install_admob.py:29` (SSRF в сканере) остаётся
  как есть и к этому треку отношения не имеет.
