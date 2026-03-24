--!strict
-- LOCATION: ReplicatedStorage/Modules/OreConfigurations

local OreConfigurations = {}

export type OreConfig = {
	[string]: number
}

OreConfigurations.MineSpawns = {
	["1"] = {
		Stone = 100,
	},
	["2"] = {
		Sapphire = 100,
	},
	["3"] = {
		Emerald = 100,
	},
	["4"] = {
		Sunstone = 100,
	},
	["5"] = {
		Rhodonite = 100,
	},
} :: { [string]: OreConfig }

OreConfigurations.OreHealth = {
	Stone = 2,
	Sapphire = 10,
	Emerald = 25,
	Sunstone = 50,
	Rhodonite = 100
} :: { [string]: number }

function OreConfigurations.GetRandomOre(mineTier: string): string
	local chances = OreConfigurations.MineSpawns[mineTier]
	if not chances then return "Stone" end

	local totalWeight = 0
	for _, weight in pairs(chances) do
		totalWeight += weight
	end

	local roll = math.random(1, totalWeight)
	local currentWeight = 0

	for oreName, weight in pairs(chances) do
		currentWeight += weight
		if roll <= currentWeight then
			return oreName
		end
	end

	return "Stone"
end

return OreConfigurations