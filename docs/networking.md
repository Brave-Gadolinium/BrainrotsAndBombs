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

Namespace: Events

Location:
- `ReplicatedStorage.Events`

Purpose:
- Shared fire-and-forget events such as `ShowNotification`, `RequestRebirth`, `UpdateRebirthUI`, and analytics/reporting events
