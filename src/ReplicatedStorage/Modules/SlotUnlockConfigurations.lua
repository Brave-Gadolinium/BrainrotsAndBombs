--!strict
-- LOCATION: ReplicatedStorage/Modules/SlotUnlockConfigurations

local SlotUnlockConfigurations = {}

SlotUnlockConfigurations.StartSlots = 10
SlotUnlockConfigurations.MaxSlots = 30
SlotUnlockConfigurations.SlotsPerUpgrade = 2

SlotUnlockConfigurations.new_slots = {
	{
		lvl = 1,
		money_req = 0,
		new_slots = 2,
	},
	{
		lvl = 2,
		money_req = 100000,
		new_slots = 2,
	},
	{
		lvl = 3,
		money_req = 500000,
		new_slots = 2,
	},
	{
		lvl = 4,
		money_req = 1000000,
		new_slots = 2,
	},
	{
		lvl = 5,
		money_req = 5000000,
		new_slots = 2,
	},
	{
		lvl = 6,
		money_req = 10000000,
		new_slots = 2,
	},
	{
		lvl = 7,
		money_req = 25000000,
		new_slots = 2,
	},
	{
		lvl = 8,
		money_req = 50000000,
		new_slots = 2,
	},
	{
		lvl = 9,
		money_req = 75000000,
		new_slots = 2,
	},
	{
		lvl = 10,
		money_req = 100000000,
		new_slots = 2,
	},
}

function SlotUnlockConfigurations.GetUpgradeIndex(unlockedSlots: number): number
	return math.floor((unlockedSlots - SlotUnlockConfigurations.StartSlots) / SlotUnlockConfigurations.SlotsPerUpgrade) + 1
end

function SlotUnlockConfigurations.GetUpgradeData(unlockedSlots: number)
	return SlotUnlockConfigurations.new_slots[SlotUnlockConfigurations.GetUpgradeIndex(unlockedSlots)]
end

function SlotUnlockConfigurations.ClampSlots(unlockedSlots: number): number
	return math.clamp(unlockedSlots, SlotUnlockConfigurations.StartSlots, SlotUnlockConfigurations.MaxSlots)
end

return SlotUnlockConfigurations
