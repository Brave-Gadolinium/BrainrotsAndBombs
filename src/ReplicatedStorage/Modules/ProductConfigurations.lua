--!strict
-- LOCATION: ReplicatedStorage/Modules/ProductConfigurations

local ProductConfigurations = {}

ProductConfigurations.Group = {
	Id = 222755422,
	Reward = {
		Name = "bombombini_gusini",
		Mutation = "Normal",
		Level = 1
	}
}

ProductConfigurations.Products = {
	["SkipRebirth"] = 3567801357,
	["RandomItem"] = 3567801988,
	["PlaytimeRewardsSkipAll"] = 3567801859,
	["PlaytimeRewardsSpeedX2"] = 3567801697,
	["PlaytimeRewardsSpeedX5"] = 3567801499,
	["DailyRewardsSkipAll"] = 3567802250,
	["DailyRewardsSkip1"] = 3567802115,
	["RewardedSoft100"] = 0,

	["ItemProduct1"] = 3567803285,
	["ItemProduct2"] = 3567803643,
	["ItemProduct3"] = 3567803372,

	["CashProduct1"] = 3567802668,
	["CashProduct2"] = 3567803042,
	["CashProduct3"] = 3567802511,

	["SpinsX3"] = 3567801026,
	["SpinsX9"] = 3567801177,

	["BrainrotGodBallerinoLololo"] = 3569171946,
	["BrainrotGodLuckyBlock"] = 3569174619,
	["BrainrotGodDragonCannelloni"] = 3569172115,
	["BrainrotGodEsokSekolah"] = 3569172309,
	["BrainrotGodEspressoSignora"] = 3569171748,
	["HackerLuckyBlock"] = 3569174411,
	["BrainrotGodMatteo"] = 3569171240,
}

ProductConfigurations.GamePasses = {
	["VIP"] = 1782060480,
	["StarterPack"] = 1781448453,
	["ProPack"] = 1780452467,
	["CollectAll"] = 1783037385,
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
	["BrainrotGodBallerinoLololo"] = {Name = "ballerino_lololo", Mutation = "Normal", Level = 1},
	["BrainrotGodDragonCannelloni"] = {Name = "dragon_cannelloni", Mutation = "Normal", Level = 1},
	["BrainrotGodEsokSekolah"] = {Name = "esok_sekolah", Mutation = "Normal", Level = 1},
	["BrainrotGodEspressoSignora"] = {Name = "espresso_signora", Mutation = "Normal", Level = 1},
	["BrainrotGodMatteo"] = {Name = "matteo", Mutation = "Normal", Level = 1},
}

ProductConfigurations.LimitedItemProducts = {
	["BrainrotGodBallerinoLololo"] = {Total = 100},
	["BrainrotGodDragonCannelloni"] = {Total = 100},
	["BrainrotGodEsokSekolah"] = {Total = 100},
	["BrainrotGodEspressoSignora"] = {Total = 100},
	["BrainrotGodMatteo"] = {Total = 100},
}

ProductConfigurations.CashProductRewards = {
	["CashProduct1"] = 10000,
	["CashProduct2"] = 100000,
	["CashProduct3"] = 1000000,
}

ProductConfigurations.LuckyBlockProductRewards = {
	["BrainrotGodLuckyBlock"] = "luckyblock_brainrotgod",
	["HackerLuckyBlock"] = "luckyblock_hacker",
}

ProductConfigurations.PrimaryRewardedAdKey = "RewardedSoft100"

ProductConfigurations.RewardedAdRewards = {
	["RewardedSoft100"] = {
		CashAmount = 100,
		ButtonTitle = "WATCH AD",
		ButtonSubtitle = "+100 SOFT",
		PlacementId = nil,
	}
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

function ProductConfigurations.GetLimitedItemProductConfig(productName: string)
	return ProductConfigurations.LimitedItemProducts[productName]
end

function ProductConfigurations.GetLimitedItemProductConfigById(id: number)
	local productName = ProductConfigurations.GetProductById(id)
	if not productName then
		return nil, nil
	end

	return ProductConfigurations.GetLimitedItemProductConfig(productName), productName
end

function ProductConfigurations.IsLimitedItemProductId(id: number): boolean
	local limitedConfig = ProductConfigurations.GetLimitedItemProductConfigById(id)
	return limitedConfig ~= nil
end

return ProductConfigurations
