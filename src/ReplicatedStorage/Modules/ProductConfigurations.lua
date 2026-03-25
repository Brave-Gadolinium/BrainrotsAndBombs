--!strict
-- LOCATION: ReplicatedStorage/Modules/ProductConfigurations

local ProductConfigurations = {}

ProductConfigurations.Group = {
	Id = 229327648,
	Reward = {
		Name = "Blue",
		Mutation = "Normal",
		Level = 1
	}
}

ProductConfigurations.Products = {
	["SkipRebirth"] = 3535477160,
	["RandomItem"] = 3541134967,
	["PlaytimeRewardsSkipAll"] = 3555241775,
	["DailyRewardsSkipAll"] = 3555241775,
	["DailyRewardsSkip1"] = 3555241775,

	["ItemProduct1"] = 3507422194,
	["ItemProduct2"] = 3507422461,
	["ItemProduct3"] = 3507422665,

	["CashProduct1"] = 3507413234,
	["CashProduct2"] = 3507413478,
	["CashProduct3"] = 3507414088,

	["SpinsX3"] = 3544825393,
	["SpinsX9"] = 3544825505,
}

ProductConfigurations.GamePasses = {
	["VIP"] = 1664438543,
	["StarterPack"] = 1664754284,
	["ProPack"] = 1664576483,
}

ProductConfigurations.PackRewards = {
	["StarterPack"] = {
		Money = 5000,
		Items = {
			{Name = "Blue", Mutation = "Normal", Level = 1},
			{Name = "Green", Mutation = "Normal", Level = 1}
		}
	},
	["ProPack"] = {
		Money = 50000,
		Items = {
			{Name = "Yellow", Mutation = "Normal", Level = 1},
			{Name = "Pink", Mutation = "Normal", Level = 1}
		}
	}
}

ProductConfigurations.ItemProductRewards = {
	["ItemProduct1"] = {Name = "Purple", Mutation = "Normal", Level = 1},
	["ItemProduct2"] = {Name = "Orange", Mutation = "Normal", Level = 1},
	["ItemProduct3"] = {Name = "Brown", Mutation = "Normal", Level = 1},
}

ProductConfigurations.CashProductRewards = {
	["CashProduct1"] = 10000,
	["CashProduct2"] = 100000,
	["CashProduct3"] = 1000000,
}

function ProductConfigurations.GetProductById(id: number)
	for name, productId in pairs(ProductConfigurations.Products) do
		if productId == id then return name end
	end
	return nil
end

function ProductConfigurations.GetGamePassById(id: number)
	for name, passId in pairs(ProductConfigurations.GamePasses) do
		if passId == id then return name end
	end
	return nil
end

return ProductConfigurations