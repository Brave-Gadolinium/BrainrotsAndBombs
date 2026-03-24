--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)

local RarityManager = {}

function RarityManager.GetRarityInfo(rarityName: string): {any}?
	return RarityConfigurations[rarityName]
end

return RarityManager