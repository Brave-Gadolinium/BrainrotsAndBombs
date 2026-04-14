# Controllers

Controller: BombCameraController

Location:
- `src/StarterPlayer/StarterPlayerScripts/BombCameraController.client.lua`

Responsibility:
- Drive the temporary bomb cinematic camera and guarantee an immediate camera reset when the Roblox escape menu opens

Features:
- Captures/restores camera baseline and applies the bomb follow + blast FOV sequence
- Cancels active camera tweens and forces default FOV recovery on `GuiService.MenuOpened`

Controller: HUDController

Location:
- `src/StarterPlayer/StarterPlayerScripts/HUDController.client.lua`

Responsibility:
- Render HUD money, offline-per-hour, invite prompt, and boost multipliers

Features:
- Binds `HUD.Boosts.Friends.Value` to `FriendBoostMultiplier`
- Binds `HUD.Boosts.Rebirth.Value` to rebirth multiplier formatting
- Keeps invite prompt on the existing HUD button

Controller: HUDModeController

Location:
- `src/StarterPlayer/StarterPlayerScripts/HUDModeController.client.lua`

Responsibility:
- Switch the shared HUD between mine-zone and base-zone button sets

Features:
- Shows mine-only HUD elements such as progress/back/auto-bomb while hiding base-only icons
- Re-syncs HUD mode on zone transitions and when tutorial completion removes the FTUE mask

Controller: OnboardingController

Location:
- `src/StarterPlayer/StarterPlayerScripts/OnboardingController.client.lua`

Responsibility:
- Drive tutorial/post-tutorial guidance, mask non-essential UI during FTUE, and restore runtime HUD state safely afterwards

Features:
- Applies per-step UI presentation rules from `TutorialConfiguration`
- Points players to world targets with beams/highlights and opens guided upgrade flows
- Resets tutorial completion state by closing all non-notification frames and forcing the camera back to the default FOV on the final tutorial step
- Invalidates cached masking only when top-level HUD/frame children change during tutorial so dynamic UI still restores correctly without mask spam inside animated frames
- Re-applies FTUE masking when guided targets arrive late so money HUD, purchase buttons, and the base-upgrade surface button do not remain hidden after step transitions

Controller: QuestChainUIController

Location:
- `src/StarterPlayer/StarterPlayerScripts/QuestChainUIController.client.lua`

Responsibility:
- Render the `ChainQuests` HUD widget, keep quest text/reward rows in sync with server state, and claim completed rewards

Features:
- Fetches initial quest state from `ReplicatedStorage.Remotes.QuestChain`
- Re-renders quest rows defensively after tutorial completion so masked UI state does not leave quest text hidden
- Preserves compatibility with legacy `Quests` frame naming by normalizing the runtime widget to `ChainQuests`

Controller: FeedbackTopbarController

Location:
- `src/StarterPlayer/StarterPlayerScripts/FeedbackTopbarController.client.lua`

Responsibility:
- Add a TopbarPlus feedback button next to the Satchel inventory icon and open Roblox's built-in in-experience feedback prompt

Features:
- Reuses the same `TopbarPlus` package already used by Satchel inventory
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

Controller: RebirthScript

Location:
- `src/StarterPlayer/StarterPlayerScripts/RebirthScript.client.lua`

Responsibility:
- Render rebirth requirements/rewards and request rebirth actions from the server
