--!strict
-- LOCATION: ReplicatedStorage/Modules/FriendBoostConfiguration

local FriendBoostConfiguration = {}

FriendBoostConfiguration.BaseMultiplier = 1

function FriendBoostConfiguration.GetMultiplierForFriendCount(friendCount: number?): number
	local resolvedFriendCount = math.max(0, math.floor(tonumber(friendCount) or 0))
	return FriendBoostConfiguration.BaseMultiplier + resolvedFriendCount
end

return FriendBoostConfiguration
