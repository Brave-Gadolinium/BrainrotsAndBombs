local TerrainGeneratorManager = {}

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Terrain = Workspace.Terrain
local groundParts = Workspace:WaitForChild("Mines")

local function ensureTimerFinishEvent(): BindableEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local timerFolder = remotesFolder:FindFirstChild("Timer")
	if not timerFolder then
		timerFolder = Instance.new("Folder")
		timerFolder.Name = "Timer"
		timerFolder.Parent = remotesFolder
	end

	local finishTime = timerFolder:FindFirstChild("FinishTime")
	if not finishTime then
		finishTime = Instance.new("BindableEvent")
		finishTime.Name = "FinishTime"
		finishTime.Parent = timerFolder
	end

	return finishTime :: BindableEvent
end

local FinishTime = ensureTimerFinishEvent()

local VOXEL_RESOLUTION = 4
local TERRAIN_SLICE_HEIGHT = 48
local TERRAIN_BATCH_SIZE = 4
local TERRAIN_BATCH_YIELD = 0.03

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
local queuedRegeneration = false
local isRegenerating = false

type TerrainSlice = {
	Region: Region3,
	Material: Enum.Material,
}

local cachedSlices: {TerrainSlice} = {}

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

local function buildSlices(): {TerrainSlice}
	local slices: {TerrainSlice} = {}

	for _, groundPart in ipairs(groundParts:GetChildren()) do
		if not groundPart:IsA("BasePart") then
			continue
		end

		local config = ZoneMaterialConfigs[groundPart.Name] or DEFAULT_ZONE_CONFIG
		local size = groundPart.Size
		local cframe = groundPart.CFrame

		local minX = cframe.Position.X - (size.X * 0.5)
		local maxX = cframe.Position.X + (size.X * 0.5)
		local minZ = cframe.Position.Z - (size.Z * 0.5)
		local maxZ = cframe.Position.Z + (size.Z * 0.5)
		local bottomY = cframe.Position.Y - (size.Y * 0.5)
		local topY = cframe.Position.Y + (size.Y * 0.5)
		local currentBottomY = bottomY

		while currentBottomY < topY do
			local currentTopY = math.min(currentBottomY + TERRAIN_SLICE_HEIGHT, topY)
			local region = Region3.new(
				Vector3.new(minX, currentBottomY, minZ),
				Vector3.new(maxX, currentTopY, maxZ)
			):ExpandToGrid(VOXEL_RESOLUTION)

			table.insert(slices, {
				Region = region,
				Material = config.Material,
			})

			currentBottomY = currentTopY
		end
	end

	return slices
end

local function rebuildSliceCache()
	cachedSlices = buildSlices()
end

local function runRegeneration()
	if isRegenerating then
		queuedRegeneration = true
		return
	end

	isRegenerating = true
	Workspace:SetAttribute("TerrainResetInProgress", true)

	task.spawn(function()
		repeat
			queuedRegeneration = false

			for index, slice in ipairs(cachedSlices) do
				Terrain:FillRegion(slice.Region, VOXEL_RESOLUTION, slice.Material)

				if index % TERRAIN_BATCH_SIZE == 0 then
					task.wait(TERRAIN_BATCH_YIELD)
				end
			end
		until not queuedRegeneration

		isRegenerating = false
		Workspace:SetAttribute("TerrainResetInProgress", false)
	end)
end

configureMaterialOverrides()
rebuildSliceCache()
runRegeneration()

groundParts.ChildAdded:Connect(function(child)
	if child:IsA("BasePart") then
		rebuildSliceCache()
	end
end)

groundParts.ChildRemoved:Connect(function(child)
	if child:IsA("BasePart") then
		rebuildSliceCache()
	end
end)

FinishTime.Event:Connect(runRegeneration)

return TerrainGeneratorManager
