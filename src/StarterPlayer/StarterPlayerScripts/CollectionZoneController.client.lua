--!strict
-- LOCATION: StarterPlayerScripts/CollectionZoneController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local ClientZoneService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClientZoneService"))

local SatchelFolder = ReplicatedStorage:WaitForChild("Satchel")
local SatchelLoader = SatchelFolder:WaitForChild("SatchelLoader")
local SatchelModule = SatchelLoader:WaitForChild("Satchel")
local Satchel = require(SatchelModule)

local player = Players.LocalPlayer
local inMineZone: boolean? = nil

local function applyBackpackState(nextInMineZone: boolean)
	if inMineZone == nextInMineZone then
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		return
	end

	inMineZone = nextInMineZone

	if Satchel.SetBackpackEnabled then
		Satchel:SetBackpackEnabled(not nextInMineZone)
	end

	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
applyBackpackState(ClientZoneService.IsInMineZone())

ClientZoneService.Changed:Connect(function(nextZone)
	applyBackpackState(nextZone ~= nil)
end)

player.CharacterAdded:Connect(function()
	task.defer(function()
		applyBackpackState(ClientZoneService.IsInMineZone())
	end)
end)

player.CharacterRemoving:Connect(function()
	applyBackpackState(false)
end)
