--!strict
-- LOCATION: StarterPlayerScripts/RebirthUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local Events = ReplicatedStorage:WaitForChild("Events")
local RequestRebirth = Events:WaitForChild("RequestRebirth")
local UpdateEvent = Events:WaitForChild("UpdateRebirthUI")
local ReportAnalyticsIntent = Events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")

local hudLeft1 = hud:WaitForChild("Left"):WaitForChild("Buttons1")
local hudRebirthBtn = hudLeft1:WaitForChild("Rebirth") :: TextButton
local notificationDot = hudRebirthBtn:FindFirstChild("Notification") :: Frame

local frames = gui:WaitForChild("Frames")
local rebirthFrame = frames:WaitForChild("Rebirth")
local contentFrame = rebirthFrame:WaitForChild("Frame") 

local statsFrame = contentFrame:WaitForChild("Stats")
local beforeLabel = statsFrame:WaitForChild("Before"):WaitForChild("Money"):WaitForChild("Text") :: TextLabel
local afterLabel = statsFrame:WaitForChild("After"):WaitForChild("Money"):WaitForChild("Text") :: TextLabel

local barFrame = contentFrame:WaitForChild("Bar")
local progressFill = barFrame:WaitForChild("Progress") :: Frame
local progressText = barFrame:WaitForChild("Text") :: TextLabel

local rebirthButton = rebirthFrame:WaitForChild("Rebirth") :: TextButton
local skipButton = rebirthFrame:WaitForChild("Skip") :: TextButton

-- Make sure these match the server settings!
local BASE_REBIRTH_COST = 1000000 
local REBIRTH_COST_STEP = 500000

local TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function getRebirthCost(rebirths: number): number
	return BASE_REBIRTH_COST + (rebirths * REBIRTH_COST_STEP)
end

local function updateUI()
	local rebirths = player:GetAttribute("Rebirths") or 0
	local cost = getRebirthCost(rebirths)

	-- Read current Money safely
	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyStat = leaderstats and leaderstats:FindFirstChild("Money") :: NumberValue
	local currentMoney = moneyStat and moneyStat.Value or 0

	local currentMult = 1 + (rebirths * 0.5)
	local nextMult = 1 + ((rebirths + 1) * 0.5)

	beforeLabel.Text = "x" .. string.format("%.1f", currentMult)
	afterLabel.Text = "x" .. string.format("%.1f", nextMult)

	local percentage = math.clamp(currentMoney / cost, 0, 1)

	progressText.Text = "Cash $" .. NumberFormatter.Format(currentMoney) .. " / $" .. NumberFormatter.Format(cost)
	TweenService:Create(progressFill, TWEEN_INFO, {Size = UDim2.fromScale(percentage, 1)}):Play()

	if notificationDot then notificationDot.Visible = (currentMoney >= cost) end

	if currentMoney >= cost then
		rebirthButton.AutoButtonColor = true
		rebirthButton.BackgroundColor3 = Color3.fromRGB(0, 170, 0)
	else
		rebirthButton.AutoButtonColor = false
		rebirthButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	end
end

if rebirthButton then rebirthButton.MouseButton1Click:Connect(function() RequestRebirth:FireServer() end) end
if skipButton then
	skipButton.MouseButton1Click:Connect(function()
		local productId = ProductConfigurations.Products["SkipRebirth"]
		if productId then MarketplaceService:PromptProductPurchase(player, productId) end
	end)
end

-- Wait for leaderstats to load, then connect the money change event
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local moneyStat = leaderstats:WaitForChild("Money", 10)
		if moneyStat then
			moneyStat.Changed:Connect(updateUI)
			updateUI()
		end
	end
end)

player:GetAttributeChangedSignal("Rebirths"):Connect(updateUI)
UpdateEvent.OnClientEvent:Connect(updateUI)
updateUI()

rebirthFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if rebirthFrame.Visible then
		ReportAnalyticsIntent:FireServer("RebirthUIOpened")
	end
end)
