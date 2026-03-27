# Analytics Guide

## Зачем вообще нужна эта аналитика

Аналитика в проекте отвечает за три отдельные продуктовые задачи:

1. Понять, где игроки отваливаются.
2. Понять, где игра зарабатывает или теряет экономический баланс.
3. Понять, какие фичи реально двигают прогресс, retention и монетизацию.

В проекте заведены два основных направления аналитики:

- `Funnels` — воронки поведения игрока.
- `Economy` — источники, траты и баланс игровых ресурсов.

Дополнительно используются `custom events` для причин отказа, намерений игрока и entitlement-событий, которые не должны попадать в Economy dashboard.

## Где что лежит

Основные файлы аналитики:

- `src/ServerScriptService/Modules/AnalyticsFunnelsService.lua`
- `src/ServerScriptService/Modules/AnalyticsEconomyService.lua`
- `src/ServerScriptService/Modules/EconomyValueUtils.lua`
- `src/ServerScriptService/Controllers/PlayerController.lua`

Важные точки интеграции по геймплею:

- `src/ServerScriptService/Modules/CarrySystem.lua`
- `src/ServerScriptService/Modules/BombManager.lua`
- `src/ServerScriptService/Modules/SlotManager.lua`
- `src/ServerScriptService/Modules/SellManager.lua`
- `src/ServerScriptService/PlotManager.server.lua`
- `src/ServerScriptService/Controllers/PickaxeController.lua`
- `src/ServerScriptService/Modules/UpgradesSystem.lua`
- `src/ServerScriptService/Modules/RebirthSystem.lua`
- `src/ServerScriptService/Controllers/DailyRewardController.lua`
- `src/ServerScriptService/Controllers/PlaytimeRewardController.lua`
- `src/ServerScriptService/Controllers/DailySpinController.lua`
- `src/ServerScriptService/Controllers/MonetizationController.lua`
- `src/ServerScriptService/Modules/GroupRewardController.lua`

## Архитектура

### 1. Funnels

`AnalyticsFunnelsService` — это единая точка работы с funnel analytics.

Он отвечает за:

- описание всех funnel-конфигов;
- хранение состояния one-time funnels в профиле;
- управление recurring sessions;
- генерацию безопасных `funnelSessionId`;
- логирование companion custom events;
- приём client intent событий через `ReportAnalyticsIntent`.

Почему это важно:

- логика funnel не размазана по десяти модулям;
- проще менять названия, шаги и политику сессий;
- меньше шансов сломать Creator Hub из-за разных форматов логирования.

### 2. Economy

`AnalyticsEconomyService` — это единая точка работы с economy events.

Он отвечает за:

- `Cash`, `Spins`, `ItemValue`;
- source/sink логирование;
- custom fields;
- оценку текущего баланса по каждой валюте;
- буферизацию bomb income;
- entitlement custom events.

Почему это важно:

- dashboard получает чистые и консистентные события;
- `endingBalance` считается централизованно;
- бизнес-смысл события задаётся на уровне действия, а не на уровне `AddMoney` / `DeductMoney`.

### 3. Оценка стоимости предметов

`EconomyValueUtils` нужен для `ItemValue`.

Он считает:

- reference price обычного item;
- reference price lucky block по expected value;
- value tool'а в инвентаре.

Почему это важно:

- `ItemValue` — это не "реальная валюта", а оценочная ликвидная стоимость активов игрока;
- без общего helper формула быстро разъедется по проекту и аналитика станет несопоставимой.

## Что важно помнить про Roblox Analytics

### Общие правила

- События отправляются только с сервера.
- События реально появляются только в published experience.
- В Studio funnels/economy dashboards не наполняются.

### Для funnels

- One-time funnel не должен спамиться повторно.
- Recurring funnel должен иметь `funnelSessionId`.
- `funnelSessionId` должен быть коротким.
- В проекте все session id теперь ограничены безопасным форматом, чтобы не превышать лимит Roblox в 50 символов.

### Для economy

- `amount` всегда положительный.
- `FlowType` определяет, это source или sink.
- `endingBalance` должен быть post-transaction balance именно этой валюты.

## Funnels: что заведено сейчас

### TutorialFTUE

Тип:

- `one-time`

Шаги:

1. `JoinGame`
2. `WalkToZone`
3. `ThrowBomb`
4. `PickupBrainrot`
5. `BackToSurface`
6. `PlaceBrainrot`
7. `Collect100Cash`
8. `OpenBombShop`
9. `BuyBomb2`
10. `TutorialComplete`

Где используется:

- `TutorialService`
- client intent на открытие магазина
- покупка бомбы

Почему важно:

- это главная воронка первого опыта;
- показывает, где игрок теряется уже в первые минуты;
- по ней принимаются решения по UX, темпу туториала и качеству объяснений.

Продуктовый смысл:

- если сильный дроп между `WalkToZone` и `ThrowBomb`, игрок не понял core loop;
- если дроп на `OpenBombShop`, игрок не понял, как апгрейдить бомбы;
- если дроп на `TutorialComplete`, значит финальная часть flow перегружена.

### EarlyProgressionToFirstRebirth

Тип:

- `one-time`

Шаги:

1. `TutorialComplete`
2. `FirstExtraSlotsBought`
3. `FirstSlotUpgrade`
4. `Bomb3Bought`
5. `Rebirth1`

Почему важно:

- показывает, превращается ли completed tutorial в настоящий mid-game progression;
- помогает понять, работает ли мета после FTUE;
- это мост между onboarding и long-term retention.

### BaseEconomyActivation

Тип:

- `one-time`

Шаги:

1. `FirstItemPlaced`
2. `FirstStoredCashPositive`
3. `FirstManualCollect`
4. `FirstSlotUpgradeAfterCollect`

Почему важно:

- отвечает на вопрос, понял ли игрок базовую экономику базы;
- если игрок ставит предмет, но не собирает деньги, значит loop недостаточно читаемый;
- если игрок собирает, но не апгрейдит слот, возможно upgrade не кажется ценным.

### MineRunLoop

Тип:

- `recurring`

Шаги:

1. `EnterMine`
2. `ThrowBomb`
3. `PickupBrainrot`
4. `ExitMineWithCarry`
5. `ToolGrantedOnExit`
6. `PlaceOrSellFirstItem`

Почему важно:

- это главный core gameplay loop;
- по нему видны проблемы зоны, переноски, дропа, выдачи tool и конверсии лута в прогресс.

### BombShopConversion

Тип:

- `recurring`

Шаги:

1. `ShopOpened`
2. `BombSelected`
3. `BuyPressed`
4. `PurchaseSuccess`

Почему важно:

- показывает, где ломается путь покупки новой бомбы;
- помогает отличить проблему UX от проблемы цены;
- особенно полезен для tuning progression pacing.

### StatUpgradesConversion

Тип:

- `recurring`

Шаги:

1. `UpgradesOpened`
2. `UpgradeSelected`
3. `CashBuyPressed`
4. `UpgradeSuccess`

Почему важно:

- показывает, какие апгрейды реально интересны игроку;
- помогает понять, насколько апгрейды ощущаются полезными.

### RebirthConversion

Тип:

- `recurring`

Шаги:

1. `RebirthEligible`
2. `RebirthUIOpened`
3. `RebirthPressed`
4. `RebirthSuccess`

Почему важно:

- это ключевая воронка mid/late-game;
- если много игроков eligible, но мало открывают UI, проблема в discoverability;
- если открывают UI, но не жмут rebirth, проблема в perceived cost/reward.

### DailyRewardClaim

Тип:

- `recurring`

Шаги:

1. `ClaimAvailable`
2. `DailyRewardsOpened`
3. `RewardClicked`
4. `ClaimSuccess`

Почему важно:

- помогает анализировать D1/D7 retention;
- показывает, доходят ли игроки до календаря наград и реально ли его используют.

### PlaytimeRewards

Тип:

- `recurring`

Шаги:

1. `FirstRewardClaimable`
2. `PlaytimeRewardsOpened`
3. `FirstRewardClaimed`
4. `MultipleRewardsClaimed`
5. `AllTodayClaimed`

Почему важно:

- это индикатор глубины текущей сессии;
- показывает, играют ли игроки достаточно долго, чтобы добираться до наград за время.

### DailySpin

Тип:

- `recurring`

Шаги:

1. `SpinAvailable`
2. `WheelOpened`
3. `SpinPressed`
4. `RewardGranted`

Почему важно:

- объединяет retention и emotional reward;
- показывает, понимают ли игроки, что спин доступен;
- помогает оценить интерес к wheel feature.

## Companion Custom Events

Funnels сами по себе показывают движение по шагам, но почти не объясняют, почему игрок не дошёл дальше. Для этого заведены companion custom events.

Примеры:

- `not_enough_money`
- `locked_by_previous_bomb`
- `carry_limit_reached`
- `reward_locked`
- `no_spins_available`
- `not_in_group`
- `sell_success`
- `upgrade_selected`
- `upgrade_buy_pressed`
- `bomb_shop_selection`
- `bomb_shop_buy_pressed`

Почему это важно:

- funnel говорит "где";
- custom event помогает понять "почему".

## Economy: что заведено сейчас

### Валюты

В Economy dashboard используются только три валюты:

1. `Cash`
2. `Spins`
3. `ItemValue`

### Почему только три

Потому что это те сущности, для которых можно честно посчитать баланс.

Мы сознательно не включаем в Economy dashboard:

- VIP
- ownership gamepasses
- skip products
- robux-only permanent upgrades
- ownership bombs как entitlement

Почему:

- у них нет честного wallet balance;
- они ломают интерпретацию average wallet;
- они лучше подходят под custom event формат.

## Что такое `Cash`

Это реальный баланс `profile.Data.Money`.

### Cash sources

Сейчас логируются:

- доход от взрыва бомбы;
- сбор денег со слота;
- `CollectAll`;
- продажа предметов;
- daily rewards money;
- playtime rewards money;
- group cash reward;
- cash IAP;
- деньги из pack rewards.

### Cash sinks

Сейчас логируются:

- покупка бомбы;
- покупка slot unlock;
- покупка slot level upgrade;
- cash stat upgrades;
- rebirth cost.

Почему `Cash` важен:

- это основная progression currency;
- по нему видно, достаточно ли у игрока денег;
- по нему балансируется весь early/mid-game.

## Что такое `Spins`

Это реальный баланс `profile.Data.SpinNumber`.

### Spins sources

Сейчас логируются:

- бесплатный daily spin;
- spin pack IAP;
- награда wheel в spins.

### Spins sinks

Сейчас логируются:

- сам факт прокрутки колеса.

Почему `Spins` важны:

- позволяют понимать usage wheel feature;
- полезны для анализа перехода от free spins к paid spins.

## Что такое `ItemValue`

Это оценочная ликвидная стоимость коллекционных активов игрока:

- brainrot items;
- lucky blocks.

### Как считается

Для обычного item используется reference price по sell formula:

- `floor(baseIncome * mutationMultiplier * INCOME_SCALING^(level-1) * 300)`

Для lucky block используется expected value по reward table.

### ItemValue sources

Сейчас логируются:

- выдача предметов на выходе из mine;
- reward item из daily rewards;
- reward lucky block из playtime rewards;
- group reward item;
- IAP item / random item;
- результат открытия lucky block;
- pack items.

### ItemValue sinks

Сейчас логируются:

- продажа предметов;
- consumed lucky block при открытии.

Почему `ItemValue` важен:

- даёт понимание, копят ли игроки активы или сразу ликвидируют их;
- помогает видеть pressure между "оставить на базу" и "продать";
- позволяет сравнивать reward systems по реальной ценности.

## Bomb income buffer

Доход от бомб не шлётся в аналитику на каждый взрыв.

Он буферизуется в `AnalyticsEconomyService` и флашится:

- раз в 30 секунд;
- при выходе из mine;
- при `PlayerRemoving`.

Почему это важно:

- не упираемся в rate limits;
- не забиваем dashboard шумом;
- сохраняем корректный aggregate по bomb tier.

## Custom fields

### Funnel first-step fields

На первом шаге funnel обычно отправляются:

- `tutorial_version`
- `bomb_tier`
- `rebirth_bucket`
- `vip`

В зависимости от funnel добавляются:

- `zone`
- `reward_day`
- `reward_id`
- `upgrade_id`
- `target_rebirth`

Почему это важно:

- funnels без breakdown очень быстро становятся "средней температурой";
- кастомные поля позволяют понять, где именно ломается experience.

### Economy custom fields

Часто используются:

- `feature`
- `content_id`
- `context`
- `rarity`
- `mutation`
- `reward_day`
- `reward_id`
- `bomb_tier`
- `vip`
- `rebirth_bucket`

Почему это важно:

- можно разбирать не просто "сколько денег пришло", а "откуда именно и в каком контексте".

## Чем `Onboarding` в Economy отличается от onboarding funnels

Это важный момент.

В Economy событии `Enum.AnalyticsEconomyTransactionType.Onboarding` — это просто тип транзакции.

Это не означает, что событие пойдёт в funnel dashboard.

Пример:

- group reward item в `GroupRewardController` логируется как economy source с transaction type `Onboarding`;
- это полезно для экономики, потому что награда относится к early experience;
- но это не имеет отношения к funnel type и не создаёт воронку.

## Где какие модули отвечают за аналитику

### `AnalyticsFunnelsService.lua`

Отвечает за:

- все funnel definitions;
- one-time progress в профиле;
- recurring sessions;
- client intent;
- custom failure events.

Менять здесь:

- название funnel;
- шаги funnel;
- правила session id;
- first-step breakdown fields.

### `AnalyticsEconomyService.lua`

Отвечает за:

- `LogCashSource`, `LogCashSink`;
- `LogSpinSource`, `LogSpinSink`;
- `LogItemValueSource`, `LogItemValueSink`;
- bomb income buffer;
- entitlement custom events.

Менять здесь:

- новые валюты;
- политика custom fields;
- оценка endingBalance;
- политика flush.

### `EconomyValueUtils.lua`

Отвечает за:

- reference price items;
- expected value lucky blocks;
- value tool'ов.

Менять здесь:

- только valuation logic.

### `PlayerController.lua`

Отвечает за:

- инициализацию analytics services;
- профильную persistence-часть one-time funnels;
- часть reward-driven economy events;
- group reward cash;
- pack rewards;
- entitlement gamepass events.

## Как правильно добавить новый funnel

### Шаг 1

Добавить конфиг в `AnalyticsFunnelsService.lua`.

Для one-time:

- описать шаги;
- выбрать `FunnelName`;
- если надо, привязать legacy key.

Для recurring:

- описать шаги;
- решить, когда начинается новая session;
- решить, когда её очищать.

### Шаг 2

Найти реальный серверный источник истины.

Нельзя ставить funnel только на клиентское "кажется, игрок что-то сделал", если сервер это не подтвердил.

### Шаг 3

Выбрать тип:

- `one-time`, если событие в жизни игрока происходит один раз;
- `recurring`, если это повторяемый цикл.

### Шаг 4

Определить бизнес-цель funnel:

- retention;
- progression;
- monetization;
- reward engagement.

Если цель не ясна, funnel почти наверняка будет шумным.

## Как правильно добавить новый economy event

### Правильное место

Логировать нужно в модуле бизнес-действия.

Хорошо:

- в reward controller;
- в shop purchase;
- в sell action;
- в rebirth purchase.

Плохо:

- в голом `AddMoney`;
- в голом `DeductMoney`.

Почему:

- там уже потерян смысл операции;
- нельзя нормально задать `transactionType`, `SKU`, `feature`, `context`.

### Что нужно решить заранее

1. Это `Source` или `Sink`.
2. Какая валюта.
3. Какой `transactionType`.
4. Какой `itemSKU`.
5. Каким должен быть `endingBalance`.
6. Нужно ли буферизовать событие.

## Как читать эти данные продуктово

### Если проседает `TutorialFTUE`

Смотреть:

- на каком шаге самый резкий drop;
- на каких платформах;
- с каким `bomb_tier`;
- у каких cohort.

Что делать:

- упрощать UX;
- делать шаг обязательным;
- улучшать визуальные подсказки.

### Если проседает `BombShopConversion`

Смотреть:

- открывают ли магазин;
- выбирают ли конкретную бомбу;
- жмут ли buy;
- хватает ли денег.

Что делать:

- править ценообразование;
- улучшать shop UI;
- снижать friction progression.

### Если `Cash` растёт быстрее, чем тратится

Это признак инфляции.

Что можно делать:

- добавить новые sinks;
- увеличить usefulness upgrades;
- пересмотреть стоимость rebirth / slot unlock / bomb progression.

### Если `ItemValue` сильно растёт, а продажи слабые

Это может значить:

- игроки предпочитают держать всё на базе;
- продажа кажется невыгодной;
- экономика базы слишком доминирует над sell loop.

### Если `Spins` часто выдаются, но мало тратятся

Это значит:

- wheel плохо заметен;
- reward expectation слабая;
- UI не мотивирует открыть feature.

## Самые частые причины, почему аналитика "не работает"

### События не видны в Creator Hub

Проверь:

- игра опубликована;
- тест идёт не в Studio;
- выбран правильный date range;
- funnel name не менялся посреди анализируемого периода;
- step names не поменялись неожиданно.

### Ошибка с `funnelSessionId`

Причина:

- строка слишком длинная.

Что уже сделано:

- в проекте session ids укорочены и проходят через централизованный helper.

### Funnel не считается как надо

Возможные причины:

- шаг шлётся не с сервера;
- шаг логируется слишком рано;
- повторный шаг приходит раньше нужного;
- recurring session стартует не там, где игрок реально начал цикл.

### Economy dashboard выглядит странно

Проверь:

- корректен ли `endingBalance`;
- не отправляются ли события из низкоуровневых `AddMoney` / `DeductMoney`;
- не включили ли entitlement как валюту;
- не идёт ли шумный high-frequency source без буфера.

## Практические правила для команды

1. Любой новый funnel добавлять только через `AnalyticsFunnelsService`.
2. Любой новый economy event добавлять только через `AnalyticsEconomyService`.
3. Не логировать деньги/траты в `AddMoney` и `DeductMoney`.
4. Не отправлять аналитические события с клиента напрямую.
5. Любая recurring feature должна иметь короткий и стабильный `funnelSessionId`.
6. Любая новая reward feature должна сразу иметь product question:
   "Что мы хотим понять по этой фиче?"

## Мини-чеклист перед выкладкой

- Все analytics вызовы идут с сервера.
- Funnel names не пустые.
- `funnelSessionId` не превышает лимит Roblox.
- One-time funnel не дублируется при reconnect.
- Reward flows не отправляют шумных лишних событий.
- `endingBalance` соответствует post-transaction состоянию.
- Date range после выкладки выставлен от даты изменения funnel.

## Итог

Текущая аналитика в проекте покрывает:

- onboarding;
- ранний progression;
- основной mine loop;
- базовую экономику;
- магазин бомб;
- апгрейды;
- rebirth;
- daily rewards;
- playtime rewards;
- daily spin;
- игровую экономику по трем валютам;
- custom events по причинам фейлов и entitlement-событиям.

Это уже не "базовая телеметрия", а рабочая продуктовая система, по которой можно:

- искать реальные точки дропа;
- балансировать экономику;
- принимать решения по UX;
- оценивать ценность rewards и monetization features;
- сравнивать разные сегменты игроков.
