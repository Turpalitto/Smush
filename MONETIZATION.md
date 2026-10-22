# Монетизация — сохранено на будущий этап

По указанию владельца настройка и развитие монетизации сейчас отложены.
Текущий приоритет: [игровой процесс](GAMEPLAY_STATUS.md).

Коммерческие SDK на устройстве ещё не проверены. Основная игра офлайн,
сервер не нужен для обычного геймплея. Неизвестные/недоступные покупки и реклама
не заменяются фиктивными успешными транзакциями.

## Добровольная rewarded реклама

Один revive, одно удвоение результата и один дополнительный выбор мутации за забег.
Подтверждение награды принимает только SDK callback с текущим уникальным токеном;
повторы, чужие токены и ответы из предыдущего забега игнорируются.
Тестовые адаптеры запрещены в non-debug/commercial режиме.

`systems/PoingRewardedAdapter.gd` использует API **Poing AdMob 5.1.0** из официального
MIT-релиза: `ConsentInformation.update`, `UserMessagingPlatform.load_consent_form`,
`MobileAds.initialize`, `RewardedAdLoader.load`, `RewardedAd.show`,
`OnUserEarnedRewardListener`. UMP failure/отсутствие согласия оставляют рекламу выключенной.
Закрытие без earned callback ничего не выдаёт; после показа ad уничтожается.
Кнопка privacy options доступна в информации о приложении.

Установка необязательного add-on и совместимых Android 4.6.3 бинарников:

```bash
python3 tools/install_admob.py --install
```

Installer проверяет закреплённые SHA256. Затем нужен Godot import и включение
AdMob editor plugin. Настроить App ID/UMP в AdMob и project settings, rewarded IDs
в `BuildConfig`, проверить на тестовом устройстве. В release пустой production unit
ID оставляет ads выключенными. Public Google test unit IDs используются только
в non-commercial debug. Наличие исходников адаптера не равно production validation.

## Покупки и восстановление

Официальный **GodotGooglePlayBilling 3.3.0**, MIT, Play Billing 9.1.0.
В репозитории находятся wrapper и native debug/release AAR; provenance и digest:
[UPSTREAM.md](addons/GodotGooglePlayBilling/UPSTREAM.md).

Native `PURCHASED` обрабатывается по `product_ids`. Неподтверждённые покупки ждут
успешного `acknowledge_purchase_response`; подтверждённые покупки восстанавливаются
через `query_purchases`. PENDING не выдаёт права. Launch/ack errors сообщают об ошибке.
Один токен может содержать несколько товаров; повторные ответы не дублируют права.

| SKU | Что выдаёт |
| --- | --- |
| `com.turpalitto.slimerush.no_ads` | Нет forced ads, один бесплатный reroll за забег |
| `com.turpalitto.slimerush.skin_astral_jelly` | Косметическая форма Astral Jelly |
| `com.turpalitto.slimerush.skin_amber_spirit` | Косметическая форма Amber Spirit |
| `com.turpalitto.slimerush.fx_starlight_wake` | Косметический шлейф Starlight Wake |
| `com.turpalitto.slimerush.fx_emerald_petals` | Косметический шлейф Emerald Petals |

Источник каталога — `resources/data/meta_progression.json -> store_catalog`.
Localized price читается из `one_time_purchase_offer_details_list`; до ответа магазина
текст в каталоге — только ориентир, не подтверждённая цена магазина.

### Что означает No Ads

Баннеров и interstitial в этой версии **нет у всех игроков**. No Ads обещает отсутствие
принудительных форматов и даёт один бесплатный reroll. Добровольные revive и x2
остаются opt-in; товар не означает бесконечные бесплатные возрождения или удвоения.
Это правило указано в локализованном описании. Перед коммерческим запуском отдельно
оценить ценность товара при отсутствии forced ads и влияние платного reroll на
требование «без pay-to-win»; экономику покупки ещё не валидировали на игроках.

## Аналитика

Поддержаны 14 событий из задания. Детальный буфер gated согласием; локальные агрегаты
прогрессии работают офлайн и наружу не отправляются. SDK удалённой аналитики не подключён.

Средняя сессия и забег имеют отдельные знаменатели. Boss win rate считается по
encounters; rewarded opt-in по начатым показам, completion отдельно. D1/D7 — локальное
наблюдение одной установки; незрелый горизонт возвращает `null`. ARPDAU не вычисляется
из выдуманных цен: без проверенной выручки возвращается `null`. Популяционные метрики
и финансовые данные потребуют достаточной выборки и достоверных store/ads-отчётов.

## Обязательные внешние проверки

Play internal test: успешная/pending/отменённая покупка, ack failure, восстановление,
переустановка, offline и refund/revocation. Refund/revocation-синхронизация пока
не реализована; это блокер production IAP. AdMob: тестовый показ, UMP required/denied,
no fill/offline, dismiss без reward, реальный earned callback, lifecycle и повтор callbacks.
Нужны аккаунты владельца и Android-устройство. Реальные списания в этой работе не выполнялись.
