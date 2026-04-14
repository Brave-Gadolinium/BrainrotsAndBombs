# Mechanic: Offline Income

Description:
- When a player rejoins, the server converts eligible offline time into a pending reward instead of writing it directly into slot storage

Rules:
- Minimum offline time is 60 seconds
- Maximum counted offline time is 8 hours
- Formula uses item income, mutation, level, rebirth multiplier, and VIP multiplier
- Friend boost does not affect offline income

Claim paths:
- `ClaimButton` grants `x1` of the pending base amount
- `ClaimButtonx2` is the legacy UI instance name for the paid `x5` claim
- `Play15` starts a session-only 15-minute timer and grants `x5` when the timer completes

Failure handling:
- No pending reward means the frame stays closed
- Leaving before `Play15` completes clears only the timer, not the pending reward
- Failed purchase prompt does not clear pending reward
- Successful claim paths clear pending reward and cancel any active `Play15` timer
