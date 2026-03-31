local TerrainGeneratorManager = {}

local MaterialService = game:GetService("MaterialService")

local Terrain = workspace.Terrain
local groundParts = workspace:WaitForChild("Mines")
local FinishTime = game.ReplicatedStorage.Remotes.Timer.FinishTime

local VOXEL_RESOLUTION = 4

local ZoneMaterialConfigs = {
	Zone1 = {
		Material = Enum.Material.Sand,
		MaterialVariant = "SandTerrain",
	},
	Zone2 = {
		Material = Enum.Material.Slate,
		MaterialVariant = "StoneTerrain3",
	},
	Zone3 = {
		Material = Enum.Material.Rock,
		MaterialVariant = "StoneTerrain",
	},
	Zone4 = {
		Material = Enum.Material.Basalt,
		MaterialVariant = "LavaTerrain",
	},
	Zone5 = {
		Material = Enum.Material.CrackedLava,
		MaterialVariant = "GlitchTerrain",
	},
}

local DEFAULT_ZONE_CONFIG = ZoneMaterialConfigs.Zone1

local function configureMaterialOverrides()
	for zoneName, config in pairs(ZoneMaterialConfigs) do
		local variant = MaterialService:GetMaterialVariant(config.Material, config.MaterialVariant)
		if variant then
			MaterialService:SetBaseMaterialOverride(config.Material, config.MaterialVariant)
			continue
		end

		local variantByName = MaterialService:FindFirstChild(config.MaterialVariant, true)
		if variantByName and variantByName:IsA("MaterialVariant") then
			warn(string.format(
				"[TerrainGeneratorManager] %s uses MaterialVariant %q, but its BaseMaterial must match %s in MaterialService.",
				zoneName,
				config.MaterialVariant,
				tostring(config.Material)
			))
		else
			warn(string.format(
				"[TerrainGeneratorManager] MaterialVariant %q for %s was not found in MaterialService.",
				config.MaterialVariant,
				zoneName
			))
		end
	end
end

local function fillZones()
	for _, groundPart in ipairs(groundParts:GetChildren()) do
		if not groundPart:IsA("BasePart") then
			continue
		end

		local config = ZoneMaterialConfigs[groundPart.Name] or DEFAULT_ZONE_CONFIG
		local size = groundPart.Size
		local cframe = groundPart.CFrame

		local min = cframe.Position - size / 2
		local max = cframe.Position + size / 2

		local region = Region3.new(min, max):ExpandToGrid(VOXEL_RESOLUTION)
		Terrain:FillRegion(region, VOXEL_RESOLUTION, config.Material)
	end
end

local function regenerateTerrain()
	Terrain:Clear()
	fillZones()
end

configureMaterialOverrides()
regenerateTerrain()

FinishTime.Event:Connect(regenerateTerrain)

return TerrainGeneratorManager
