--!strict
-- LOCATION: StarterPlayerScripts/GoldEventUIController

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- UI References
local mainGui = playerGui:WaitForChild("GUI")
local frames = mainGui:WaitForChild("Frames")
local notifications = frames:WaitForChild("Notifications")
--local goldEventLabel = notifications:WaitForChild("GoldEvent") :: TextLabel

-- Force the label to always be visible!
--goldEventLabel.Visible = true

--print("[GoldEventUIController] Loaded")

-- [ HELPER: Format Time ]
local function formatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	-- Formats cleanly like "05:00" or "00:59"
	return string.format("%02d:%02d", m, s)
end

-- [ UI UPDATE LOOP ]
RunService.Heartbeat:Connect(function()
	--local isActive = Workspace:GetAttribute("GoldEventActive")
	--local targetTime = Workspace:GetAttribute("GoldEventTime")

	--if targetTime then
	--	local remaining = math.max(0, targetTime - os.time())
	--	local timeStr = formatTime(remaining)

	--	if isActive then
	--		goldEventLabel.Text = "Gold event ends in " .. timeStr .. "!"
	--	else
	--		goldEventLabel.Text = "Gold event in " .. timeStr .. "!"
	--	end
	--else
	--	goldEventLabel.Text = "Waiting for Gold Event..."
	--end
end)