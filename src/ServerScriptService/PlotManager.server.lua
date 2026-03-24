--!strict
-- LOCATION: ServerScriptService/PlotManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- Modules
local PlayerController = require(ServerScriptService.Controllers.PlayerController)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

-- Assets
local Templates = ReplicatedStorage:WaitForChild("Templates")
local PlotTemplate = Templates:WaitForChild("Plot")
local PlotsFolder = Workspace:WaitForChild("Plots")
local Events = ReplicatedStorage:WaitForChild("Events")

-- [ CONFIGURATION: PRICES ]
-- BaseLevel 0 means only Floor1 is unlocked.
-- Purchasing the upgrade increases BaseLevel by 1 and unlocks Floor(BaseLevel + 1).
local UPGRADE_PRICES = {
	[0] = 25000,    -- Cost to unlock Floor 2
	[1] = 100000,   -- Cost to unlock Floor 3
}
local MAX_LEVEL = 2

-- State
local occupiedPlots = {} 
local activePlotModels = {} 

local PlotManager = {}
function PlotManager.GetPrice(currentLevel: number)
	return UPGRADE_PRICES[currentLevel]
end
function PlotManager.GetMaxLevel()
	return MAX_LEVEL
end

-- [ HELPER FUNCTIONS ] -------------------------------------------------------

local function getFreePlotIndex(): number?
	for i = 1, 5 do
		local taken = false
		for _, index in pairs(occupiedPlots) do
			if index == i then taken = true; break end
		end
		if not taken then return i end
	end
	return nil
end

local function storeOriginalProperties(model: Instance)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			if child:GetAttribute("OriginalTransparency") == nil then
				child:SetAttribute("OriginalTransparency", child.Transparency)
				child:SetAttribute("OriginalCanCollide", child.CanCollide)
			end
		end
	end
end

local function setModelVisibility(model: Instance, isVisible: boolean)
	if not model then return end
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			if isVisible then
				child.Transparency = child:GetAttribute("OriginalTransparency") or 0
				local collide = child:GetAttribute("OriginalCanCollide")
				if collide == nil then collide = true end
				child.CanCollide = collide
			else
				child.Transparency = 1
				child.CanCollide = false
			end
		end
	end
end

local function updatePlotVisuals(player: Player, baseLevel: number)
	local plotModel = activePlotModels[player]
	if not plotModel then return end

	-- Ensure originals are stored first
	storeOriginalProperties(plotModel)

	-- Check up to 20 potential floors
	for i = 1, 20 do
		local floor = plotModel:FindFirstChild("Floor" .. i)
		if floor then
			-- Is this floor unlocked? (BaseLevel 0 = Floor 1, BaseLevel 1 = Floor 2, etc.)
			if i <= baseLevel + 1 then
				-- 1. Unhide Floor
				setModelVisibility(floor, true)

				-- 2. Unlock all slots on this floor instantly
				local slotsFolder = floor:FindFirstChild("Slots")
				if slotsFolder then
					for _, slot in ipairs(slotsFolder:GetChildren()) do
						slot:SetAttribute("IsUnlocked", true)
					end
				end

				-- 3. Manage the BuyFloor terminal
				local buyFloor = floor:FindFirstChild("BuyFloor")
				if buyFloor then
					-- Only show the BuyFloor for the HIGHEST currently unlocked floor
					if i == baseLevel + 1 and baseLevel < PlotManager.GetMaxLevel() then
						setModelVisibility(buyFloor, true)

						local guiPart = buyFloor:FindFirstChild("GUIPart")
						if guiPart then
							guiPart:SetAttribute("CurrentLevel", baseLevel)
							guiPart:SetAttribute("MaxLevel", PlotManager.GetMaxLevel())
							guiPart:SetAttribute("Price", UPGRADE_PRICES[baseLevel] or 0)
							guiPart:SetAttribute("OwnerId", player.UserId)
						end
					else
						-- Hide old BuyFloors or hide it if max level is reached
						setModelVisibility(buyFloor, false)
					end
				end

			else
				-- Floor is still locked, hide everything inside it
				setModelVisibility(floor, false)
			end
		end
	end
end

-- [ CORE LOGIC ] -------------------------------------------------------------

local function spawnPlot(player: Player)
	local index = getFreePlotIndex()
	if not index then player:Kick("No plots available."); return end

	occupiedPlots[player] = index

	local locator = PlotsFolder:FindFirstChild(tostring(index))
	if not locator then warn("Locator not found") return end

	local newPlot = PlotTemplate:Clone()
	newPlot.Name = "Plot_" .. player.Name
	newPlot.Parent = Workspace
	newPlot:SetPrimaryPartCFrame(locator.CFrame)

	local spawnPart = newPlot:FindFirstChild("Spawn")
	if spawnPart then
		local plotGui = spawnPart:FindFirstChild("PlotGUI") :: SurfaceGui
		if plotGui then plotGui.Enabled = false end
	end

	activePlotModels[player] = newPlot

	local profile = PlayerController:GetProfile(player)
	if profile then
		updatePlotVisuals(player, profile.Data.BaseLevel or 0)
	end
end

local function handleCharacterSpawn(player: Player, character: Model)
	local plotModel = activePlotModels[player]
	if plotModel and plotModel.PrimaryPart then
		character:WaitForChild("HumanoidRootPart").CFrame = plotModel.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
	end
end

-- [ EVENTS ] -----------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	repeat task.wait() until PlayerController:GetProfile(player)
	spawnPlot(player)

	player.CharacterAdded:Connect(function(char)
		task.wait(0.1) 
		handleCharacterSpawn(player, char)
	end)

	if player.Character then handleCharacterSpawn(player, player.Character) end
end)

Players.PlayerRemoving:Connect(function(player)
	if activePlotModels[player] then
		activePlotModels[player]:Destroy()
		activePlotModels[player] = nil
	end
	occupiedPlots[player] = nil
end)

local requestUpgrade = Events:WaitForChild("RequestBaseUpgrade")

requestUpgrade.OnServerEvent:Connect(function(player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	local currentLevel = profile.Data.BaseLevel or 0
	if currentLevel >= MAX_LEVEL then return end

	local price = UPGRADE_PRICES[currentLevel]

	if PlayerController:DeductMoney(player, price) then
		local newLevel = PlayerController:IncrementBaseLevel(player)
		updatePlotVisuals(player, newLevel)

		local notif = Events:FindFirstChild("ShowNotification")
		if notif then notif:FireClient(player, "New Floor Unlocked!", "Success") end
	else
		local notif = Events:FindFirstChild("ShowNotification")
		if notif then notif:FireClient(player, "Not enough Money!", "Error") end
	end
end)

print("[PlotManager] Active (Floor Upgrade Logic)")

return PlotManager