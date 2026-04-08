local BACK_BUTTON_TEXT = "Back to base"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrameManager = require(ReplicatedStorage.Modules.FrameManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local framesContainer = playerGui:WaitForChild("GUI"):WaitForChild("Frames")
local button = script.Parent
local trackedFrames = {}

local function applyBackButtonCopy(target: Instance)
	if target:IsA("TextButton") or target:IsA("TextLabel") then
		--target.Text = BACK_BUTTON_TEXT
	end
end

local function isBlockingFrame(frame: Instance): boolean
	return frame:IsA("GuiObject") and frame.Name ~= "Notifications"
end

local function isAnyBlockingFrameVisible(): boolean
	if FrameManager.isAnyFrameOpen() then
		return true
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if isBlockingFrame(child) and child.Visible then
			return true
		end
	end

	return false
end

local function refreshBackButtonVisibility()
	if button:IsA("GuiButton") then
		button.Visible = not isAnyBlockingFrameVisible()
	end
end

local function trackFrame(frame: Instance)
	if not isBlockingFrame(frame) then
		return
	end

	if trackedFrames[frame] then
		return
	end

	trackedFrames[frame] = frame:GetPropertyChangedSignal("Visible"):Connect(refreshBackButtonVisibility)
end

local function untrackFrame(frame: Instance)
	local connection = trackedFrames[frame]
	if connection then
		connection:Disconnect()
		trackedFrames[frame] = nil
	end
end

applyBackButtonCopy(button)

local label = button:FindFirstChild("Text", true)
if label then
	applyBackButtonCopy(label)
end

button.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "Text" or descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
		applyBackButtonCopy(descendant)
	end
end)

button.MouseButton1Click:Connect(function()
	game.ReplicatedStorage.Remotes.Helper.TeleportPlayer:FireServer()
end)

for _, child in ipairs(framesContainer:GetChildren()) do
	trackFrame(child)
end

framesContainer.ChildAdded:Connect(function(child)
	trackFrame(child)
	refreshBackButtonVisibility()
end)

framesContainer.ChildRemoved:Connect(function(child)
	untrackFrame(child)
	refreshBackButtonVisibility()
end)

refreshBackButtonVisibility()
