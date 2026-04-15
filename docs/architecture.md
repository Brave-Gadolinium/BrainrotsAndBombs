# Architecture

Pattern:
- Service-controller style Roblox architecture with shared modules in `ReplicatedStorage.Modules`

Server systems:
- `PlayerController` owns profile loading, public player state, entitlements, and lifecycle hooks
- `IncomeController` owns passive slot income ticks
- `FriendBoostController` owns online-friend boost recalculation
- `OfflineIncomeController` owns pending offline reward calculation, claim state, and reward payout
- `MonetizationController` owns developer product receipts and paid reward fulfillment
- `PlotManager.server.lua` owns runtime plot spawning, stamps each player plot with ownership/base identity attributes, and plays the temporary `UpgradeBase` floor effect after slot upgrades
- `TerrainGeneratorManager` owns mine terrain baseline snapshots and restores only dirty chunks at round end while keeping the fixed timer flow unchanged

Client systems:
- `BombCameraController` owns the temporary bomb follow camera, FOV handoff, blast punch, and immediate recovery when the Roblox menu opens after FTUE completion
- `HUDController` owns HUD money, offline-per-hour, invite prompt, and boost labels
- `OnboardingController` owns tutorial step presentation, UI masking, world guidance beams, and post-tutorial prompts
- `QuestChainUIController` owns the HUD quest-chain widget and reward-claim rendering
- `FeedbackTopbarController` owns the Roblox in-experience feedback topbar button next to inventory
- `OfflineIncomeUIController` owns `GUI.Frames.Offline` status rendering and claim actions
- `RebirthScript.client.lua` owns rebirth frame rendering and requests

Shared modules:
- `MultiplierUtils` is the canonical rebirth multiplier formatter/source
- `IncomeCalculationUtils` is the canonical live/offline income formula source used by server and HUD
- `FriendBoostConfiguration` and `OfflineIncomeConfiguration` hold tunable reward rules
- `FrameManager` is the canonical blocking-frame open/close coordinator and now also provides an immediate close-all path for forced UI cleanup flows

Networking:
- `ReplicatedStorage.Events` is used for global fire-and-forget UI notifications and analytics intents
- `ReplicatedStorage.Remotes.*` is used for namespaced request/response gameplay flows such as daily rewards, playtime rewards, helper remotes, promo codes, and offline income
