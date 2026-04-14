# Controllers

Controller: HUDController

Location:
- `src/StarterPlayer/StarterPlayerScripts/HUDController.client.lua`

Responsibility:
- Render HUD money, offline-per-hour, invite prompt, and boost multipliers

Features:
- Binds `HUD.Boosts.Friends.Value` to `FriendBoostMultiplier`
- Binds `HUD.Boosts.Rebirth.Value` to rebirth multiplier formatting
- Keeps invite prompt on the existing HUD button

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
