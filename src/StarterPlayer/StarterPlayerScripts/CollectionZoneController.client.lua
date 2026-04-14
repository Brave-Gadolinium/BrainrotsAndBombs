--!strict
-- LOCATION: StarterPlayerScripts/CollectionZoneController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local ClientZoneService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClientZoneService"))
local FrameManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FrameManager"))
local TutorialConfiguration = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TutorialConfiguration"))

local SatchelFolder = ReplicatedStorage:WaitForChild("Satchel")
local SatchelLoader = SatchelFolder:WaitForChild("SatchelLoader")
local SatchelModule = SatchelLoader:WaitForChild("Satchel")
local Satchel = require(SatchelModule)

local player = Players.LocalPlayer
local backpackEnabled: boolean? = nil

local function isTutorialInventoryForced(): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	if onboardingStep <= 0 then
		return false
	end

	local presentation = TutorialConfiguration.GetStepPresentation(onboardingStep)
	return presentation.MaskUi and presentation.ShowInventory
end

local function shouldEnableBackpack(nextInMineZone: boolean): boolean
	if FrameManager.isAnyFrameOpen() then
		return false
	end

	if isTutorialInventoryForced() then
		return true
	end

	return not nextInMineZone
end

local function applyBackpackState(nextInMineZone: boolean)
	local nextBackpackEnabled = shouldEnableBackpack(nextInMineZone)
	if backpackEnabled == nextBackpackEnabled then
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		return
	end

	backpackEnabled = nextBackpackEnabled

	if Satchel.SetBackpackEnabled then
		Satchel:SetBackpackEnabled(nextBackpackEnabled)
	end

	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
applyBackpackState(ClientZoneService.IsInMineZone())

ClientZoneService.Changed:Connect(function(nextZone)
	applyBackpackState(nextZone ~= nil)
end)

FrameManager.Changed:Connect(function()
	applyBackpackState(ClientZoneService.IsInMineZone())
end)

player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
	applyBackpackState(ClientZoneService.IsInMineZone())
end)

player.CharacterAdded:Connect(function()
	task.defer(function()
		applyBackpackState(ClientZoneService.IsInMineZone())
	end)
end)

player.CharacterRemoving:Connect(function()
	applyBackpackState(false)
end)
