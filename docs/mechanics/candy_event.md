# Mechanic: Candy Event

Description:
- The candy event is a separate live-feature layered onto the mine round flow
- It activates globally during the first `10` minutes of every server hour and keeps the candy wheel available at all times

Core flow:
- `CandyEventService` computes the active window from `Workspace:GetServerTimeNow()` as `HH:00:00` to `HH:09:59`
- When the event becomes active, the service pushes `{ isActive, nextStartAt, endsAt, serverNow }` through `ReplicatedStorage.Remotes.CandyEvent.StateUpdated`
- `CandyEventController` writes the countdown text into `Workspace.TimerWorkspace.SurfaceGui.TitleLabel` both before start and during the active window
- The same timer surface can show `START EVENT` and `END EVENT` buttons for testers/admins by reusing existing `ManualTestController` actions instead of a separate debug remote
- If a mine round is currently live and `TerrainResetInProgress` is false, the service spawns candies across `Workspace.Mines` using the same positioning helper as `ItemManager`
- Spawned candy visuals are rotated `90` degrees on `Y` and tagged into the shared `Rotate` client animation flow so they continuously spin and bob up/down
- Candies do not use carry, backpack, or inventory pickup flow; they are collected instantly through server-side `Touched`
- Each collected candy immediately increments `PlayerController` saved `CandyCount`, fires `ReplicatedStorage.Events.ShowCandyPopUp`, shows a `+1` popup with a candy icon, and plays the local pickup sound
- At round end or event end, all live candies are cleared without refill or compensation
- `GUI.Frames.CandyWheel` opens only from the `Workspace.CandyWheel` world entry and spins through `ReplicatedStorage.Remotes.CandyEvent.Spin`
- A spin consumes `20` candies first, otherwise falls back to one `CandyPaidSpinCount` if available
- The server reserves the cost immediately, returns the winning reward index, and grants the reward after the `6` second client wheel animation

Rewards:
- `Brainrot Matteo`
- `Random Mythic Brainrot`
- `Random Legendary Brainrot`
- `+1 Player Speed`
- `$50,000`
- `$100,000`

Persistence:
- `PlayerController` persists `CandyCount` and `CandyPaidSpinCount` in the main player profile
- The same values are mirrored to player attributes for client UI updates

Systems involved:
- `CandyEventService`
- `PlayerController`
- `MonetizationController`
- `ItemManager`
- `MineSpawnUtils`
- `CandyEventConfiguration`
- `CandyEventController`
- `CandySpinController`
