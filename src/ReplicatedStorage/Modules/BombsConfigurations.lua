--!strict
-- LOCATION: ReplicatedStorage/Modules/BombsConfigurations

local BombsConfigurations = {}

export type BombData = {
	DisplayName: string,
	Cooldown: number,
	Damage: number,
	Radius: number,
	MaxDepthLevel: number,
	Price: number,
	RobuxProductId: number?,
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
	[Enum.Material.Sand] = 2,
	[Enum.Material.Slate] = 3,
	[Enum.Material.Rock] = 3,
	[Enum.Material.Basalt] = 4,
	[Enum.Material.CrackedLava] = 5,
}

BombsConfigurations.Bombs = {
	["Bomb 1"] = {
		DisplayName = "Classic Bomb",
		Cooldown = 1.25,
		Damage = 1,
		Radius = 4,
		MaxDepthLevel = 1,
		Price = 0,
		ImageId = "rbxassetid://87100761204566",
		ExplosionRadius = 4,
		ExplosionPower = 2,
		KnockbackForce = 2,
		ExplosionIncome = 5,
		ThrowSpeed = 68,
		ThrowArc = 17,
	},
	["Bomb 2"] = {
		DisplayName = "Venom Bomb",
		Cooldown = 1.1,
		Damage = 3,
		Radius = 5.5,
		MaxDepthLevel = 1,
		Price = 50,
		RobuxProductId = 3569056023,
		ImageId = "rbxassetid://132214507200870",
		ExplosionRadius = 5.5,
		ExplosionPower = 3,
		KnockbackForce = 4,
		ExplosionIncome = 6,
		ThrowSpeed = 74,
		ThrowArc = 19,
	},
	["Bomb 3"] = {
		DisplayName = "Fire Bomb",
		Cooldown = 0.95,
		Damage = 4,
		Radius = 7,
		MaxDepthLevel = 1,
		Price = 5000,
		RobuxProductId = 3569247187,
		ImageId = "rbxassetid://126369340128052",
		ExplosionRadius = 7,
		ExplosionPower = 4,
		KnockbackForce = 6,
		ExplosionIncome = 8,
		ThrowSpeed = 80,
		ThrowArc = 22,
	},
	["Bomb 4"] = {
		DisplayName = "Dynamite",
		Cooldown = 0.92,
		Damage = 5,
		Radius = 7.5,
		MaxDepthLevel = 2,
		Price = 10000, -- было 20000
		RobuxProductId = 3569247253,
		ImageId = "rbxassetid://124545742137462",
		ExplosionRadius = 7.5,
		ExplosionPower = 4.5,
		KnockbackForce = 8,
		ExplosionIncome = 10,
		ThrowSpeed = 81,
		ThrowArc = 22,
	},
	["Bomb 5"] = {
		DisplayName = "Firework Dynamite",
		Cooldown = 0.9,
		Damage = 5.5,
		Radius = 8,
		MaxDepthLevel = 2,
		Price = 50000,-- было 30000
		RobuxProductId = 3569247314,
		ImageId = "rbxassetid://123962734279128",
		ExplosionRadius = 8,
		ExplosionPower = 5,
		KnockbackForce = 10,
		ExplosionIncome = 12,
		ThrowSpeed = 82,
		ThrowArc = 22,
	},
	["Bomb 6"] = {
		DisplayName = "Mega Dynamite",
		Cooldown = 0.88,
		Damage = 6,
		Radius = 8.5,
		MaxDepthLevel = 2,
		Price = 100000, -- было 42000
		RobuxProductId = 3569247388,
		ImageId = "rbxassetid://137998021450236",
		ExplosionRadius = 8.5,
		ExplosionPower = 5.6,
		KnockbackForce = 12,
		ExplosionIncome = 15,
		ThrowSpeed = 84,
		ThrowArc = 23,
	},
	["Bomb 7"] = {
		DisplayName = "Spike Bomb",
		Cooldown = 0.86,
		Damage = 6.5,
		Radius = 9,
		MaxDepthLevel = 3,
		Price = 250000, -- было 110000
		RobuxProductId = 3569247435,
		ImageId = "rbxassetid://75374064401487",
		ExplosionRadius = 9,
		ExplosionPower = 6.2,
		KnockbackForce = 14,
		ExplosionIncome = 20,
		ThrowSpeed = 85,
		ThrowArc = 23,
	},
	["Bomb 8"] = {
		DisplayName = "Slime Bomb",
		Cooldown = 0.84,
		Damage = 7,
		Radius = 9.5,
		MaxDepthLevel = 3,
		Price = 500000, -- было 250000
		RobuxProductId = 3569247515,
		ImageId = "rbxassetid://105675260030246",
		ExplosionRadius = 9.5,
		ExplosionPower = 6.8,
		KnockbackForce = 16,
		ExplosionIncome = 25,
		ThrowSpeed = 86,
		ThrowArc = 23,
	},
	["Bomb 9"] = {
		DisplayName = "Boom Bomb",
		Cooldown = 0.82,
		Damage = 7.5,
		Radius = 10,
		MaxDepthLevel = 3,
		Price = 1000000, -- было 560000
		RobuxProductId = 3569247575,
		ImageId = "rbxassetid://74375365533894",
		ExplosionRadius = 10,
		ExplosionPower = 7.5,
		KnockbackForce = 18,
		ExplosionIncome = 30,
		ThrowSpeed = 88,
		ThrowArc = 24,
	},
	["Bomb 10"] = {
		DisplayName = "Blast Rocket",
		Cooldown = 0.8,
		Damage = 8,
		Radius = 10.5,
		MaxDepthLevel = 4,
		Price = 2500000, -- было 1500000
		RobuxProductId = 3569247649,
		ImageId = "rbxassetid://91713670957168",
		ExplosionRadius = 10.5,
		ExplosionPower = 8.2,
		KnockbackForce = 20,
		ExplosionIncome = 40,
		ThrowSpeed = 89,
		ThrowArc = 24,
	},
	["Bomb 11"] = {
		DisplayName = "Glitch Rocket",
		Cooldown = 0.78,
		Damage = 8.5,
		Radius = 11,
		MaxDepthLevel = 4,
		Price = 5000000, -- было 3300000
		RobuxProductId = 3569247733,
		ImageId = "rbxassetid://125192967668626",
		ExplosionRadius = 11,
		ExplosionPower = 9,
		KnockbackForce = 25,
		ExplosionIncome = 50,
		ThrowSpeed = 90,
		ThrowArc = 24,
	},
	["Bomb 12"] = {
		DisplayName = "Golden Rocket",
		Cooldown = 0.76,
		Damage = 9,
		Radius = 11.5,
		MaxDepthLevel = 4,
		Price = 10000000, --было 7300000
		RobuxProductId = 3569247836,
		ImageId = "rbxassetid://140242185992764",
		ExplosionRadius = 11.5,
		ExplosionPower = 9.8,
		KnockbackForce = 30,
		ExplosionIncome = 60,
		ThrowSpeed = 91,
		ThrowArc = 25,
	},
	["Bomb 13"] = {
		DisplayName = "TNT Block",
		Cooldown = 0.74,
		Damage = 9.5,
		Radius = 12,
		MaxDepthLevel = 5,
		Price = 25000000, -- было 19000000
		RobuxProductId = 3569247967,
		ImageId = "rbxassetid://70483299252689",
		ExplosionRadius = 12,
		ExplosionPower = 10.6,
		KnockbackForce = 35,
		ExplosionIncome = 75,
		ThrowSpeed = 92,
		ThrowArc = 25,
	},
	["Bomb 14"] = {
		DisplayName = "Space TNT",
		Cooldown = 0.72,
		Damage = 10,
		Radius = 12.5,
		MaxDepthLevel = 5,
		Price = 50000000, -- было 42000000
		RobuxProductId = 3569248032,
		ImageId = "rbxassetid://108607929432134",
		ExplosionRadius = 12.5,
		ExplosionPower = 11.5,
		KnockbackForce = 40,
		ExplosionIncome = 90,
		ThrowSpeed = 93,
		ThrowArc = 25,
	},
	["Bomb 15"] = {
		DisplayName = "Diamond TNT",
		Cooldown = 0.7,
		Damage = 10.5,
		Radius = 13,
		MaxDepthLevel = 5,
		Price = 100000000, -- было 94000000
		RobuxProductId = 3569248114,
		ImageId = "rbxassetid://123983988660865",
		ExplosionRadius = 13,
		ExplosionPower = 12.4,
		KnockbackForce = 50,
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
