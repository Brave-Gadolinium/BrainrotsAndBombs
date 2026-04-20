# Services

Service: PlayerController

Location:
- `src/ServerScriptService/Controllers/PlayerController.lua`

Responsibility:
- Profile lifecycle, public player attributes, entitlement sync, inventory loading, session timestamps, and persisted candy balances

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

Service: CandyEventService

Location:
- `src/ServerScriptService/Modules/CandyEventService.lua`

Responsibility:
- Run the hourly candy event, spawn touch-collectible candies in mine zones, keep candy wheel remotes in sync, and grant wheel rewards

Main Features:
- Spawns live mine candies only during the active hourly window and clears them again on round/event end
- Awards `CandyCount` immediately on touch pickup and fires the shared `ShowCandyPopUp` UI event for `+1` feedback
- Applies a `90` degree yaw to spawned candy models and tags them with the existing `Rotate` world-animation flow for hover/rotation feedback
- Keeps candy-wheel reward fulfillment authoritative on the server after the client spin animation delay

Dependencies:
- `PlayerController`
- `ItemManager`
- `CandyEventConfiguration`
- `MineSpawnUtils`
- `ItemConfigurations`
- `UpgradesConfigurations`
- `BadgeManager`

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

Main Features:
- Repairs invalid FTUE rejoin states, including returning step `4`/`5` players to brainrot pickup when the carried or inventory item is gone
- Advances mine-exit step `4 -> 5` only after the carried brainrot is actually present in `Character` or `Backpack`, and immediately re-evaluates back to pickup if that conversion fails
- Computes `PostTutorialStage` from live player state after FTUE completion using the `Speed1` purchase and first base-slot upgrade thresholds
- Fires the post-tutorial character/base completion prompts only from the matching purchase events, not from passive recomputation

Dependencies:
- `PlayerController`
- `TutorialConfiguration`
- `PostTutorialConfiguration`
- `SlotUnlockConfigurations`
- `UpgradesConfigurations`
- `AnalyticsFunnelsService`

Service: CarrySystem

Location:
- `src/ServerScriptService/Modules/CarrySystem.lua`

Responsibility:
- Own mine carry stacks, convert carried brainrots into backpack tools on zone exit, and reserve forced drop paths for system-driven cases only

Main Features:
- Tracks carried brainrot visuals and capacity while players are inside mine zones
- Converts carried brainrots into tool inventory on zone exit and now treats manual player drop requests as disabled
- Finishes carry-stack cleanup before FTUE mine-exit evaluation so walking out of the mine and using `Back` produce the same tutorial brainrot state
- Keeps internal forced-drop methods for gameplay systems such as bomb failures, event recovery, and other authoritative server flows
