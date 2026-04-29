--!strict
-- LOCATION: ReplicatedStorage/Modules/DailyRewardConfiguration

local DailyRewardConfiguration = {}
local BombsConfigurations = require(script.Parent.BombsConfigurations)

export type RewardEntry = {
	Day: number,
	Type: string,
	Amount: number?,
	Image: string,
	HiddenUntilClaimed: boolean?,
	Rarity: string?,
	PickaxeName: string?,
	CompensationType: string?,
	CompensationAmount: number?,
}

local MONEY_IMAGE = "rbxassetid://18209585783"
local RANDOM_ITEM_IMAGE = "rbxassetid://94902603798927"
local RANDOM_ITEM_IMAGE2 = "rbxassetid://100324087260160"
local RANDOM_ITEM_IMAGE3 = "rbxassetid://118911944523229"
local RANDOM_ITEM_IMAGE4 = "rbxassetid://126299015694808"
local BOMB_IMAGE = ((BombsConfigurations.Bombs :: any)["Bomb 7"] and (BombsConfigurations.Bombs :: any)["Bomb 7"].ImageId) or ""
local BOMB_IMAGE2 = ((BombsConfigurations.Bombs :: any)["Bomb 13"] and (BombsConfigurations.Bombs :: any)["Bomb 13"].ImageId) or ""
local BOMB_IMAGE3 = ((BombsConfigurations.Bombs :: any)["Bomb 15"] and (BombsConfigurations.Bombs :: any)["Bomb 15"].ImageId) or ""

DailyRewardConfiguration.Rewards = {
	[1] = { Day = 1, Type = "RandomItemByRarity", Rarity = "Legendary", Image = RANDOM_ITEM_IMAGE } :: RewardEntry,
	[2] = { Day = 2, Type = "Pickaxe", PickaxeName = "Bomb 7", Image = BOMB_IMAGE, CompensationType = "Money", CompensationAmount = 50000 } :: RewardEntry,
	[3] = { Day = 3, Type = "Money", Amount = 500000, Image = MONEY_IMAGE } :: RewardEntry,
	[4] = { Day = 4, Type = "RandomItemByRarity", Rarity = "Mythic", Image = RANDOM_ITEM_IMAGE2, HiddenUntilClaimed = true } :: RewardEntry,
	[5] = { Day = 5, Type = "Pickaxe", PickaxeName = "Bomb 13", Image = BOMB_IMAGE2, CompensationType = "Money", CompensationAmount = 2500000 } :: RewardEntry,
	[6] = { Day = 6, Type = "Money", Amount = 5000000, Image = MONEY_IMAGE } :: RewardEntry,
	[7] = { Day = 7, Type = "Pickaxe", PickaxeName = "Bomb 15", Image = BOMB_IMAGE3, CompensationType = "Money", CompensationAmount = 10000000 } :: RewardEntry,
}

function DailyRewardConfiguration.GetMaxDay(): number
	return #DailyRewardConfiguration.Rewards
end

function DailyRewardConfiguration.GetRewardForDay(day: number): RewardEntry?
	return DailyRewardConfiguration.Rewards[day]
end

return DailyRewardConfiguration