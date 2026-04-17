# Controllers

Controller: BombCameraController

Location:
- `src/StarterPlayer/StarterPlayerScripts/BombCameraController.client.lua`

Responsibility:
- Drive the temporary bomb cinematic camera and guarantee an immediate camera reset when the Roblox escape menu opens after FTUE completion

Features:
- Captures/restores camera baseline and applies the bomb follow + blast FOV sequence
- Cancels active camera tweens and forces default FOV recovery on `GuiService.MenuOpened`
- Ignores `GuiService.MenuOpened` while `OnboardingStep` is still below `TutorialConfiguration.FinalStep`

Controller: HUDController

Location:
- `src/StarterPlayer/StarterPlayerScripts/HUDController.client.lua`

Responsibility:
- Render HUD money, offline-per-hour, invite prompt, and boost multipliers

Features:
- Binds `HUD.Boosts.Friends.Value` to `FriendBoostMultiplier`
- Binds `HUD.Boosts.Rebirth.Value` to rebirth multiplier formatting
- Formats the live money balance with a leading `$`
- Keeps invite prompt on the existing HUD button

Controller: CandyEventController

Location:
- `src/StarterPlayer/StarterPlayerScripts/CandyEventController.client.lua`

Responsibility:
- Render the hourly candy-event countdown on `Workspace.TimerWorkspace.SurfaceGui.TitleLabel` and announce the active event start

Features:
- Pulls the initial event state from `ReplicatedStorage.Remotes.CandyEvent.GetState`
- Recomputes the countdown locally from server time while `StateUpdated` pushes authoritative schedule changes
- Shows `CANDY EVENT STARTED!` and `COLLECT CANDIES IN THE MINE` notifications when the event switches from inactive to active
- Adds `START EVENT` and `END EVENT` buttons onto `Workspace.TimerWorkspace.SurfaceGui` for users who already have access to the existing `ManualTestController` actions

Controller: CandySpinController

Location:
- `src/StarterPlayer/StarterPlayerScripts/CandySpinController.client.lua`

Responsibility:
- Drive the separate `GUI.Frames.CandyWheel` UI, open it only from `Workspace.CandyWheel`, and animate the 6-slot candy wheel

Features:
- Opens and closes `CandyWheel` from world bounds instead of a HUD button
- Renders reward slots from `CandyEventConfiguration` and keeps the main button text synced with `CandyCount` and `CandyPaidSpinCount`
- Prompts `CandySpinsX3` / `CandySpinsX9` purchases and uses `ReplicatedStorage.Remotes.CandyEvent.Spin` for server-authoritative results

Controller: HUDModeController

Location:
- `src/StarterPlayer/StarterPlayerScripts/HUDModeController.client.lua`

Responsibility:
- Switch the shared HUD between mine-zone and base-zone button sets

Features:
- Shows mine-only HUD elements such as progress/back/auto-bomb while hiding base-only icons
- Re-syncs HUD mode on zone transitions and when tutorial completion removes the FTUE mask

Controller: UIInitializer

Location:
- `src/StarterPlayer/StarterPlayerScripts/UIInitializer.client.lua`

Responsibility:
- Initialize shared frame open/close wiring, HUD buttons, and touch-triggered world parts for UI entry points

Features:
- Connects tagged world parts such as `UpgradePart`, `ShopPart`, and `RobuxShop` to their corresponding frames through `FrameManager`
- Keeps own-base `BaseNumber`/distance validation for `UpgradePart` while allowing shared `RobuxShop` triggers to open `Shop` without base ownership gating

Controller: ShopController

Location:
- `src/StarterGui/GUI/Frames/Shop/ShopConrtoller.client.lua`

Responsibility:
- Drive the main shop frame, resolve live product pricing, and keep runtime button text aligned with the visible Studio UI hierarchy

Features:
- Formats cash values with a leading `$`
- Normalizes Robux price presentation onto the shared Robux icon glyph, including runtime buttons whose visible text lives in nested `TextLabel` descendants

Controller: MiningController

Location:
- `src/StarterPlayer/StarterPlayerScripts/MiningController.client.lua`

Responsibility:
- Handle local mining feedback, bomb hit application against client ore proxies, and the touch-only mobile bomb button

Features:
- Shows a mobile mine-zone bomb button only on touch devices and hides it while blocking frames are open
- Swaps separate ready/cooldown mobile bomb icons and keeps the icon art at `0.5` transparency in both states

Controller: OnboardingController

Location:
- `src/StarterPlayer/StarterPlayerScripts/OnboardingController.client.lua`

Responsibility:
- Drive tutorial/post-tutorial guidance, mask non-essential UI during FTUE, and restore runtime HUD state safely afterwards

Features:
- Applies per-step UI presentation rules from `TutorialConfiguration`
- Points players to world targets with beams/highlights and opens guided upgrade flows
- Keeps the step `4` back-button pointer while also aiming a world beam at the player's base after the first brainrot pickup
- Uses prebuilt `TutorialCursor` descendants inside the active target button or proxy, toggles them visible only for the active FTUE step, and restores their original hidden state afterwards
- Resets tutorial completion state by closing all non-notification frames and forcing the camera back to the default FOV on the final tutorial step
- Invalidates cached masking only when top-level HUD/frame children change during tutorial so dynamic UI still restores correctly without mask spam inside animated frames
- Re-applies FTUE masking when guided targets arrive late so money HUD, purchase buttons, and the base-upgrade surface button do not remain hidden after step transitions

Controller: ExitRewardPromptController

Location:
- `src/StarterPlayer/StarterPlayerScripts/ExitRewardPromptController.client.lua`

Responsibility:
- Intercept Roblox menu exits to surface the playtime reward prompt when it is relevant outside the tutorial

Features:
- Defers the exit-reward prompt until `PlaytimeRewards.GetStatus` confirms there is still progress or a claimable reward
- Ignores `GuiService.MenuOpened` and `GuiService.MenuClosed` while `OnboardingStep` is still below `TutorialConfiguration.FinalStep`

Controller: QuestChainUIController

Location:
- `src/StarterPlayer/StarterPlayerScripts/QuestChainUIController.client.lua`

Responsibility:
- Render the `ChainQuests` HUD widget, keep quest text/reward rows in sync with server state, and claim completed rewards

Features:
- Fetches initial quest state from `ReplicatedStorage.Remotes.QuestChain`
- Re-renders quest rows defensively after tutorial completion so masked UI state does not leave quest text hidden
- Resolves `ClaimFrame.Collect.Coin.RewardAmount` from `QuestChainConfiguration`, renders it as `+amount`, and looks up the runtime claim descendants defensively so Studio quest templates still update
- Preserves compatibility with legacy `Quests` frame naming by normalizing the runtime widget to `ChainQuests`

Controller: FeedbackTopbarController

Location:
- `src/StarterPlayer/StarterPlayerScripts/FeedbackTopbarController.client.lua`

Responsibility:
- Own the optional TopbarPlus feedback button integration and keep it disabled when the live build should not show the feedback entry

Features:
- Reuses the same `TopbarPlus` package already used by Satchel inventory
- Exits early behind a local feature flag so the feedback button stays hidden without removing the integration code
- Calls `SocialService:PromptFeedbackSubmissionAsync()`
- Shows a client notification instead of failing silently in Studio

Controller: OfflineIncomeUIController

Location:
- `src/StarterPlayer/StarterPlayerScripts/OfflineIncomeUIController.client.lua`

Responsibility:
- Render `GUI.Frames.Offline`, keep it modal while reward is pending, and dispatch x1 / x5 / `Play15` actions

Features:
- Uses `ReplicatedStorage.Remotes.OfflineIncome`
- Resolves UI paths defensively because the frame currently exists in runtime Studio UI, not in the Rojo snapshot

Controller: PlaytimeRewardUIController

Location:
- `src/StarterPlayer/StarterPlayerScripts/PlaytimeRewardUIController.client.lua`

Responsibility:
- Render the `PlaytimeRewards` frame, keep reward cards visible even before the first server sync, and claim timed rewards safely

Features:
- Uses `ReplicatedStorage.Modules.PlaytimeRewardConfiguration` as the canonical reward-card source instead of depending on the first status payload
- Wraps `GetStatus` / `ClaimReward` remote calls in defensive retries and refreshes status again whenever the frame opens
- Resolves reward-card descendants defensively and falls back to a local layout/canvas sync when the runtime `Template` hierarchy is incomplete or mismatched
- Preserves reward availability when server-side reward grant fails by waiting for the authoritative status update instead of mutating the local card list

Controller: JoinLikeStandController

Location:
- `src/StarterPlayer/StarterPlayerScripts/JoinLikeStandController.client.lua`

Responsibility:
- Manage the own-plot join/claim stand, keep its world UI visible, and route proximity interactions through the group reward flow

Features:
- Keeps `InfoUnit`-style stand GUIs enabled when the stand is visible even if the Studio template carried them with `Enabled = false`
- Attempts the server reward claim before prompting Roblox group join so already-joined players do not get stuck on the join prompt path
- Re-attempts the reward claim immediately after a successful join prompt instead of requiring a second interaction

Controller: LimitedTimeOfferController

Location:
- `src/StarterPlayer/StarterPlayerScripts/LimitedTimeOfferController.client.lua`

Responsibility:
- Auto-open and maintain the limited-time offer frame while syncing the countdown, purchase availability, and Robux price

Features:
- Resolves the gamepass price asynchronously and keeps the separate price label visible
- Leaves the main buy button text blank so the button shows only the Robux price treatment
- Suppresses the offer during tutorial and closes it when the timed offer expires or is purchased

Controller: RebirthScript

Location:
- `src/StarterPlayer/StarterPlayerScripts/RebirthScript.client.lua`

Responsibility:
- Render rebirth requirements/rewards and request rebirth actions from the server
