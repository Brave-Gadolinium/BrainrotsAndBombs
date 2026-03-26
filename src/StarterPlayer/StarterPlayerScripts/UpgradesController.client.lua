--!strict
-- LOCATION: StarterPlayerScripts/UpgradesController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Player = Players.LocalPlayer
local playerGui = Player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")
local UpgradeEvent = Events:WaitForChild("RequestSlotUpgrade")

local SoundFolder = Workspace:WaitForChild("Sounds")

local UpgradesController = {}

print("[UpgradesController] Loaded")

local function hideSlotUpgrade(button: TextButton)
	button.Visible = false
	button.Active = false
	button.AutoButtonColor = false

	local surfaceGui = button.Parent
	if surfaceGui and surfaceGui:IsA("SurfaceGui") then
		-- Можно разблокировать и будут видны улучшения слотов.
		surfaceGui.Enabled = false
	end
end

local function setupButton(button: TextButton)
	if button:FindFirstAncestor("UpgradeSlotsButton") then
		return
	end
	hideSlotUpgrade(button)
end

local function onDescendantAdded(descendant: Instance)
	if descendant:IsA("TextButton") and descendant.Name == "UpgradeButton" then
		setupButton(descendant)
	end
end

-- Start Listening
local function initialize()
	local plotName = "Plot_" .. Player.Name
	local plot = Workspace:WaitForChild(plotName, 10)

	if plot then
		-- Check existing buttons
		for _, desc in ipairs(plot:GetDescendants()) do
			onDescendantAdded(desc)
		end
		-- Listen for new ones
		plot.DescendantAdded:Connect(onDescendantAdded)
	end

	-- Also listen for plot creation if it doesn't exist yet
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == plotName then
			child.DescendantAdded:Connect(onDescendantAdded)
		end
	end)
end

task.spawn(initialize)

return UpgradesController
