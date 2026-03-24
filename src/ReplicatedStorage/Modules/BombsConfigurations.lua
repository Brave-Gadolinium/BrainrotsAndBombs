--!strict
-- LOCATION: ReplicatedStorage/Modules/BombsConfigurations

local BombsConfigurations = {}

export type BombData = {
	DisplayName: string,
	Cooldown: number,
	Damage: number,
	Radius: number,
	Price: number,
	ImageId: string
}

local BASE_RADIUS = 4

BombsConfigurations.Bombs = {
	["Bomb 1"] = {
		DisplayName = "Bomb 1",
		Cooldown = 1,
		Damage = 1,
		Radius = BASE_RADIUS,
		Price = 0,
		ImageId = "rbxassetid://127431622312206"
	},
	
	["Bomb 2"] = {
		DisplayName = "Bomb 1",
		Cooldown = 1,
		Damage = 1,
		Radius = BASE_RADIUS,
		Price = 0,
		ImageId = "rbxassetid://127431622312206"
	},

	["Bomb 3"] = {
		DisplayName = "Bomb 1",
		Cooldown = 1,
		Damage = 1,
		Radius = BASE_RADIUS,
		Price = 0,
		ImageId = "rbxassetid://127431622312206"
	},

} :: { [string]: BombData }

return BombsConfigurations