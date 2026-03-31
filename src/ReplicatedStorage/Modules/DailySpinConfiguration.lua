--!strict
-- LOCATION: ReplicatedStorage/Modules/DailySpinConfiguration

local DailySpinConfiguration = {}

export type RewardData = {
	Type: string,
	Amount: number?,
	Name: string?,
	Chance: number,
	Image: string?
}

DailySpinConfiguration.FreeSpinCooldownSeconds = 15 * 60

-- Define the 6 slots on the wheel
-- Chance is weight-based. Total weight = sum of all chances.
DailySpinConfiguration.Rewards = {
	[1] = {Type = "Cash", Amount = 1000, Chance = 50, Image = "rbxassetid://18209585783"} :: RewardData,
	[2] = {Type = "Spins", Amount = 2, Chance = 20, Image = "rbxassetid://123668998332245"} :: RewardData,
	[3] = {Type = "Cash", Amount = 5000, Chance = 15, Image = "rbxassetid://18209585783"} :: RewardData,
	[4] = {Type = "Cash", Amount = 10000, Chance = 10, Image = "rbxassetid://18209585783"} :: RewardData,
	[5] = {Type = "Item", Name = "espresso_signora", Chance = 6} :: RewardData,
	[6] = {Type = "Item", Name = "esok_sekolah", Chance = 2} :: RewardData,
}

function DailySpinConfiguration.GetTotalWeight(): number
	local weight = 0
	for _, reward in pairs(DailySpinConfiguration.Rewards) do
		weight += reward.Chance
	end
	return weight
end

return DailySpinConfiguration
