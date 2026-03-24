--!strict
-- LOCATION: StarterPlayerScripts/PlotController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundFolder = Workspace:WaitForChild("Sounds")

-- Modules
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local requestUpgradeEvent = Events:WaitForChild("RequestBaseUpgrade")

print("[PlotController] Loaded.")

-- Variables to hold current references
local plotUpgradeGui: SurfaceGui?
local upgradeButton: TextButton?
local levelsLabel: TextLabel?
local priceLabel: TextLabel?
local currentGuiPart: BasePart?
local upgradeConnection: RBXScriptConnection?
local attributeConnection: RBXScriptConnection?

-- 1. Initialize GUI References (Runs on Spawn)
local function refreshGuiReferences()
	local gui = nil
	local attempts = 0
	while not gui and attempts < 10 do
		gui = playerGui:FindFirstChild("PlotUpgradeGUI")
		if not gui then task.wait(0.5) end
		attempts += 1
	end

	if not gui then 
		warn("[PlotController] Could not find PlotUpgradeGUI after respawn.")
		return 
	end

	plotUpgradeGui = gui :: SurfaceGui
	upgradeButton = plotUpgradeGui:WaitForChild("UpgradeButton") :: TextButton
	levelsLabel = upgradeButton:WaitForChild("Levels") :: TextLabel
	priceLabel = upgradeButton:WaitForChild("Price") :: TextLabel

	if upgradeConnection then upgradeConnection:Disconnect() end

	upgradeConnection = upgradeButton.MouseButton1Click:Connect(function()
		-- Sound Logic
		local firework = SoundFolder:FindFirstChild("Upgrade")
		if firework then firework:Play() end

		requestUpgradeEvent:FireServer()
	end)
end

-- 2. Function to attach the GUI to the 3D Part
local function attachGuiToPart(guiPart: BasePart)
	if currentGuiPart == guiPart then return end -- Already attached

	currentGuiPart = guiPart
	if not plotUpgradeGui then return end

	plotUpgradeGui.Adornee = guiPart
	plotUpgradeGui.Enabled = true

	local currentLevel = guiPart:GetAttribute("CurrentLevel") or 0
	local maxLevel = guiPart:GetAttribute("MaxLevel") or 6
	local price = guiPart:GetAttribute("Price") or 0

	if levelsLabel then levelsLabel.Text = tostring(currentLevel) .. "/" .. tostring(maxLevel) end

	if priceLabel and upgradeButton then
		if currentLevel >= maxLevel then
			priceLabel.Text = "MAX"
			upgradeButton.Active = false
		else
			priceLabel.Text = "$" .. NumberFormatter.Format(price)
			upgradeButton.Active = true
		end
	end

	if attributeConnection then attributeConnection:Disconnect() end
	attributeConnection = guiPart.AttributeChanged:Connect(function(attr)
		local newLevel = guiPart:GetAttribute("CurrentLevel") or 0
		local newMax = guiPart:GetAttribute("MaxLevel") or 6
		local newPrice = guiPart:GetAttribute("Price") or 0

		if attr == "CurrentLevel" then
			if levelsLabel then levelsLabel.Text = tostring(newLevel) .. "/" .. tostring(newMax) end
		elseif attr == "Price" then
			if priceLabel and upgradeButton then
				if newLevel >= newMax then
					priceLabel.Text = "MAX"
					upgradeButton.Active = false
				else
					priceLabel.Text = "$" .. NumberFormatter.Format(newPrice)
					upgradeButton.Active = true
				end
			end
		end
	end)
end

-- 3. Dynamic GUI Finder (Hunts for the currently visible BuyFloor GUIPart)
local function startGuiTracker(plotModel: Model)
	task.spawn(function()
		-- Enable Spawn PlotGUI 
		local spawnPart = plotModel:WaitForChild("Spawn", 20)
		if spawnPart then
			local plotGui = spawnPart:WaitForChild("PlotGUI", 20) :: SurfaceGui
			if plotGui then
				plotGui.Enabled = true 
			end
		end

		-- Loop to ensure the UI is always snapped to the active floor's Buy terminal
		while plotModel and plotModel.Parent do
			local foundActivePart = nil

			for i = 1, 20 do
				local floor = plotModel:FindFirstChild("Floor" .. i)
				if floor then
					local buyFloor = floor:FindFirstChild("BuyFloor")
					if buyFloor then
						local guiPart = buyFloor:FindFirstChild("GUIPart")
						-- Check if this specific GUIPart is visible (Transparency < 1)
						if guiPart and guiPart:IsA("BasePart") and guiPart.Transparency < 1 then
							foundActivePart = guiPart
							break
						end
					end
				end
			end

			if foundActivePart then
				attachGuiToPart(foundActivePart)
			elseif plotUpgradeGui then
				plotUpgradeGui.Enabled = false
				currentGuiPart = nil
			end

			task.wait(0.5) -- Check efficiently
		end
	end)
end

-- 4. Find My Plot
local function findMyPlot()
	local plotName = "Plot_" .. player.Name

	local existingPlot = Workspace:FindFirstChild(plotName)
	if existingPlot then
		startGuiTracker(existingPlot)
	end

	local conn
	conn = Workspace.ChildAdded:Connect(function(child)
		if child.Name == plotName then
			startGuiTracker(child)
			conn:Disconnect()
		end
	end)
end

-- 5. Handle Respawn
local function onCharacterSpawn()
	task.wait(0.5)
	refreshGuiReferences()
	findMyPlot()
end

if player.Character then onCharacterSpawn() end
player.CharacterAdded:Connect(onCharacterSpawn)