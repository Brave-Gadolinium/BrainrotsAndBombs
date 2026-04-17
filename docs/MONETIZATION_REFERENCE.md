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

- В текущем коде сервер мапит покупку через `ProductConfigurations.GetProductById(id)`, поэтому у разных продуктов должны быть уникальные `id`, иначе может выдаться не тот эффект.
- В этом снимке кода конфликты `Developer Product ID`, которые раньше были у playtime/daily продуктов, уже разведены.
- `Collect All` gamepass теперь хранится в `ProductConfigurations.GamePasses.CollectAll`, а серверные проверки подтягивают `id` оттуда.
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
| `VIP` | `VIP: Brainrot Tycoon Club` | Game Pass | `1782060480` | Даёт VIP-статус и `+50%` income multiplier ко всему доходу базы. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | Проверка и выдача статуса: `src/ServerScriptService/Controllers/PlayerController.lua`; применение бонуса: `src/ServerScriptService/Controllers/IncomeController.lua` |
| `StarterPack` | `Starter Pack: Surface Jumpstart` | Game Pass | `1781448453` | Одноразовый пак: `$5,000`, `Blue`, `Green`. Если геймпасс уже куплен, награда довыдаётся при входе, если ещё не была отмечена в сохранении. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача награды: `src/ServerScriptService/Controllers/PlayerController.lua` |
| `ProPack` | `Pro Pack: Deep Mine Boost` | Game Pass | `1780452467` | Одноразовый пак: `$50,000`, `Yellow`, `Pink`. Также довыдаётся при входе, если право уже есть. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача награды: `src/ServerScriptService/Controllers/PlayerController.lua` |
| `CollectAll` | `Collect All` | Game Pass | `1783037385` | Открывает кнопку/касание `Collect All` на базе: игрок может одним действием собрать весь накопленный доход со слотов. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | Проверка владения и prompt: `src/ServerScriptService/PlotManager.server.lua`; аналитика покупки: `src/ServerScriptService/Controllers/PlayerController.lua` |

## Developer Products

| Key | Dashboard name | Type | Current ID | What it gives | Where ID is stored | Where it is used |
| --- | --- | --- | --- | --- | --- | --- |
| `SkipRebirth` | `Skip Rebirth` | Developer Product | `3567801357` | Мгновенно делает rebirth без проверки обычных требований и без траты требуемого cash. Сбрасывает upgrade-статы как обычный rebirth и увеличивает `Rebirths`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/RebirthScript.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `RandomItem` | `Mystery Brainrot Crate` | Developer Product | `3567801988` | Выдаёт случайный Brainrot из пула, где исключены `Common` и `Uncommon`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | HUD-кнопка: `src/StarterPlayer/StarterPlayerScripts/HUDController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `PlaytimeRewardsSkipAll` | `Playtime Rush: Unlock All` | Developer Product | `3567801859` | Для текущего playtime-цикла выставляет прогресс времени на максимум и открывает все playtime rewards за день для claim. Не клеймит их автоматически. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/PlaytimeRewardUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Controllers/PlaytimeRewardController.lua` |
| `PlaytimeRewardsSpeedX2` | `Playtime Turbo x2` | Developer Product | `3567801697` | Ускоряет накопление времени playtime rewards в `2x`. По текущей логике это выглядит как постоянный unlock, потому что флаг `HasSpeedX2` не сбрасывается при смене дня. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/PlaytimeRewardUIController.client.lua`; логика: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Modules/PlaytimeRewardManager.lua` |
| `PlaytimeRewardsSpeedX5` | `Playtime Warp x5` | Developer Product | `3567801499` | Ускоряет накопление времени playtime rewards в `5x`. По текущей логике тоже выглядит как постоянный unlock. Если куплены оба ускорителя, применяется `x5`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/PlaytimeRewardUIController.client.lua`; логика: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Modules/PlaytimeRewardManager.lua` |
| `DailyRewardsSkipAll` | `Daily Ladder: Unlock All Days` | Developer Product | `3567802250` | Открывает все оставшиеся дни текущего daily rewards цикла для claim. Не клеймит награды автоматически. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/DailyRewardUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Controllers/DailyRewardController.lua` |
| `DailyRewardsSkip1` | `Daily Ladder: Unlock Next Day` | Developer Product | `3567802115` | Открывает только ближайший следующий ещё неоткрытый день daily rewards цикла. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/DailyRewardUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` и `src/ServerScriptService/Controllers/DailyRewardController.lua` |
| `ItemProduct1` | `Brainrot Drop: Rare` | Developer Product | `3567803285` | Сейчас использует reward mapping из `ProductConfigurations.ItemProductRewards["ItemProduct1"]`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `ItemProduct2` | `Brainrot Drop: Gold` | Developer Product | `3567803643` | Сейчас использует reward mapping из `ProductConfigurations.ItemProductRewards["ItemProduct2"]`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `ItemProduct3` | `Brainrot Drop: Brainrot Mythic` | Developer Product | `3567803372` | Сейчас использует reward mapping из `ProductConfigurations.ItemProductRewards["ItemProduct3"]`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `CashProduct1` | `Cash Burst: 10K` | Developer Product | `3567802668` | Начисляет `$10,000`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `CashProduct2` | `Cash Burst: 100K` | Developer Product | `3567803042` | Начисляет `$100,000`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `CashProduct3` | `Cash Burst: 1M` | Developer Product | `3567802511` | Начисляет `$1,000,000`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI магазина: `src/StarterPlayer/StarterPlayerScripts/ShopController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `SpinsX3` | `Spin Pack: Triple Shot` | Developer Product | `3567801026` | Добавляет `+3` spins для daily spin. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/DailySpinUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `SpinsX9` | `Spin Pack: Mega Nine` | Developer Product | `3567801177` | Добавляет `+9` spins для daily spin. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | UI: `src/StarterPlayer/StarterPlayerScripts/DailySpinUIController.client.lua`; выдача: `src/ServerScriptService/Controllers/MonetizationController.lua` |

## Robux Upgrade Products

Это тоже `Developer Product`, но они лежат не в `ProductConfigurations`, а в `UpgradesConfigurations.Upgrades[*].RobuxProductId`.

| Upgrade ID | Dashboard name | Type | Current ID | What it gives | Where ID is stored | Where it is used |
| --- | --- | --- | --- | --- | --- | --- |
| `Range1` | `Upgrade Spark: +1 Range` | Developer Product | `3555196998` | Даёт `+1` к `BonusRange`. `HiddenInUI = true`, то есть сейчас этот продукт не показывается в обычном апгрейд-окне, но сервер умеет его обработать. | `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua` | Выдача: `src/ServerScriptService/Controllers/MonetizationController.lua`; UI-логика: `src/StarterPlayer/StarterPlayerScripts/UpgradesUIController.client.lua` |
| `Range3` | `Upgrade Burst: +3 Range` | Developer Product | `3555197053` | Даёт `+3` к `BonusRange`. Тоже скрыт в стандартном UI. | `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua` | Выдача: `src/ServerScriptService/Controllers/MonetizationController.lua`; UI-логика: `src/StarterPlayer/StarterPlayerScripts/UpgradesUIController.client.lua` |
| `Carry1` | `Upgrade Grip: +1 Carry Slot` | Developer Product | `3567800676` | Даёт `+1` к `CarryCapacity`. Видим в UI. | `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua` | Выдача: `src/ServerScriptService/Controllers/MonetizationController.lua`; UI: `src/StarterPlayer/StarterPlayerScripts/UpgradesUIController.client.lua` |
| `Speed1` | `Upgrade Dash: +1 Walk Speed` | Developer Product | `3567800914` | Даёт `+1` к `BonusSpeed`. Видим в UI. | `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua` | Выдача: `src/ServerScriptService/Controllers/MonetizationController.lua`; UI: `src/StarterPlayer/StarterPlayerScripts/UpgradesUIController.client.lua` |

## Покупки вне центрального конфига

### 1. `Collect All` gamepass

- Тип: `Game Pass`
- Current ID: `1783037385`
- Где менять:
- `src/ReplicatedStorage/Modules/ProductConfigurations.lua`
- Важно:
- серверные проверки в `src/ServerScriptService/PlotManager.server.lua` и `src/ServerScriptService/Controllers/PlayerController.lua` читают `id` из `ProductConfigurations.GamePasses.CollectAll`
- если меняешь `id`, достаточно обновить его в `ProductConfigurations.GamePasses`

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

## Конфликты ID

- На текущем наборе значений в `src` явных конфликтов `Developer Product ID` не осталось.

## Как лучше менять ID

- Для обычных продуктов меняй значения в `src/ReplicatedStorage/Modules/ProductConfigurations.lua`.
- Для Robux-upgrades меняй `RobuxProductId` в `src/ReplicatedStorage/Modules/UpgradesConfigurations.lua`.
- Для `Collect All` меняй `ProductConfigurations.GamePasses.CollectAll` в `src/ReplicatedStorage/Modules/ProductConfigurations.lua`.
- Для `Rotate`-покупок меняй атрибут `Product` у объектов в Studio.

## Что потом можно будет синхронизировать автоматически

Когда ты заменишь `id` в этом документе или просто пришлёшь мне список новых `id`, я смогу обновить:

- `ProductConfigurations.Products`
- `ProductConfigurations.GamePasses`
- `UpgradesConfigurations.Upgrades[*].RobuxProductId`
- server-side ссылки на `Collect All` gamepass
## Candy Wheel Additions

| Key | Type | Current ID | What it gives | Where ID is stored | Where it is used |
| --- | --- | --- | --- | --- | --- |
| `CandySpinsX3` | Developer Product | `3577073654` | Adds `+3` paid candy spins used as fallback when `CandyCount < 20`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | `src/StarterPlayer/StarterPlayerScripts/CandySpinController.client.lua`; `src/ServerScriptService/Controllers/MonetizationController.lua` |
| `CandySpinsX9` | Developer Product | `3577073717` | Adds `+9` paid candy spins used as fallback when `CandyCount < 20`. | `src/ReplicatedStorage/Modules/ProductConfigurations.lua` | `src/StarterPlayer/StarterPlayerScripts/CandySpinController.client.lua`; `src/ServerScriptService/Controllers/MonetizationController.lua` |
