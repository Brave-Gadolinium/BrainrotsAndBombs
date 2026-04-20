Mechanic: FTUE Tutorial

Description:
- Guided onboarding flow that advances players through mining, carrying a brainrot, placing it on the base, collecting money, and buying the first bomb/character/base upgrades.

Core flow:
- Step `1`: walk into the mining zone.
- Step `2`: throw a bomb.
- Step `3`: pick up a brainrot.
- Step `4`: leave the mine.
- Step `5`: place the brainrot on a free slot.
- If the player reaches step `5` from a surface pickup, the FTUE mask temporarily re-enables Satchel/backpack until that backpack brainrot is equipped or placed.
- While `OnboardingStep` is still below `5`, character spawn uses `Workspace.Zones.NewPlayerPart` (with `NewPlayerPart` tag fallback) instead of the plot spawn; reaching step `5` restores the normal base spawn.
- After the pickup, step `4` keeps the guided `Back` button and also shows a world beam toward the player's base so the return path stays visible.
- If the player picks up a brainrot before throwing a bomb, FTUE now treats the bomb step as completed; pickups in the mine continue at step `4`, while pickups on the surface skip straight to step `5`.
- If the player rejoins or respawns on step `5` without a placed brainrot and without any carried or backpack brainrot item, the server rewinds FTUE back to step `3`.
- Step `6+`: keep the money HUD visible for the rest of the masked tutorial flow.
- Step `8`: retry masking until the bomb purchase button is visible.
- Step `10`: retry masking until the character upgrade button is visible.
- Step `11`: retry masking until the base upgrade surface button is visible.
- Completing the tutorial base upgrade currently advances straight from step `11` to step `13`, so step `12` remains a reserved transitional presentation.
- Step `13`: remove the FTUE mask, close frames, reset FOV, and let zone-driven HUD controllers re-sync.

UI nuances:
- `TutorialConfiguration` owns step presentations and targets.
- `TutorialUiConfiguration` owns FTUE UI-specific exceptions such as persistent money visibility, retry targets for delayed buttons, and restore policies for special controls.
- FTUE analytics step events are sent to the `Tutor_17/04` funnel while server save data keeps the legacy `TutorialFTUE` progress key so partially completed profiles continue safely.
- Guided GUI targets now use prebuilt `TutorialCursor` descendants inside the relevant button/proxy, toggling `Visible` on while the FTUE step is active and restoring the original hidden state afterwards.
- The base upgrade surface button preserves its original outside-tutorial visibility snapshot so finishing the tutorial does not restore it to a hidden state.
- Step `10` auto-opening of `Upgrades` is now debounced, and shared frame opening uses a cooldown so the tutorial cannot pile up repeated open requests while the UI is still transitioning.
- Late-arriving guided targets during FTUE set the mask dirty and trigger another mask apply pass on the next refresh.
- Custom `ESC` menu hooks that reset camera FOV or open the exit-reward prompt stay disabled until step `13`.

Post-tutorial prompts:
- After FTUE completion, `PostTutorialStage` is derived from live progression instead of being hardcoded.
- Stage `0`: wait until the player reaches `CharacterUpgradeMoneyThreshold` (`10000`).
- Stage `1`: prompt the player to buy `Speed1`.
- Stage `2`: wait until the player reaches `BaseUpgradeMoneyThreshold` (`20000`).
- Stage `3`: prompt the player to buy the first base slot upgrade.
- Stage `4`: post-tutorial flow completed.
- The character/base completion popups fire only from the actual `Speed1` and first base-upgrade purchases.

Systems involved:
- `TutorialService`
- `OnboardingController`
- `TutorialConfiguration`
- `TutorialUiConfiguration`
- `FrameManager`
- `ClientZoneService`
