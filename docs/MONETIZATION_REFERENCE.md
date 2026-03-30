# Monetization Reference

Этот файл нужен как рабочая карта монетизации для Roblox Dashboard и последующей синхронизации `id` в коде.

Что включено:
- все `Developer Product`
- все `Game Pass`
- все Robux-upgrade продукты
- все места, где покупка вызывается не из централизованного конфига

Что не включено как платная монетизация:
- `ProductConfigurations.Group` с наградой за вступление в группу, потому что это social reward, а не платный продукт

## Важные предупреждения

- В текущем коде есть конфликтующие `Developer Product ID`.
- `3555241775` одновременно используется для `PlaytimeRewardsSkipAll`, `DailyRewardsSkipAll` и `DailyRewardsSkip1`.
- `3563204131` одновременно используется для `PlaytimeRewardsSpeedX2` и `PlaytimeRewardsSpeedX5`.
- Сервер мапит покупку через `ProductConfigurations.GetProductById(id)`, поэтому у разных продуктов должны быть уникальные `id`, иначе может выдаться не тот эффект.
- `Collect All` gamepass захардкожен в двух местах и не лежит в `ProductConfigurations`.
- В `Interactions.client.lua` есть покупки через атрибут `Product` на объектах с тегом `Rotate`; их `id` нужно искать и менять в Studio/Explorer у самих объектов.

## Центральные файлы монетизации

- `src/ReplicatedStorage/Modules/ProductConfigurations.lua`
- `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua`
- `src/ServerScriptService/Controllers/MonetizationController.lua`
- `src/ServerScriptService/Controllers/PlayerController.lua`
- `src/ServerScriptService/PlotManager.server.lua`
- `src/StarterPlayer/StarterPlayerScripts/Interactions.client.lua`

## Game Passes

| Key | Dashboard name | Type | Current ID | What it gives | Where ID is stored | Where it is used |
| --- | --- | --- | --- | --- | --- | --- |
| `VIP` | `VIP: Brainrot Tycoon Club` | Game Pass | `1772898056` | Даёт VIP-статус и `+50%` income multiplier ко всему доходу базы. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | Проверка и выдача статуса: `src/ServerScriptService/Controllers/PlayerController.lua`; применение бонуса: `src/ServerScriptService/Controllers/IncomeController.lua` |
| `StarterPack` | `Starter Pack: Surface Jumpstart` | Game Pass | `1772874155` | Одноразовый пак: `$5,000`, `Blue`, `Green`. Если геймпасс уже куплен, награда довыдаётся при входе, если ещё не была отмечена в сохранении. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача награды: `src/ServerScriptService/Controllers/PlayerController.lua` |
| `ProPack` | `Pro Pack: Deep Mine Boost` | Game Pass | `1772382058` | Одноразовый пак: `$50,000`, `Yellow`, `Pink`. Также довыдаётся при входе, если право уже есть. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача награды: `src/ServerScriptService/Controllers/PlayerController.lua` |
| `CollectAll` | `Collect All: Auto Cash Sweep` | Game Pass | `1773588081` | Открывает кнопку/касание `Collect All` на базе: игрок может одним действием собрать весь накопленный доход со слотов. | Захардкожен в `src/ServerScriptService/PlotManager.server.lua` и `src/ServerScriptService/Controllers/PlayerController.lua` | Проверка владения и prompt: `src/ServerScriptService/PlotManager.server.lua`; аналитика покупки: `src/ServerScriptService/Controllers/PlayerController.lua` |

## Developer Products

| Key | Dashboard name | Type | Current ID | What it gives | Where ID is stored | Where it is used |
| --- | --- | --- | --- | --- | --- | --- |
| `SkipRebirth` | `Instant Rebirth: Rift Reset` | Developer Product | `3566500447` | Мгновенно делает rebirth без проверки обычных требований и без траты требуемого cash. Сбрасывает upgrade-статы как обычный rebirth и увеличивает `Rebirths`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/RebirthScript.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `RandomItem` | `Mystery Brainrot Crate` | Developer Product | `3566503229` | Выдаёт случайный Brainrot из пула, где исключены `Common` и `Uncommon`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | HUD-кнопка: `src/StarterPlayer/StarterPlayerScripts/HUDController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `PlaytimeRewardsSkipAll` | `Playtime Rush: Unlock All` | Developer Product | `3566503314` | Для текущего playtime-цикла выставляет прогресс времени на максимум и открывает все playtime rewards за день для claim. Не клеймит их автоматически. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/PlaytimeRewardUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Controllers/PlaytimeRewardController.lua` |
| `PlaytimeRewardsSpeedX2` | `Playtime Turbo x2` | Developer Product | `3566508646` | Ускоряет накопление времени playtime rewards в `2x`. По текущей логике это выглядит как постоянный unlock, потому что флаг `HasSpeedX2` не сбрасывается при смене дня. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/PlaytimeRewardUIController.client.lua`; логика: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Modules/PlaytimeRewardManager.lua` |
| `PlaytimeRewardsSpeedX5` | `Playtime Warp x5` | Developer Product | `3566508747` | Ускоряет накопление времени playtime rewards в `5x`. По текущей логике тоже выглядит как постоянный unlock. Если куплены оба ускорителя, применяется `x5`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/PlaytimeRewardUIController.client.lua`; логика: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Modules/PlaytimeRewardManager.lua` |
| `DailyRewardsSkipAll` | `Daily Ladder: Unlock All Days` | Developer Product | `3566509090` | Открывает все оставшиеся дни текущего daily rewards цикла для claim. Не клеймит награды автоматически. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/DailyRewardUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Controllers/DailyRewardController.lua` |
| `DailyRewardsSkip1` | `Daily Ladder: Unlock Next Day` | Developer Product | `3566509199` | Открывает только ближайший следующий ещё неоткрытый день daily rewards цикла. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/DailyRewardUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Controllers/DailyRewardController.lua` |
| `ItemProduct1` | `Brainrot Drop: Purple` | Developer Product | `3566509625` | Выдаёт предмет `Purple`, `Normal`, `Level 1`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `ItemProduct2` | `Brainrot Drop: Orange` | Developer Product | `3566510433` | Выдаёт предмет `Orange`, `Normal`, `Level 1`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `ItemProduct3` | `Brainrot Drop: Brown` | Developer Product | `3566510878` | Выдаёт предмет `Brown`, `Normal`, `Level 1`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `CashProduct1` | `Cash Burst: 10K` | Developer Product | `3566511291` | Начисляет `$10,000`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `CashProduct2` | `Cash Burst: 100K` | Developer Product | `3566511557` | Начисляет `$100,000`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `CashProduct3` | `Cash Burst: 1M` | Developer Product | `3566511657` | Начисляет `$1,000,000`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `SpinsX3` | `Spin Pack: Triple Shot` | Developer Product | `3566512371` | Добавляет `+3` spins для daily spin. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/DailySpinUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `SpinsX9` | `Spin Pack: Mega Nine` | Developer Product | `3566513791` | Добавляет `+9` spins для daily spin. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/DailySpinUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |

## Robux Upgrade Products

Это тоже `Developer Product`, но они лежат не в `ProductConfigurations`, а в `UpgradesConfigurations.Upgrades[*].RobuxProductId`.

| Upgrade ID | Dashboard name | Type | Current ID | What it gives | Where ID is stored | Where it is used |
| --- | --- | --- | --- | --- | --- | --- |
| `Range1` | `Upgrade Spark: +1 Range` | Developer Product | `3555196998` | Даёт `+1` к `BonusRange`. `HiddenInUI = true`, то есть сейчас этот продукт не показывается в обычном апгрейд-окне, но сервер умеет его обработать. | `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua` | Выдача: `src/ServerScriptService/Controllers/MonetizationController.lua`; UI-логика: `src/StarterPlayer/StarterPlayerScripts/UpgradesUIController.client.lua` |
| `Range3` | `Upgrade Burst: +3 Range` | Developer Product | `3555197053` | Даёт `+3` к `BonusRange`. Тоже скрыт в стандартном UI. | `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua` | Выдача: `src/ServerScriptService/Controllers/MonetizationController.lua`; UI-логика: `src/StarterPlayer/StarterPlayerScripts/UpgradesUIController.client.lua` |
| `Carry1` | `Upgrade Grip: +1 Carry Slot` | Developer Product | `3555197134` | Даёт `+1` к `CarryCapacity`. Видим в UI. | `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua` | Выдача: `src/ServerScriptService/Controllers/MonetizationController.lua`; UI: `src/StarterPlayer/StarterPlayerScripts/UpgradesUIController.client.lua` |
| `Speed1` | `Upgrade Dash: +1 Walk Speed` | Developer Product | `3555197217` | Даёт `+1` к `BonusSpeed`. Видим в UI. | `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua` | Выдача: `src/ServerScriptService/Controllers/MonetizationController.lua`; UI: `src/StarterPlayer/StarterPlayerScripts/UpgradesUIController.client.lua` |

## Покупки вне центрального конфига

### 1. `Collect All` gamepass

- Тип: `Game Pass`
- Current ID: `1736841051`
- Где менять:
- `src/ServerScriptService/PlotManager.server.lua`
- `src/ServerScriptService/Controllers/PlayerController.lua`
- Важно:
- это не лежит в `ProductConfigurations.GamePasses`
- если поменяешь только в одном месте, логика покупки и аналитика разъедутся

### 2. `Rotate`-объекты с атрибутом `Product`

- Тип: зависит от того, какой `ProductId` выставлен на объекте, но по коду вызывается именно `PromptProductPurchase`, то есть ожидается `Developer Product`
- Current ID: не хранится в исходниках как константа
- Где искать:
- `src/StarterPlayer/StarterPlayerScripts/Interactions.client.lua`
- В Studio у объектов с тегом `Rotate`
- На каждом таком объекте смотри атрибут `Product`
- Важно:
- в коде нет проверки `if not ProductId then continue end`, строка закомментирована
- если на `Rotate`-объекте атрибут пустой или неправильный, prompt может работать некорректно
- после замены `id` в Studio этот файл менять не нужно, если механика останется через атрибут

## Конфликты ID, которые обязательно надо разнести

| Current ID | Conflicting keys | Why it is a problem |
| --- | --- | --- |
| `3555241775` | `PlaytimeRewardsSkipAll`, `DailyRewardsSkipAll`, `DailyRewardsSkip1` | Сервер не сможет надёжно понять, какой именно продукт куплен |
| `3563204131` | `PlaytimeRewardsSpeedX2`, `PlaytimeRewardsSpeedX5` | `x2` и `x5` не должны делить один `Developer Product ID` |

## Как лучше менять ID

- Для обычных продуктов меняй значения в `src/ReplicatedStorage/Modules/ProductConfigurations.lua`.
- Для Robux-upgrades меняй `RobuxProductId` в `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua`.
- Для `Collect All` меняй `1736841051` сразу в двух файлах:
- `src/ServerScriptService/PlotManager.server.lua`
- `src/ServerScriptService/Controllers/PlayerController.lua`
- Для `Rotate`-покупок меняй атрибут `Product` у объектов в Studio.

## Что потом можно будет синхронизировать автоматически

Когда ты заменишь `id` в этом документе или просто пришлёшь мне список новых `id`, я смогу обновить:

- `ProductConfigurations.Products`
- `ProductConfigurations.GamePasses`
- `UpgradesConfigurations.Upgrades[*].RobuxProductId`
- hardcoded `Collect All` gamepass

