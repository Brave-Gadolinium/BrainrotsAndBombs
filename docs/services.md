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

Service: PlaytimeRewardController

Location:
- `src/ServerScriptService/Controllers/PlaytimeRewardController.lua`

Responsibility:
- Expose playtime reward remotes, tick daily playtime progress, and grant/claim timed rewards without losing claimability on reward-grant failure

Dependencies:
- `PlayerController`
- `PlaytimeRewardManager`
- `ItemManager`
- `AnalyticsFunnelsService`
- `AnalyticsEconomyService`

Service: GroupRewardController

Location:
- `src/ServerScriptService/Modules/GroupRewardController.lua`

Responsibility:
- Validate creator-group membership, grant the join reward, and only mark the reward claimed after the item grant succeeds

Dependencies:
- `PlayerController`
- `ItemManager`
- `ProductConfigurations`
- `AnalyticsFunnelsService`
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

Service: TerrainGeneratorManager

Location:
- `src/ServerScriptService/Modules/TerrainGeneratorManager.lua`

Responsibility:
- Normalize the mine terrain baseline on server start, snapshot voxel chunks, and restore only dirty terrain chunks when a round ends

Dependencies:
- `Workspace.Terrain`
- `Workspace.Mines`
- `ReplicatedStorage.Remotes.Timer.FinishTime`
- `BombManager`
- `ItemManager`

Service: TutorialService

Location:
- `src/ServerScriptService/Modules/TutorialService.lua`

Responsibility:
- Own FTUE/post-tutorial progression, reconcile onboarding steps with the live player state, and sync tutorial attributes/events

Dependencies:
- `PlayerController`
- `TutorialConfiguration`
- `PostTutorialConfiguration`
- `SlotUnlockConfigurations`
- `UpgradesConfigurations`
- `AnalyticsFunnelsService`
