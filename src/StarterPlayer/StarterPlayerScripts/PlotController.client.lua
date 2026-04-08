--!strict
-- LOCATION: StarterPlayerScripts/PlotController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestSlotPurchaseEvent = events:WaitForChild("RequestSlotPurchase")
local soundFolder = Workspace:WaitForChild("Sounds")

local currentButton: TextButton? = nil
local buttonConnection: RBXScriptConnection? = nil
local workspaceConnection: RBXScriptConnection? = nil

print("[PlotController] Loaded (Slot Upgrade Button)")

local function disconnectButton()
	if buttonConnection then
		buttonConnection:Disconnect()
		buttonConnection = nil
	end
	currentButton = nil
end

local function connectUpgradeButton(button: TextButton)
	if currentButton == button then
		return
	end

	disconnectButton()
	currentButton = button

	buttonConnection = button.MouseButton1Click:Connect(function()
		local upgradeSound = soundFolder:FindFirstChild("Upgrade")
		if upgradeSound and upgradeSound:IsA("Sound") then
			upgradeSound:Play()
		end

		requestSlotPurchaseEvent:FireServer()
	end)
end

local function bindPlot(plotModel: Model)
	local upgradeModel = plotModel:WaitForChild("UpgradeSlotsButton", 10)
	local mainGui = upgradeModel and upgradeModel:WaitForChild("MainGUI", 10)
	local surfaceGui = mainGui and mainGui:WaitForChild("SurfaceGuiA", 10)
	local frame = surfaceGui and surfaceGui:WaitForChild("FrameB", 10)
	local upgradeButton = frame and frame:WaitForChild("UpgradeButton", 10)

	if upgradeButton and upgradeButton:IsA("TextButton") then
		connectUpgradeButton(upgradeButton)
	end
end

local function watchMyPlot()
	local plotName = "Plot_" .. player.Name
	local existingPlot = Workspace:FindFirstChild(plotName)
	if existingPlot and existingPlot:IsA("Model") then
		bindPlot(existingPlot)
	end

	if workspaceConnection then
		return
	end

	workspaceConnection = Workspace.ChildAdded:Connect(function(child)
		if child.Name == plotName and child:IsA("Model") then
			bindPlot(child)
		end
	end)
end

if player.Character then
	task.defer(watchMyPlot)
end

player.CharacterAdded:Connect(function()
	task.wait(0.25)
	watchMyPlot()
end)
