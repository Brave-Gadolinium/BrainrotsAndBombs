# Project Configurations

Config: FriendBoostConfiguration

Location:
- `src/ReplicatedStorage/Modules/FriendBoostConfiguration.lua`

Purpose:
- Maps online friend count to passive income multiplier

Parameters:
- `0 friends -> x1`
- `1 friend -> x2`
- `2 friends -> x3`
- `3 friends -> x4`
- continues linearly for higher counts

Used by:
- `FriendBoostController`

Config: OfflineIncomeConfiguration

Location:
- `src/ReplicatedStorage/Modules/OfflineIncomeConfiguration.lua`

Purpose:
- Stores offline reward rules and timers

Parameters:
- `MinimumOfflineSeconds = 60`
- `MaxOfflineSeconds = 1800`
- `Play15Seconds = 900`
- `RobuxMultiplier = 5`
- `Play15Multiplier = 5`
- `ProductKey = OfflineIncomeX5`

Used by:
- `OfflineIncomeController`
- `OfflineIncomeUIController`

Config: ProductConfigurations.Group

Location:
- `src/ReplicatedStorage/Modules/ProductConfigurations.lua`

Purpose:
- Defines the creator-group id and the item granted by the group/join reward flow

Parameters:
- `Id = 222755422`
- `Reward.Name = bombombini_gusini`
- `Reward.Mutation = Normal`
- `Reward.Level = 1`

Used by:
- `GroupRewardController`
- `JoinLikeStandController`
- `GroupRewardController.client.lua`

Config: ProductConfigurations.Products.OfflineIncomeX5

Location:
- `src/ReplicatedStorage/Modules/ProductConfigurations.lua`

Purpose:
- Developer product id for the paid x5 offline reward claim

Parameters:
- `3575770865`

Used by:
- `OfflineIncomeUIController`
- `OfflineIncomeController`
- `MonetizationController`

Config: DailyRewardConfiguration

Location:
- `src/ReplicatedStorage/Modules/DailyRewardConfiguration.lua`

Purpose:
- Defines the 7-day reward calendar and now resolves bomb reward images for pickaxe days from `BombsConfigurations`

Parameters:
- `Rewards[3].PickaxeName = Bomb 7`
- `Rewards[7].PickaxeName = Bomb 13`
- money, random-item, and pickaxe reward payloads for each daily slot

Used by:
- `DailyRewardController`
- `DailyRewardUIController`

Config: PlaytimeRewardConfiguration

Location:
- `src/ReplicatedStorage/Modules/PlaytimeRewardConfiguration.lua`

Purpose:
- Defines the canonical per-day timed reward list rendered by the playtime reward UI and consumed by the server reward manager

Parameters:
- `Rewards[1..12]` with `RequiredSeconds`, `Type`, and image metadata
- reward types `Money` and `LuckyBlock`

Used by:
- `PlaytimeRewardController`
- `PlaytimeRewardUIController`
- `PlaytimeRewardManager`

Config: QuestChainConfiguration

Location:
- `src/ReplicatedStorage/Modules/QuestChainConfiguration.lua`

Purpose:
- Defines quest-chain ordering, targets, text, and money reward amounts shown in the right-side quest HUD and granted by the server quest service

Parameters:
- `ActiveSlots = 3`
- per-quest `Id`, `Type`, `Target`, `Text`, and `Reward`

Used by:
- `QuestChainService`
- `QuestChainUIController`
- `ManualTestController`

Config: SlotUnlockConfigurations

Location:
- `src/ReplicatedStorage/Modules/SlotUnlockConfigurations.lua`

Purpose:
- Defines how many base slots each upgrade unlocks and how much each slot-upgrade purchase costs

Parameters:
- `StartSlots = 10`
- `SlotsPerUpgrade = 2`
- `new_slots[1].money_req = 0`
- `MaxSlots = 30`

Used by:
- `PlotManager.server.lua`

Config: TutorialConfiguration

Location:
- `src/ReplicatedStorage/Modules/TutorialConfiguration.lua`

Purpose:
- Defines FTUE steps, guided targets, and per-step presentation rules such as masking, guided frames, and allowed tutorial buttons.

Parameters:
- `FinalStep = 13`
- `CashGoal = 5`
- `TutorialCharacterUpgradeId = Speed1`
- `TutorialBaseUpgradeMode = FirstSlotUnlock`
- `BaseUpgradeApproachDistance = 20`

Used by:
- `TutorialService`
- `OnboardingController`
- `UIInitializer`
- `QuestChainUIController`
- `CollectionZoneController`
- `MiningController`

Config: TutorialUiConfiguration

Location:
- `src/ReplicatedStorage/Modules/TutorialUiConfiguration.lua`

Purpose:
- Centralizes FTUE UI exceptions that should not be hardcoded inside `OnboardingController`, including retry targets for delayed tutorial buttons and special visibility restore rules.

Parameters:
- `PersistentMoneyStartStep = 6`
- `RetryTargetsByStep` for delayed controls like bomb-buy, character-upgrade, and base-upgrade buttons
- `PreserveOriginalVisibilityTargets` for controls such as the base-upgrade surface button

Used by:
- `TutorialConfiguration`
- `OnboardingController`

Config: XrayBonusConfiguration

Location:
- `src/ReplicatedStorage/Modules/XrayBonusConfiguration.lua`

Purpose:
- Controls xRay bonus spawn behavior and client-side brainrot highlight visuals

Parameters:
- `Enabled = true`
- `HighlightRadius = 100`
- `SpawnChancePerRound = 1`
- `InitialSpawnDelaySeconds = 12`
- `UseNearestBeam = true`

Used by:
- `XrayBonusService`
- `XrayBonusController`
