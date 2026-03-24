local TerrainGeneratorManager = {}

local Terrain = workspace.Terrain
local groundParts = workspace:WaitForChild("Mines")
local FinishTime = game.ReplicatedStorage.Remotes.Timer.FinishTime

local VOXEL_RESOLUTION = 4

-- Очистка текущего ландшафта
Terrain:Clear()

-- Таблица соответствия зон и материалов
local ZoneMaterials = {
	["Zone1"] = Enum.Material.Grass,
	["Zone2"] = Enum.Material.Neon,
	["Zone3"] = Enum.Material.Sand,
	["Zone4"] = Enum.Material.Granite,
	["Zone5"] = Enum.Material.CrackedLava
}

for _, groundPart in pairs(groundParts:GetChildren()) do
	if not groundPart:IsA("BasePart") then continue end

	local material = ZoneMaterials[groundPart.Name] or Enum.Material.Sand

	-- Размеры и позиция зоны
	local size = groundPart.Size
	local cframe = groundPart.CFrame

	local min = (cframe.Position - size / 2)
	local max = (cframe.Position + size / 2)

	local region = Region3.new(min, max):ExpandToGrid(VOXEL_RESOLUTION)

	Terrain:FillRegion(region, VOXEL_RESOLUTION, material)
end

FinishTime.Event:Connect(function()
	Terrain:Clear()
	
	for _, groundPart in pairs(groundParts:GetChildren()) do
		if not groundPart:IsA("BasePart") then continue end

		local material = ZoneMaterials[groundPart.Name] or Enum.Material.Sand

		-- Размеры и позиция зоны
		local size = groundPart.Size
		local cframe = groundPart.CFrame

		local min = (cframe.Position - size / 2)
		local max = (cframe.Position + size / 2)

		local region = Region3.new(min, max):ExpandToGrid(VOXEL_RESOLUTION)

		Terrain:FillRegion(region, VOXEL_RESOLUTION, material)
	end
end)

return TerrainGeneratorManager