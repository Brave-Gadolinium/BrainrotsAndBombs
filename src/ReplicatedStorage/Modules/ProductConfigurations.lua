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
	["SkipRebirth"] = 3566500447,
	["RandomItem"] = 3566503229,
	["PlaytimeRewardsSkipAll"] = 3566503314,
	-- TODO Добавить актуальные ID продуктов для ускорения получения наград за время игры
	["PlaytimeRewardsSpeedX2"] = 3566508646,
	["PlaytimeRewardsSpeedX5"] = 3566508747,
	-- TODO Добавить актуальные ID продуктов для пропуска наград за время игры
	["DailyRewardsSkipAll"] = 3566509090,
	["DailyRewardsSkip1"] = 3566509199,

	["ItemProduct1"] = 3566509625,
	["ItemProduct2"] = 3566510433,
	["ItemProduct3"] = 3566510878,

	["CashProduct1"] = 3566511291,
	["CashProduct2"] = 3566511557,
	["CashProduct3"] = 3566511657,

	["SpinsX3"] = 3566512371,
	["SpinsX9"] = 3566513791,
}

ProductConfigurations.GamePasses = {
	["VIP"] = 1772898056,
	["StarterPack"] = 1772874155,
	["ProPack"] = 1772382058,
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
