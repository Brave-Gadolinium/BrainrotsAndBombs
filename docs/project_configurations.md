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
