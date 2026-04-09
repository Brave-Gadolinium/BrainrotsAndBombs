--!strict
-- LOCATION: StarterPlayerScripts/DropController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientZoneService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClientZoneService"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local DropEvent = Events:WaitForChild("RequestDropItem")

local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")
local dropButton = hud:WaitForChild("Drop") :: GuiButton

local characterConnections: {RBXScriptConnection} = {}
local isInMineZone = false
local isCarrying = false

local function disconnectConnections(connections: {RBXScriptConnection})
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function updateDropButton()
	dropButton.Visible = isInMineZone and isCarrying
end

local function refreshCarryingState(character: Model?)
	isCarrying = character ~= nil and character:FindFirstChild("StackItem") ~= nil
	updateDropButton()
end

local function bindCharacter(character: Model?)
	disconnectConnections(characterConnections)
	refreshCarryingState(character)

	if not character then
		return
	end

	table.insert(characterConnections, character.ChildAdded:Connect(function(child)
		if child.Name == "StackItem" then
			refreshCarryingState(character)
		end
	end))

	table.insert(characterConnections, character.ChildRemoved:Connect(function(child)
		if child.Name == "StackItem" then
			refreshCarryingState(character)
		end
	end))
end

dropButton.MouseButton1Click:Connect(function()
	if dropButton.Visible then
		DropEvent:FireServer()
	end
end)

isInMineZone = ClientZoneService.IsInMineZone()
bindCharacter(player.Character)
updateDropButton()

ClientZoneService.Changed:Connect(function(nextZone)
	isInMineZone = nextZone ~= nil
	updateDropButton()
end)

player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
end)

player.CharacterRemoving:Connect(function()
	bindCharacter(nil)
end)
