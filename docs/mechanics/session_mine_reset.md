# Mechanic: Session Mine Reset

Description:
- The mine now bootstraps in staged `Zone1 -> Zone5` slices on server start, becomes playable after `Zone1` terrain plus the first seed brainrot batch are ready, and still restores only dirty terrain chunks when a round ends

Core flow:
- `TerrainGeneratorManager` builds a `64x64x64` stud chunk grid over `Workspace.Mines`, then fills startup slices top-down with `TERRAIN_STARTUP_SLICE_HEIGHT = 24`
- Startup blockers stay above not-yet-ready deeper zones so players cannot fall into ungenerated terrain while the background bootstrap continues
- `ItemManager` seeds each newly ready zone with an upper-band brainrot batch first, then backfills deeper bands and finally reconciles zones to their normal cap after all startup zones are ready
- `Workspace.MineStartupProgress` tracks the loading-screen progress toward the first playable state and `Workspace.MineStartupPlayable` unlocks the first round only after `Zone1` is actually usable
- The manager captures baseline `materials` and `occupancy` from `Workspace.Terrain` chunk snapshots
- `BombManager` marks intersected chunks dirty whenever a blast actually removes terrain with `FillBall(..., Air)`
- `FinishTime` triggers a time-budgeted restore worker that rewrites only dirty chunks back from the baseline snapshot
- If mine parts change, the terrain cache is invalidated and the next reset rebuilds the baseline before restoring chunks

Compatibility:
- `TimerManager` waits only for `MineStartupPlayable` before the first round; later rounds keep the existing fixed flow
- `TerrainResetInProgress` stays true only while the round-end/full-rebuild restore worker is actively rebuilding terrain
- `BombManager`, `CandyEventService`, and `RoundBrainrotEventManager` reject or defer work that targets unready startup zones
- `ItemManager` still delays normal round refills until `TerrainResetInProgress` returns to false

Systems involved:
- `TerrainGeneratorManager`
- `BombManager`
- `TimerManager`
- `ItemManager`
- `CandyEventService`
- `RoundBrainrotEventManager`
