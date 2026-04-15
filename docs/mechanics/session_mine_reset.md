# Mechanic: Session Mine Reset

Description:
- The mine terrain is normalized once on server start, captured into voxel chunk snapshots, and only the chunks damaged during the round are restored when the timer ends

Core flow:
- `TerrainGeneratorManager` builds a `64x64x64` stud chunk grid over `Workspace.Mines`
- The manager captures baseline `materials` and `occupancy` from `Workspace.Terrain`
- `BombManager` marks intersected chunks dirty whenever a blast actually removes terrain with `FillBall(..., Air)`
- `FinishTime` triggers a time-budgeted restore worker that rewrites only dirty chunks back from the baseline snapshot
- If mine parts change, the terrain cache is invalidated and the next reset rebuilds the baseline before restoring chunks

Compatibility:
- `TimerManager` keeps the existing fixed round flow and does not wait for terrain reset completion
- `TerrainResetInProgress` stays true only while the restore worker is actively rebuilding terrain
- `ItemManager` still delays mine refills until `TerrainResetInProgress` returns to false

Systems involved:
- `TerrainGeneratorManager`
- `BombManager`
- `TimerManager`
- `ItemManager`
