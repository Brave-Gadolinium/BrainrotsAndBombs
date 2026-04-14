# Services

Service: PlayerController

Location:
- `src/ServerScriptService/Controllers/PlayerController.lua`

Responsibility:
- Profile lifecycle, public player attributes, entitlement sync, inventory loading, and session timestamps

Dependencies:
- `ProfileStore`
- `SlotManager`
- `OfflineIncomeController`
- `ItemManager`

Service: IncomeController

Location:
- `src/ServerScriptService/Controllers/IncomeController.lua`

Responsibility:
- Tick passive slot income and update collect labels on player plots

Dependencies:
- `PlayerController`
- `IncomeCalculationUtils`
- `ItemConfigurations`

Service: FriendBoostController

Location:
- `src/ServerScriptService/Controllers/FriendBoostController.lua`

Responsibility:
- Recalculate online-friend counts per player and expose `FriendBoostCount` / `FriendBoostMultiplier`

Dependencies:
- `FriendBoostConfiguration`

Service: OfflineIncomeController

Location:
- `src/ServerScriptService/Controllers/OfflineIncomeController.lua`

Responsibility:
- Convert elapsed offline time into a pending reward, expose offline status remotes, run `Play15` timers, and pay offline reward claims

Dependencies:
- `PlayerController`
- `OfflineIncomeConfiguration`
- `IncomeCalculationUtils`
- `ProductConfigurations`
- `AnalyticsEconomyService`

Service: MonetizationController

Location:
- `src/ServerScriptService/Controllers/MonetizationController.lua`

Responsibility:
- Process developer product receipts and route each product to its gameplay reward system

Dependencies:
- `OfflineIncomeController`
- `PlaytimeRewardController`
- `DailyRewardController`
- `RebirthSystem`
