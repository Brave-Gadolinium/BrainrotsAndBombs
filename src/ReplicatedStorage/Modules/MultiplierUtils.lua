--!strict
-- LOCATION: ReplicatedStorage/Modules/MultiplierUtils

local MultiplierUtils = {}

function MultiplierUtils.GetRebirthMultiplier(rebirths: number?): number
	local resolvedRebirths = math.max(0, tonumber(rebirths) or 0)
	return 1 + (resolvedRebirths * 0.5)
end

function MultiplierUtils.FormatMultiplier(multiplier: number?): string
	local resolvedMultiplier = math.max(1, tonumber(multiplier) or 1)
	return string.format("x%.1f", resolvedMultiplier)
end

return MultiplierUtils
