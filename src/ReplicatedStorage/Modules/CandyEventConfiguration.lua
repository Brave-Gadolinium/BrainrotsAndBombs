--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local UpgradesConfigurations = require(ReplicatedStorage.Modules.UpgradesConfigurations)

local CandyEventConfiguration = {}

export type CandyEventState = {
	isActive: boolean,
	nextStartAt: number,
	endsAt: number?,
	serverNow: number,
}

export type CandyReward = {
	Type: string,
	DisplayName: string,
	DisplayChance: number,
	Weight: number,
	Image: string?,
	ItemName: string?,
	Rarity: string?,
	Amount: number?,
	UpgradeId: string?,
}

local MONEY_IMAGE = "rbxassetid://18209585783"

local function getRepresentativeItemImage(rarity: string): string?
	local itemNames = ItemConfigurations.GetItemsByRarity(rarity)
	table.sort(itemNames)

	local itemName = itemNames[1]
	if not itemName then
		return nil
	end

	local itemData = ItemConfigurations.GetItemData(itemName)
	return itemData and itemData.ImageId or nil
end

local function getUpgradeImage(upgradeId: string): string?
	for _, config in ipairs(UpgradesConfigurations.Upgrades) do
		if config.Id == upgradeId then
			return config.ImageId
		end
	end

	return nil
end

CandyEventConfiguration.ActiveDurationSeconds = 2 * 60
CandyEventConfiguration.SpinCost = 3
CandyEventConfiguration.SpinAnimationSeconds = 6
CandyEventConfiguration.SchedulePeriodSeconds = 10 * 60
CandyEventConfiguration.TemplateSearchNames = {
	"Candy",
	"CandyModel",
	"CandyCollectible",
}

CandyEventConfiguration.TemplateSearchRoots = {
	"ReplicatedStorage",
	"Workspace",
}

CandyEventConfiguration.WorldVisualYawDegrees = 90

CandyEventConfiguration.ZoneCandyCounts = {
	Zone1 = 37,
	Zone2 = 37,
	Zone3 = 37,
	Zone4 = 37,
	Zone5 = 37,
}

CandyEventConfiguration.ProductKeys = {
	SpinsX3 = "CandySpinsX3",
	SpinsX9 = "CandySpinsX9",
}

CandyEventConfiguration.PickupPopUpSoundId = "rbxassetid://136650469995272"

CandyEventConfiguration.Text = {
	CountdownPrefix = "CANDY EVENT IN",
	ActivePrefix = "CANDY EVENT LIVE",
	CountdownSubtext = "HAPPENS EVERY 10 MINUTES",
	EventStarted = "CANDY EVENT STARTED!",
	EventHint = "COLLECT CANDIES IN THE MINE",
	SpinButtonFormat = "SPIN (%d CANDIES)",
	PaidSpinButton = "SPIN",
	SpinInProgress = "SPIN IN PROGRESS",
	NotEnoughCandies = "NOT ENOUGH CANDIES",
	CandyCountPrefix = "CANDIES: ",
}

CandyEventConfiguration.Rewards = {
	{
		Type = "Item",
		DisplayName = "Brainrot Matteo",
		DisplayChance = 0.5,
		Weight = 5,
		Image = (ItemConfigurations.GetItemData("matteo") :: any).ImageId,
		ItemName = "matteo",
	},
	{
		Type = "RandomItemByRarity",
		DisplayName = "Random Mythic Brainrot",
		DisplayChance = 3,
		Weight = 30,
		Image = getRepresentativeItemImage("Mythic"),
		Rarity = "Mythic",
	},
	{
		Type = "RandomItemByRarity",
		DisplayName = "Random Legendary Brainrot",
		DisplayChance = 9.5,
		Weight = 95,
		Image = getRepresentativeItemImage("Legendary"),
		Rarity = "Legendary",
	},
	{
		Type = "UpgradeStat",
		DisplayName = "+1 Player Speed",
		DisplayChance = 17,
		Weight = 170,
		Image = getUpgradeImage("Speed1"),
		UpgradeId = "Speed1",
		Amount = 1,
	},
	{
		Type = "Money",
		DisplayName = "50,000 Money",
		DisplayChance = 30,
		Weight = 300,
		Image = MONEY_IMAGE,
		Amount = 50000,
	},
	{
		Type = "Money",
		DisplayName = "100,000 Money",
		DisplayChance = 40,
		Weight = 400,
		Image = MONEY_IMAGE,
		Amount = 100000,
	},
} :: {CandyReward}

function CandyEventConfiguration.GetTotalWeight(): number
	local totalWeight = 0
	for _, reward in ipairs(CandyEventConfiguration.Rewards) do
		totalWeight += math.max(0, tonumber(reward.Weight) or 0)
	end
	return totalWeight
end

function CandyEventConfiguration.GetRewardByIndex(index: number): CandyReward?
	return CandyEventConfiguration.Rewards[index]
end

function CandyEventConfiguration.GetSpinButtonText(): string
	return string.format(CandyEventConfiguration.Text.SpinButtonFormat, CandyEventConfiguration.SpinCost)
end

function CandyEventConfiguration.GetCurrentState(serverNow: number, scheduleStartedAt: number?): CandyEventState
	local now = math.max(0, tonumber(serverNow) or 0)
	local schedulePeriod = CandyEventConfiguration.SchedulePeriodSeconds
	local activeDuration = CandyEventConfiguration.ActiveDurationSeconds
	local startedAt = math.max(0, tonumber(scheduleStartedAt) or 0)
	local elapsed = now - startedAt

	if elapsed < schedulePeriod then
		return {
			isActive = false,
			nextStartAt = startedAt + schedulePeriod,
			endsAt = nil,
			serverNow = now,
		}
	end

	local periodIndex = math.max(1, math.floor(elapsed / schedulePeriod))
	local currentWindowStart = startedAt + (periodIndex * schedulePeriod)
	local currentWindowEnd = currentWindowStart + activeDuration
	local isActive = now >= currentWindowStart and now < currentWindowEnd
	local nextStartAt = if isActive then currentWindowStart + schedulePeriod else currentWindowStart + schedulePeriod
	local endsAt = if isActive then currentWindowEnd else nil

	return {
		isActive = isActive,
		nextStartAt = nextStartAt,
		endsAt = endsAt,
		serverNow = now,
	}
end

return CandyEventConfiguration
