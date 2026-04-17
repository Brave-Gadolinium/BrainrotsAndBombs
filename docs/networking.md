# Networking

Namespace: OfflineIncome

Location:
- `ReplicatedStorage.Remotes.OfflineIncome`

Members:
- `GetStatus` (`RemoteFunction`)
- `Claim` (`RemoteFunction`)
- `StartPlay15` (`RemoteFunction`)
- `StatusUpdated` (`RemoteEvent`)

Purpose:
- Sync pending offline reward state and handle x1 / x5 / `Play15` claims

Notes:
- Client startup requests status with `GetStatus`
- Server pushes changes with `StatusUpdated`
- `Claim` handles the base x1 claim
- developer-product fulfillment is handled in `MonetizationController` via `OfflineIncomeController:HandleRobuxClaim`

Namespace: PlaytimeRewards

Location:
- `ReplicatedStorage.Remotes.PlaytimeRewards`

Members:
- `GetStatus` (`RemoteFunction`)
- `ClaimReward` (`RemoteFunction`)
- `StatusUpdated` (`RemoteEvent`)

Purpose:
- Sync the daily playtime reward board and handle safe reward claims from the timed reward frame

Notes:
- Client startup and frame re-open both request status with `GetStatus`
- Server pushes progress and claim changes with `StatusUpdated`
- `ClaimReward` uses a validate -> grant -> mark-claimed flow so failed reward grants do not silently consume claimable rewards

Namespace: CandyEvent

Location:
- `ReplicatedStorage.Remotes.CandyEvent`

Members:
- `GetState` (`RemoteFunction`)
- `Spin` (`RemoteFunction`)
- `StateUpdated` (`RemoteEvent`)

Purpose:
- Sync the hourly candy-event schedule and handle server-authoritative candy wheel spins

Notes:
- Clients bootstrap countdown state through `GetState` and then keep the countdown local using server time
- `StateUpdated` only pushes `{ isActive, nextStartAt, endsAt, serverNow }`
- `Spin` immediately reserves either `20` candies or one paid candy spin and returns the winning wheel index for the 6-second client animation

Namespace: Events

Location:
- `ReplicatedStorage.Events`

Purpose:
- Shared fire-and-forget events such as `ShowNotification`, `RequestRebirth`, `UpdateRebirthUI`, and analytics/reporting events

Notes:
- `RequestGroupReward` is a `RemoteFunction` in `ReplicatedStorage.Events` used by join/group reward surfaces such as `JoinLikeStand`
- FTUE analytics funnel steps are reported under the `Tutor_17/04` funnel name while player save data keeps the existing `TutorialFTUE` progress key for compatibility
