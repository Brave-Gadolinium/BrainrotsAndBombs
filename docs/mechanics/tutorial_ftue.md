Mechanic: FTUE Tutorial

Description:
- Guided onboarding flow that advances players through mining, carrying a brainrot, placing it on the base, collecting money, and buying the first bomb/character/base upgrades.

Core flow:
- Step `1`: walk into the mining zone.
- Step `2`: throw a bomb.
- Step `3`: pick up a brainrot.
- Step `4`: leave the mine.
- Step `5`: place the brainrot on a free slot.
- After the pickup, step `4` keeps the guided `Back` button and also shows a world beam toward the player's base so the return path stays visible.
- If the player picks up a brainrot before throwing a bomb, FTUE now treats the bomb step as completed; pickups in the mine continue at step `4`, while pickups on the surface skip straight to step `5`.
- Step `6+`: keep the money HUD visible for the rest of the masked tutorial flow.
- Step `8`: retry masking until the bomb purchase button is visible.
- Step `10`: retry masking until the character upgrade button is visible.
- Step `11`: retry masking until the base upgrade surface button is visible.
- Completing the tutorial base upgrade currently advances straight from step `11` to step `13`, so step `12` remains a reserved transitional presentation.
- Step `13`: remove the FTUE mask, close frames, reset FOV, and let zone-driven HUD controllers re-sync.

UI nuances:
- `TutorialConfiguration` owns step presentations and targets.
- `TutorialUiConfiguration` owns FTUE UI-specific exceptions such as persistent money visibility, retry targets for delayed buttons, and restore policies for special controls.
- Guided GUI targets now use prebuilt `TutorialCursor` descendants inside the relevant button/proxy, toggling `Visible` on while the FTUE step is active and restoring the original hidden state afterwards.
- The base upgrade surface button preserves its original outside-tutorial visibility snapshot so finishing the tutorial does not restore it to a hidden state.
- Late-arriving guided targets during FTUE set the mask dirty and trigger another mask apply pass on the next refresh.
- Custom `ESC` menu hooks that reset camera FOV or open the exit-reward prompt stay disabled until step `13`.

Systems involved:
- `TutorialService`
- `OnboardingController`
- `TutorialConfiguration`
- `TutorialUiConfiguration`
- `FrameManager`
- `ClientZoneService`
