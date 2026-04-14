# Changes

- Added online friend income boost calculation with `FriendBoostMultiplier` and `FriendBoostCount`
- Added HUD boost labels for friend and rebirth multipliers
- Reworked offline income from auto-credit into pending claim flow with x1, Robux x5, and `Play15`
- Added `OfflineIncomeX5` product configuration placeholder
- Added a TopbarPlus feedback button that opens Roblox's in-experience feedback prompt
- Adjusted offline income UI button lookup to use `Content.right.Buttons` with legacy fallback
- Prioritized limited-time offer before offline income, hid offline window during `Play15`, and removed the tutorial end delay
- Restored tutorial text and target guidance for non-masked step 5 after returning to base
- Prevented `FrameManagerBlur` from activating on tutorial-forced `Pickaxes` and `Upgrades` frames
- Stopped tutorial step 6 from auto-skipping to 7 before the player reaches the bomb shop
- Reworked tutorial steps 3-8 to require actual pickup, explicit back-button return, cash collection, and shop opening via `ShopPart`
- Restored step 6 completion on reaching `CashGoal` and made the money HUD visible during that step
