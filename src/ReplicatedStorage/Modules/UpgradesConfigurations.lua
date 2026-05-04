--!strict
-- LOCATION: ReplicatedStorage/Modules/UpgradesConfigurations
local UpgradesConfigurations = {}
UpgradesConfigurations.MaxCarryUpgrades = 3
UpgradesConfigurations.Upgrades = {
	{
		Id = "Range1",
		StatId = "BonusRange",
		Amount = 1,
		DisplayName = "+1 Pickaxe Range",
		HiddenInUI = true,
		BaseCost = 250,
		PriceMultiplier = 1.5,
		RobuxProductId = 3555196998,
		ImageId = "rbxassetid://87959907477250"
	},
	{
		Id = "Range3",
		StatId = "BonusRange",
		Amount = 3,
		DisplayName = "+3 Pickaxe Range",
		HiddenInUI = true,
		BaseCost = 250,
		PriceMultiplier = 1.5,
		RobuxProductId = 3555197053,
		ImageId = "rbxassetid://87959907477250"
	},
	{
		Id = "Carry1",
		StatId = "CarryCapacity",
		DefaultValue = 1,
		Amount = 1,
		DisplayName = "+1 Carry Slot",
		BaseCost = 50000,
		PriceMultiplier = 2.5,
		RobuxProductId = 3567800676,
		ImageId = "rbxassetid://84954813371600"
	},
	{
		Id = "Speed1",
		StatId = "BonusSpeed",
		Amount = 1,
		DisplayName = "+1 Walk Speed",
		BaseCostTutorial = 0, -- тут надо подключить
		BaseCost = 10000,
		PriceMultiplier = 1.5,
		RobuxProductId = 3567800914,
		ImageId = "rbxassetid://92215347682288"
	}
}

function UpgradesConfigurations.GetMaxCarryCapacity(): number
	for _, config in ipairs(UpgradesConfigurations.Upgrades) do
		if config.StatId == "CarryCapacity" then
			local defaultValue = math.max(0, tonumber(config.DefaultValue) or 0)
			local amount = math.max(1, tonumber(config.Amount) or 1)
			return defaultValue + (UpgradesConfigurations.MaxCarryUpgrades * amount)
		end
	end

	return 4
end

return UpgradesConfigurations
