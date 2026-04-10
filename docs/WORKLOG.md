# Worklog

## 2026-04-10
- Raised natural `Zone1` brainrot spawn positions higher while keeping the original random spawn pattern.
- Hid lucky block titles in Playtime Rewards without changing other reward UIs.
- Changed bomb card `Level` labels to show only the bomb order number.
- Moved held lucky block visuals a bit farther from the player's hand and raised slot lucky block visuals slightly.
- Fixed bomb hit ragdoll to preserve the neck joint so other players keep knockback/ragdoll effects without dying.
- Restored contextual popup offer cards and moved their definitions into a separate `ContextualOfferConfiguration` module.
- Reworked contextual offers to use the existing HUD popup frame: its `ImageButton` cards now rotate every 30 seconds, play an offer sound, scale in for 10 seconds, then fade out one by one.
- Bound HUD popup offer buttons to the actual in-game names: `HackerLB`, `AutoBomb`, `AutoCollect`, `BrainrotGodLB`, and `CarrySlot`.
- Wired HUD offer button `Cost` labels to live Robux prices and fixed robux upgrade success text so it no longer duplicates values like `+1 +1`.
- Replaced all visible `R$` Robux price prefixes in the project with the `` symbol format.
- Added a shared round-based `Xray` world bonus that can spawn near miners, grants local through-ground brainrot highlights in a configurable radius, and points to the nearest brainrot with the tutorial beam until the round ends.
- Added an auto-opening `LimitedTimeOffer` flow for `Collect All`: the server now stores the player-specific 3-day offer start/end window from the first tracked join, and the existing frame shows a live countdown plus Robux purchase prompt until the gamepass is bought or the timer expires.
- Changed HUD contextual offer rotation so exactly one offer button stays visible at all times, swapping to the next one every 30 seconds without the old appearance sound or hide gap.
- Updated bomb shop buttons so available-but-unowned bombs now show a toxic bright `Buy`, sequence-locked bombs show gray `Locked`, and owned bombs use yellow `Equip` / `Equipped`; shortened bomb stat labels to `Radius`, `KB`, `Depth`, and `CD`.
