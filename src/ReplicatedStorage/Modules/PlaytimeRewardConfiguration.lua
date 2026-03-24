--!strict
-- LOCATION: ReplicatedStorage/Modules/PlaytimeRewardConfiguration

local PlaytimeRewardConfiguration = {}

export type RewardEntry = {
	Id: number,
	RequiredSeconds: number,
	Type: string,
	Amount: number?,
	Image: string,
	LuckyBlockId: string?,
	DisplayName: string?,
}

local MONEY_IMAGE = "rbxassetid://18209585783"

PlaytimeRewardConfiguration.Rewards = {
	[1] = { Id = 1, RequiredSeconds = 0, Type = "LuckyBlock", LuckyBlockId = "luckyblock_common", DisplayName = "Common Lucky Block", Image = "rbxassetid://91834580706569" } :: RewardEntry,
	[2] = { Id = 2, RequiredSeconds = 2 * 60, Type = "Money", Amount = 999, Image = MONEY_IMAGE } :: RewardEntry,
	[3] = { Id = 3, RequiredSeconds = 4 * 60, Type = "Money", Amount = 1499, Image = MONEY_IMAGE } :: RewardEntry,
	[4] = { Id = 4, RequiredSeconds = 6 * 60, Type = "Money", Amount = 2499, Image = MONEY_IMAGE } :: RewardEntry,
	[5] = { Id = 5, RequiredSeconds = 8 * 60, Type = "LuckyBlock", LuckyBlockId = "luckyblock_rare", DisplayName = "Rare Lucky Block", Image = "rbxassetid://78540026394217" } :: RewardEntry,
	[6] = { Id = 6, RequiredSeconds = 11 * 60, Type = "Money", Amount = 3499, Image = MONEY_IMAGE } :: RewardEntry,
	[7] = { Id = 7, RequiredSeconds = 14 * 60, Type = "Money", Amount = 4999, Image = MONEY_IMAGE } :: RewardEntry,
	[8] = { Id = 8, RequiredSeconds = 17 * 60, Type = "Money", Amount = 6999, Image = MONEY_IMAGE } :: RewardEntry,
	[9] = { Id = 9, RequiredSeconds = 20 * 60, Type = "LuckyBlock", LuckyBlockId = "luckyblock_epic", DisplayName = "Epic Lucky Block", Image = "rbxassetid://119662372487092" } :: RewardEntry,
	[10] = { Id = 10, RequiredSeconds = 23 * 60, Type = "Money", Amount = 8999, Image = MONEY_IMAGE } :: RewardEntry,
	[11] = { Id = 11, RequiredSeconds = 26 * 60, Type = "Money", Amount = 11999, Image = MONEY_IMAGE } :: RewardEntry,
	[12] = { Id = 12, RequiredSeconds = 30 * 60, Type = "LuckyBlock", LuckyBlockId = "luckyblock_legendary", DisplayName = "Legendary Lucky Block", Image = "rbxassetid://111304202358633" } :: RewardEntry,
} :: { [number]: RewardEntry }

function PlaytimeRewardConfiguration.GetRewardById(rewardId: number): RewardEntry?
	return PlaytimeRewardConfiguration.Rewards[rewardId]
end

function PlaytimeRewardConfiguration.GetMaxRewardId(): number
	return #PlaytimeRewardConfiguration.Rewards
end

return PlaytimeRewardConfiguration