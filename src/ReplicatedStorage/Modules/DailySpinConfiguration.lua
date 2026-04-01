--!strict
-- LOCATION: ReplicatedStorage/Modules/DailySpinConfiguration

local DailySpinConfiguration = {}
local BombsConfigurations = require(script.Parent.BombsConfigurations)
local ItemConfigurations = require(script.Parent.ItemConfigurations)

export type RewardData = {
	Type: string,
	Amount: number?,
	Name: string?,
	DisplayName: string?,
	ResolvedDisplayName: string?,
	Rarity: string?,
	PickaxeName: string?,
	Chance: number,
	Image: string?
}

DailySpinConfiguration.FreeSpinCooldownSeconds = 15 * 60

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

local function getBombImage(pickaxeName: string): string?
	local bombData = BombsConfigurations.GetBombData(pickaxeName)
	return bombData and bombData.ImageId or nil
end

-- Define the 6 slots on the wheel
-- Chance is weight-based. Total weight = sum of all chances.
DailySpinConfiguration.Rewards = {
	[1] = {
		Type = "RandomItemByRarity",
		DisplayName = "Brainrot Rare",
		Rarity = "Rare",
		Chance = 38,
		Image = getRepresentativeItemImage("Rare"),
	} :: RewardData,
	[2] = {
		Type = "Cash",
		Amount = 10000,
		DisplayName = "10 000 money",
		Chance = 25,
		Image = "rbxassetid://18209585783",
	} :: RewardData,
	[3] = {
		Type = "RandomItemByRarity",
		DisplayName = "Brainrot Epic",
		Rarity = "Epic",
		Chance = 18,
		Image = getRepresentativeItemImage("Epic"),
	} :: RewardData,
	[4] = {
		Type = "Cash",
		Amount = 75000,
		DisplayName = "75 000 money",
		Chance = 10,
		Image = "rbxassetid://18209585783",
	} :: RewardData,
	[5] = {
		Type = "RandomItemByRarity",
		DisplayName = "Brainrot Legendary",
		Rarity = "Legendary",
		Chance = 6,
		Image = getRepresentativeItemImage("Legendary"),
	} :: RewardData,
	[6] = {
		Type = "Pickaxe",
		DisplayName = "Bomb 15 Lvl",
		PickaxeName = "Bomb 15",
		Chance = 3,
		Image = getBombImage("Bomb 15"),
	} :: RewardData,
}

function DailySpinConfiguration.GetTotalWeight(): number
	local weight = 0
	for _, reward in pairs(DailySpinConfiguration.Rewards) do
		weight += reward.Chance
	end
	return weight
end

return DailySpinConfiguration
