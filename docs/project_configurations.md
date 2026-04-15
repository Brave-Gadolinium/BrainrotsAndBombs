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
- `MaxOfflineSeconds = 28800`
- `Play15Seconds = 900`
- `RobuxMultiplier = 5`
- `Play15Multiplier = 5`
- `ProductKey = OfflineIncomeX5`

Used by:
- `OfflineIncomeController`
- `OfflineIncomeUIController`

Config: ProductConfigurations.Products.OfflineIncomeX5

Location:
- `src/ReplicatedStorage/Modules/ProductConfigurations.lua`

Purpose:
- Developer product placeholder for the paid x5 offline reward claim

Parameters:
- default `0` until the real product id is assigned

Used by:
- `OfflineIncomeUIController`
- `OfflineIncomeController`
- `MonetizationController`

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
