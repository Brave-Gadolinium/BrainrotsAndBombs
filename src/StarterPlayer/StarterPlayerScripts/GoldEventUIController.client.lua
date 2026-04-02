--!strict
-- LOCATION: StarterPlayerScripts/GoldEventUIController

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("GUI")
local hud = mainGui:WaitForChild("HUD")

local function hideEventBanner(instance: Instance?)
	if instance and instance:IsA("GuiObject") and instance.Name == "EventBrainrotBanner" then
		instance.Visible = false
	end
end

hideEventBanner(hud:FindFirstChild("EventBrainrotBanner", true))

hud.DescendantAdded:Connect(function(descendant)
	hideEventBanner(descendant)
end)
