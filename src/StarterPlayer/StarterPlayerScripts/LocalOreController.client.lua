--!strict
-- LOCATION: StarterPlayerScripts/LocalOreController

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local OreConfigurations = require(Modules:WaitForChild("OreConfigurations"))

local MinesFolder = Workspace:WaitForChild("Mines")
local OresFolder = ReplicatedStorage:WaitForChild("Ores")
local ZonesFolder = Workspace:WaitForChild("Zones") 

local player = Players.LocalPlayer

local GRID_SIZE = 4
local YIELD_THRESHOLD = 300 

local LocalOreController = {}

local function generateMineGrid(mineZone: BasePart)
	local mineName = mineZone.Name
	local zoneSize = mineZone.Size
	local zoneCFrame = mineZone.CFrame

	local stepsX = math.floor(zoneSize.X / GRID_SIZE)
	local stepsY = math.floor(zoneSize.Y / GRID_SIZE)
	local stepsZ = math.floor(zoneSize.Z / GRID_SIZE)

	local startX = (-zoneSize.X / 2) + (GRID_SIZE / 2)
	local startY = (-zoneSize.Y / 2) + (GRID_SIZE / 2)
	local startZ = (-zoneSize.Z / 2) + (GRID_SIZE / 2)

	local spawnedFolder = Instance.new("Folder")
	spawnedFolder.Name = "LocalOres_" .. mineName

	local oldFolder = MinesFolder:FindFirstChild(spawnedFolder.Name)
	if oldFolder then oldFolder:Destroy() end

	spawnedFolder.Parent = MinesFolder

	mineZone.Transparency = 1
	mineZone.CanCollide = false

	local blocksProcessed = 0

	task.spawn(function()
		for x = 0, stepsX - 1 do
			for y = 0, stepsY - 1 do
				for z = 0, stepsZ - 1 do

					local selectedOreName = OreConfigurations.GetRandomOre(mineName)
					local oreTemplate = OresFolder:FindFirstChild(selectedOreName)

					if oreTemplate and oreTemplate:IsA("BasePart") then
						local newOre = oreTemplate:Clone() :: BasePart

						newOre.Size = Vector3.new(GRID_SIZE, GRID_SIZE, GRID_SIZE)
						newOre.Anchored = true

						local maxHp = OreConfigurations.OreHealth[selectedOreName] or 20
						newOre:SetAttribute("MaxHealth", maxHp)
						newOre:SetAttribute("Health", maxHp)

						local offsetX = startX + (x * GRID_SIZE)
						local offsetY = startY + (y * GRID_SIZE)
						local offsetZ = startZ + (z * GRID_SIZE)

						newOre.CFrame = zoneCFrame * CFrame.new(offsetX, offsetY + 2, offsetZ)
						newOre.Parent = spawnedFolder
					end

					blocksProcessed += 1
					if blocksProcessed >= YIELD_THRESHOLD then
						blocksProcessed = 0
						task.wait() 
					end

				end
			end
		end
	end)
end

local function isInsideAnyZone(position: Vector3): boolean
	for _, zonePart in ipairs(ZonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size

			if math.abs(relativePos.X) <= (size.X / 2) + 2 and
				math.abs(relativePos.Y) <= (size.Y / 2) + 10 and 
				math.abs(relativePos.Z) <= (size.Z / 2) + 2 then
				return true
			end
		end
	end
	return false
end

function LocalOreController:Start()

	local function onMineAdded(zonePart: Instance)
		if zonePart:IsA("BasePart") and tonumber(zonePart.Name) then
			local folderName = "LocalOres_" .. zonePart.Name
			if not MinesFolder:FindFirstChild(folderName) then
				--generateMineGrid(zonePart)
			end
		end
	end

	for _, zonePart in ipairs(MinesFolder:GetChildren()) do
		onMineAdded(zonePart)
	end
	MinesFolder.ChildAdded:Connect(onMineAdded)

	local wasInZone = false

	RunService.Heartbeat:Connect(function()
		local char = player.Character
		if not char then return end

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
		local humanoid = char:FindFirstChild("Humanoid") :: Humanoid
		if not root or not humanoid then return end

		local currentlyInZone = isInsideAnyZone(root.Position)

		if currentlyInZone and not wasInZone then
			-- Player just ENTERED the zone -> Disable Jumping
			--humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

		elseif not currentlyInZone and wasInZone then
			-- Player just LEFT the zone -> Enable Jumping
			--humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

			-- Reset impacted mines
			for _, folder in ipairs(MinesFolder:GetChildren()) do
				if folder:IsA("Folder") and folder.Name:match("LocalOres_") and folder:GetAttribute("Impacted") then
					local mineId = folder.Name:gsub("LocalOres_", "")
					local mineZonePart = MinesFolder:FindFirstChild(mineId)

					if mineZonePart and mineZonePart:IsA("BasePart") then
						--generateMineGrid(mineZonePart)
					end
				end
			end
		end

		wasInZone = currentlyInZone
	end)
end

LocalOreController:Start()

return LocalOreController
