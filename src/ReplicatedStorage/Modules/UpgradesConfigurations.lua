--!strict
-- LOCATION: ReplicatedStorage/Modules/UpgradesConfigurations

local UpgradesConfigurations = {}

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
		Amount = 1,
		DisplayName = "+1 Carry Slot",
		BaseCost = 50000,
		PriceMultiplier = 2.5,
		RobuxProductId = 3555197134,
		ImageId = "rbxassetid://84954813371600"
	},
	{
		Id = "Speed1",
		StatId = "BonusSpeed",
		Amount = 1,
		DisplayName = "+1 Walk Speed",
		BaseCost = 500,
		PriceMultiplier = 1.5,
		RobuxProductId = 3555197217,
		ImageId = "rbxassetid://92215347682288"
	}
}

return UpgradesConfigurations
