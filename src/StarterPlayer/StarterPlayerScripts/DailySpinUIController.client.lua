--!strict
-- LOCATION: StarterPlayerScripts/DailySpinUIController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

-- Modules
local Config = require(ReplicatedStorage.Modules.DailySpinConfiguration)
local ProductConfigs = require(ReplicatedStorage.Modules.ProductConfigurations)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local ItemConfigs = require(ReplicatedStorage.Modules.ItemConfigurations)

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")
local wheelFrame = gui:WaitForChild("Frames"):WaitForChild("Wheel")

-- Paths
local spinWheel = wheelFrame:WaitForChild("SpinWheel")
local pattern = spinWheel:WaitForChild("Pattern")
local buttons = wheelFrame:WaitForChild("Buttons")
local redArrow = wheelFrame:WaitForChild("RedArrow") :: ImageLabel 

-- UI Elements
local spinButton = buttons:WaitForChild("SpinButton") :: TextButton
local spinLabel = spinButton:FindFirstChild("Text") :: TextLabel
local robuxButton1 = buttons:WaitForChild("RobuxButton1") :: TextButton
local robuxButton2 = buttons:WaitForChild("RobuxButton2") :: TextButton

-- [[ CHANGED: HUD Wheel is now in Left.Buttons2 ]]
local leftButtons2 = hud:WaitForChild("Left"):WaitForChild("Buttons2")
local hudWheel = leftButtons2:WaitForChild("Wheel") :: TextButton
local hudWheelText = hud:WaitForChild("SpinnyWheel"):WaitForChild("WheelHolder"):WaitForChild("Ready") :: TextLabel
local hudWheelTextCountSpin = hud:WaitForChild("SpinnyWheel"):WaitForChild("WheelHolder"):WaitForChild("CountSpin") :: TextLabel 

local hudWheelNotification = hudWheel:FindFirstChild("Notification") :: Frame 

local RequestSpin = ReplicatedStorage:WaitForChild("Events"):WaitForChild("RequestSpin") :: RemoteFunction
local ReportAnalyticsIntent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("ReportAnalyticsIntent") :: RemoteEvent
local isSpinning = false
local ONE_DAY_SECONDS = 86400

-- [ FORMATTING ]
local function formatTime(seconds: number, showSeconds: boolean): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)

	if showSeconds then
		return string.format("%dh %dm %ds", h, m, s)
	else
		return string.format("%dh %dm", h, m)
	end
end

-- [ UPDATE UI TEXTS ]
local function updateSpinButton()
	local currentSpins = player:GetAttribute("SpinNumber") or 0
	local lastFreeSpin = player:GetAttribute("LastDailySpin") or 0
	local timeLeft = ONE_DAY_SECONDS - (os.time() - lastFreeSpin)

	if hudWheelNotification then
		if currentSpins > 0 or timeLeft <= 0 then
			hudWheelNotification.Visible = true
		else
			hudWheelNotification.Visible = false
		end
	end

	--================------------------------------------------------
	-- ## MAIN BUTTON & HUD LOGIC ##
	--================------------------------------------------------
	if currentSpins > 0 then
		spinLabel.Text = "Spin (" .. currentSpins .. ")"
		if hudWheelText then
			hudWheelText.Text = "Spin (" .. currentSpins .. ")"
			hudWheelText.TextColor3 = Color3.fromRGB(255, 255, 255)
		end

		hudWheelTextCountSpin.Text = '+' .. tostring(currentSpins)
	else
		hudWheelTextCountSpin.Text = ''

		if timeLeft <= 0 then
			spinLabel.Text = "READY!"
			if hudWheelText then
				hudWheelText.Text = "READY!"
				hudWheelText.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		else
			spinLabel.Text = formatTime(timeLeft, true) 
			if hudWheelText then
				hudWheelText.Text = formatTime(timeLeft, false) 
				hudWheelText.TextColor3 = Color3.fromRGB(255, 170, 0)
			end
		end
	end
end

-- [ SPIN LOGIC ]
local function playTickEffect()
	local sounds = game:GetService("Workspace"):FindFirstChild("Sounds")
	local tickSound = sounds and sounds:FindFirstChild("Tick")
	if tickSound and tickSound:IsA("Sound") then
		tickSound:Play()
	end

	redArrow.Rotation = -15 
	TweenService:Create(redArrow, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0}):Play()
end

local function animateSpin(targetIndex: number)
	isSpinning = true
	spinWheel.Rotation = 0

	local degreesPerSlot = 360 / 6
	local fullSpins = 5
	local finalAngle = (360 * fullSpins) + ((targetIndex - 1) * degreesPerSlot)

	local lastTickAngle = 0
	local rotationTracker = Instance.new("NumberValue")
	rotationTracker.Value = 0

	local rotationConn = rotationTracker.Changed:Connect(function(val)
		spinWheel.Rotation = val
		if val - lastTickAngle >= degreesPerSlot then
			lastTickAngle = val
			playTickEffect()
		end
	end)

	local tween = TweenService:Create(rotationTracker, TweenInfo.new(6.0, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Value = finalAngle})

	tween:Play()
	tween.Completed:Connect(function()
		rotationConn:Disconnect()
		rotationTracker:Destroy()

		local sounds = game:GetService("Workspace"):FindFirstChild("Sounds")
		local rewardSound = sounds and sounds:FindFirstChild("Reward")
		if rewardSound and rewardSound:IsA("Sound") then
			rewardSound:Play()
		end

		task.wait(0.5)
		isSpinning = false
		updateSpinButton()
	end)
end

-- [ BUTTONS & PRODUCTS ]
spinButton.MouseButton1Click:Connect(function()
	if isSpinning then return end
	isSpinning = true 

	local sounds = game:GetService("Workspace"):FindFirstChild("Sounds")
	local spinSound = sounds and sounds:FindFirstChild("Spin")
	if spinSound and spinSound:IsA("Sound") then
		spinSound:Play()
	end

	local result = RequestSpin:InvokeServer()

	if result and result.success then
		animateSpin(result.Index)
	else
		isSpinning = false
		NotificationManager.show("No spins available!", "Error")
	end
end)

local function updateProductLabels()
	task.spawn(function()
		local s1, p1 = pcall(function() return MarketplaceService:GetProductInfo(ProductConfigs.Products["SpinsX3"], Enum.InfoType.Product) end)
		local s2, p2 = pcall(function() return MarketplaceService:GetProductInfo(ProductConfigs.Products["SpinsX9"], Enum.InfoType.Product) end)

		if s1 and robuxButton1 then
			local btnText = robuxButton1:FindFirstChild("Text") :: TextLabel
			local btnPrice = robuxButton1:FindFirstChild("Price") :: TextLabel
			if btnText then btnText.Text = "+3 Spins!" end
			if btnPrice then btnPrice.Text = "" .. p1.PriceInRobux end
		end

		if s2 and robuxButton2 then
			local btnText = robuxButton2:FindFirstChild("Text") :: TextLabel
			local btnPrice = robuxButton2:FindFirstChild("Price") :: TextLabel
			if btnText then btnText.Text = "+9 Spins!" end
			if btnPrice then btnPrice.Text = "" .. p2.PriceInRobux end
		end
	end)
end

if ProductConfigs.Products["SpinsX3"] then
	robuxButton1.MouseButton1Click:Connect(function() MarketplaceService:PromptProductPurchase(player, ProductConfigs.Products["SpinsX3"]) end)
end
if ProductConfigs.Products["SpinsX9"] then
	robuxButton2.MouseButton1Click:Connect(function() MarketplaceService:PromptProductPurchase(player, ProductConfigs.Products["SpinsX9"]) end)
end

-- [ INIT ]
updateProductLabels()
task.spawn(function()
	while player:GetAttribute("SpinNumber") == nil do task.wait(0.5) end
	while true do 
		updateSpinButton()
		task.wait(1) 
	end
end)
player:GetAttributeChangedSignal("SpinNumber"):Connect(updateSpinButton)
player:GetAttributeChangedSignal("LastDailySpin"):Connect(updateSpinButton)

wheelFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if wheelFrame.Visible then
		ReportAnalyticsIntent:FireServer("DailySpinWheelOpened")
	end
end)

local totalWeight = Config.GetTotalWeight() 

for i = 1, 6 do
	local slot = pattern:FindFirstChild(tostring(i))
	local data = Config.Rewards[i]

	if slot and data then
		local img = slot:FindFirstChild("Image") :: ImageLabel
		local displayImage = data.Image

		if data.Type == "Item" then
			local itemData = ItemConfigs.GetItemData(data.Name)
			if itemData then displayImage = itemData.ImageId end
		end
		if img then img.Image = displayImage or "" end

		local chanceLabel = img and img:FindFirstChild("Chance") :: TextLabel
		if chanceLabel and totalWeight > 0 then
			local percent = (data.Chance / totalWeight) * 100
			chanceLabel.Text = string.format("(%.0f%%)", percent)
		end

		if slot:IsA("TextLabel") then
			if data.Type == "Cash" and data.Amount then
				slot.Text = "$" .. NumberFormatter.Format(data.Amount)
			elseif data.Type == "Spins" and data.Amount then
				slot.Text = "+" .. tostring(data.Amount) .. " Spins"
			else
				slot.Text = data.Name or ""
			end
		end
	end
end
