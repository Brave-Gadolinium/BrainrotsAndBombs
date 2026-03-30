--!strict
-- LOCATION: ReplicatedStorage/Modules/BombsConfigurations

local BombsConfigurations = {}

export type BombData = {
	DisplayName: string,
	Cooldown: number,
	Damage: number,
	Radius: number,
	Price: number,
	ImageId: string,
	ExplosionRadius: number,
	ExplosionPower: number,
	KnockbackForce: number,
	ExplosionIncome: number,
	ThrowSpeed: number,
	ThrowArc: number
}

BombsConfigurations.Defaults = {
	ThrowSpeed = 72,
	ThrowArc = 18,
	MinBlastRatio = 0.2,
	MaxBlastRatio = 1.25,
	DefaultMaterialResistance = 3,
}

BombsConfigurations.MaterialResistance = {
	[Enum.Material.Grass] = 1,
	[Enum.Material.Ground] = 1,
	[Enum.Material.Mud] = 1,
	[Enum.Material.LeafyGrass] = 1,
	[Enum.Material.Sand] = 2,
	[Enum.Material.Sandstone] = 2,
	[Enum.Material.Neon] = 2,
	[Enum.Material.Slate] = 3,
	[Enum.Material.Rock] = 3,
	[Enum.Material.Basalt] = 4,
	[Enum.Material.Granite] = 4,
	[Enum.Material.CrackedLava] = 5,
}

BombsConfigurations.Bombs = {
	["Bomb 1"] = {
		DisplayName = "Bomb 1",
		Cooldown = 1.25,
		Damage = 2,
		Radius = 4,
		Price = 0,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 4,
		ExplosionPower = 2,
		KnockbackForce = 65,
		ExplosionIncome = 5,
		ThrowSpeed = 68,
		ThrowArc = 17,
	},
	["Bomb 2"] = {
		DisplayName = "Bomb 2",
		Cooldown = 1.1,
		Damage = 3,
		Radius = 5.5,
		Price = 100,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 5.5,
		ExplosionPower = 3,
		KnockbackForce = 80,
		ExplosionIncome = 6,
		ThrowSpeed = 74,
		ThrowArc = 19,
	},
	["Bomb 3"] = {
		DisplayName = "Bomb 3",
		Cooldown = 0.95,
		Damage = 4,
		Radius = 7,
		Price = 5000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 7,
		ExplosionPower = 4,
		KnockbackForce = 95,
		ExplosionIncome = 8,
		ThrowSpeed = 80,
		ThrowArc = 22,
	},
	["Bomb 4"] = {
		DisplayName = "Bomb 4",
		Cooldown = 0.92,
		Damage = 5,
		Radius = 7.5,
		Price = 20000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 7.5,
		ExplosionPower = 4.5,
		KnockbackForce = 100,
		ExplosionIncome = 10,
		ThrowSpeed = 81,
		ThrowArc = 22,
	},
	["Bomb 5"] = {
		DisplayName = "Bomb 5",
		Cooldown = 0.9,
		Damage = 5.5,
		Radius = 8,
		Price = 30000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 8,
		ExplosionPower = 5,
		KnockbackForce = 104,
		ExplosionIncome = 12,
		ThrowSpeed = 82,
		ThrowArc = 22,
	},
	["Bomb 6"] = {
		DisplayName = "Bomb 6",
		Cooldown = 0.88,
		Damage = 6,
		Radius = 8.5,
		Price = 42000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 8.5,
		ExplosionPower = 5.6,
		KnockbackForce = 108,
		ExplosionIncome = 15,
		ThrowSpeed = 84,
		ThrowArc = 23,
	},
	["Bomb 7"] = {
		DisplayName = "Bomb 7",
		Cooldown = 0.86,
		Damage = 6.5,
		Radius = 9,
		Price = 110000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 9,
		ExplosionPower = 6.2,
		KnockbackForce = 112,
		ExplosionIncome = 20,
		ThrowSpeed = 85,
		ThrowArc = 23,
	},
	["Bomb 8"] = {
		DisplayName = "Bomb 8",
		Cooldown = 0.84,
		Damage = 7,
		Radius = 9.5,
		Price = 250000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 9.5,
		ExplosionPower = 6.8,
		KnockbackForce = 116,
		ExplosionIncome = 25,
		ThrowSpeed = 86,
		ThrowArc = 23,
	},
	["Bomb 9"] = {
		DisplayName = "Bomb 9",
		Cooldown = 0.82,
		Damage = 7.5,
		Radius = 10,
		Price = 560000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 10,
		ExplosionPower = 7.5,
		KnockbackForce = 120,
		ExplosionIncome = 30,
		ThrowSpeed = 88,
		ThrowArc = 24,
	},
	["Bomb 10"] = {
		DisplayName = "Bomb 10",
		Cooldown = 0.8,
		Damage = 8,
		Radius = 10.5,
		Price = 1500000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 10.5,
		ExplosionPower = 8.2,
		KnockbackForce = 124,
		ExplosionIncome = 40,
		ThrowSpeed = 89,
		ThrowArc = 24,
	},
	["Bomb 11"] = {
		DisplayName = "Bomb 11",
		Cooldown = 0.78,
		Damage = 8.5,
		Radius = 11,
		Price = 3300000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 11,
		ExplosionPower = 9,
		KnockbackForce = 128,
		ExplosionIncome = 50,
		ThrowSpeed = 90,
		ThrowArc = 24,
	},
	["Bomb 12"] = {
		DisplayName = "Bomb 12",
		Cooldown = 0.76,
		Damage = 9,
		Radius = 11.5,
		Price = 7300000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 11.5,
		ExplosionPower = 9.8,
		KnockbackForce = 132,
		ExplosionIncome = 60,
		ThrowSpeed = 91,
		ThrowArc = 25,
	},
	["Bomb 13"] = {
		DisplayName = "Bomb 13",
		Cooldown = 0.74,
		Damage = 9.5,
		Radius = 12,
		Price = 19000000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 12,
		ExplosionPower = 10.6,
		KnockbackForce = 136,
		ExplosionIncome = 75,
		ThrowSpeed = 92,
		ThrowArc = 25,
	},
	["Bomb 14"] = {
		DisplayName = "Bomb 14",
		Cooldown = 0.72,
		Damage = 10,
		Radius = 12.5,
		Price = 42000000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 12.5,
		ExplosionPower = 11.5,
		KnockbackForce = 140,
		ExplosionIncome = 90,
		ThrowSpeed = 93,
		ThrowArc = 25,
	},
	["Bomb 15"] = {
		DisplayName = "Bomb 15",
		Cooldown = 0.7,
		Damage = 10.5,
		Radius = 13,
		Price = 94000000,
		ImageId = "rbxassetid://127431622312206",
		ExplosionRadius = 13,
		ExplosionPower = 12.4,
		KnockbackForce = 145,
		ExplosionIncome = 100,
		ThrowSpeed = 94,
		ThrowArc = 26,
	},
} :: { [string]: BombData }

function BombsConfigurations.GetBombData(bombName: string?): BombData?
	if not bombName then
		return nil
	end

	return BombsConfigurations.Bombs[bombName]
end

function BombsConfigurations.GetMaterialResistance(material: Enum.Material): number
	return BombsConfigurations.MaterialResistance[material] or BombsConfigurations.Defaults.DefaultMaterialResistance
end

function BombsConfigurations.GetBlastRadius(bombData: BombData, material: Enum.Material): number
	local resistance = BombsConfigurations.GetMaterialResistance(material)
	local ratio = bombData.ExplosionPower / resistance

	if ratio < BombsConfigurations.Defaults.MinBlastRatio then
		return 0
	end

	ratio = math.clamp(ratio, BombsConfigurations.Defaults.MinBlastRatio, BombsConfigurations.Defaults.MaxBlastRatio)
	return bombData.ExplosionRadius * ratio
end

for _, bombData in pairs(BombsConfigurations.Bombs) do
	bombData.ExplosionRadius *= 2
end

return BombsConfigurations
