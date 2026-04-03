--!strict
-- LOCATION: StarterPlayerScripts/RewardedAdButtonController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NotificationManager = require(Modules:WaitForChild("NotificationManager"))
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))
local ProductConfigurations = require(Modules:WaitForChild("ProductConfigurations"))

local Events = ReplicatedStorage:WaitForChild("Events")
local requestRewardedAdEvent = Events:WaitForChild("RequestRewardedAd") :: RemoteEvent
local rewardedAdResultEvent = Events:WaitForChild("RewardedAdResult") :: RemoteEvent

local BUTTON_NAME = "RewardedAdButton"
local REQUEST_TIMEOUT = 30
local HOVER_SCALE = 1.04
local CLICK_SCALE = 0.96
local TWEEN_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local button: TextButton? = nil
local buttonScale: UIScale? = nil
local titleLabel: TextLabel? = nil
local subtitleLabel: TextLabel? = nil
local buttonStroke: UIStroke? = nil
local requestSerial = 0
local requestPending = false

local function isRewardedAdConfigured(): boolean
	local rewardKey = ProductConfigurations.PrimaryRewardedAdKey
	if type(rewardKey) ~= "string" or rewardKey == "" then
		return false
	end

	local rewardConfig = ProductConfigurations.RewardedAdRewards[rewardKey]
	if type(rewardConfig) ~= "table" then
		return false
	end

	local productId = ProductConfigurations.Products[rewardKey]
	return type(productId) == "number" and productId > 0
end

local function getRewardConfig(): {[string]: any}
	local rewardKey = ProductConfigurations.PrimaryRewardedAdKey
	local rewardConfig = if type(rewardKey) == "string" then ProductConfigurations.RewardedAdRewards[rewardKey] else nil
	if type(rewardConfig) == "table" then
		return rewardConfig
	end

	return {
		CashAmount = 100,
		ButtonTitle = "WATCH AD",
		ButtonSubtitle = "+100 SOFT",
	}
end

local function buildSubtitleText(rewardConfig: {[string]: any}): string
	local configuredSubtitle = rewardConfig.ButtonSubtitle
	if type(configuredSubtitle) == "string" and configuredSubtitle ~= "" then
		return configuredSubtitle
	end

	local rewardAmount = math.max(0, math.floor(tonumber(rewardConfig.CashAmount) or 100))
	return "+" .. NumberFormatter.Format(rewardAmount) .. " SOFT"
end

local function setupButtonAnimation(targetButton: TextButton, scale: UIScale)
	targetButton.MouseEnter:Connect(function()
		if requestPending then
			return
		end

		TweenService:Create(scale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play()
	end)

	targetButton.MouseLeave:Connect(function()
		local targetScale = if requestPending then 1 else 1
		TweenService:Create(scale, TWEEN_INFO, {Scale = targetScale}):Play()
	end)

	targetButton.MouseButton1Down:Connect(function()
		if requestPending then
			return
		end

		TweenService:Create(scale, TWEEN_INFO, {Scale = CLICK_SCALE}):Play()
	end)

	targetButton.MouseButton1Up:Connect(function()
		if requestPending then
			return
		end

		TweenService:Create(scale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play()
	end)
end

local function getMainGui(): ScreenGui?
	local playerGui = player:FindFirstChild("PlayerGui")
	local mainGui = playerGui and playerGui:FindFirstChild("GUI")
	if mainGui and mainGui:IsA("ScreenGui") then
		return mainGui
	end

	return nil
end

local function getButtonParent(): GuiObject?
	local mainGui = getMainGui()
	local hud = mainGui and mainGui:FindFirstChild("HUD")
	if not hud or not hud:IsA("GuiObject") then
		return nil
	end

	local leftPanel = hud:FindFirstChild("Left")
	local buttonsFrame = leftPanel and leftPanel:FindFirstChild("Buttons1")
	if buttonsFrame and buttonsFrame:IsA("GuiObject") then
		return buttonsFrame
	end

	return hud
end

local function findReferenceButton(parent: GuiObject): GuiButton?
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name ~= BUTTON_NAME and child:IsA("GuiButton") then
			return child
		end
	end

	return nil
end

local function updateButtonVisuals()
	if not button or not titleLabel or not subtitleLabel then
		return
	end

	local rewardConfig = getRewardConfig()
	titleLabel.Text = if requestPending then "OPENING..." else tostring(rewardConfig.ButtonTitle or "WATCH AD")
	subtitleLabel.Text = if requestPending then "PLEASE WAIT" else buildSubtitleText(rewardConfig)

	button.Active = not requestPending
	button.AutoButtonColor = false
	button.BackgroundTransparency = if requestPending then 0.2 else 0.08

	if buttonStroke then
		buttonStroke.Color = if requestPending then Color3.fromRGB(255, 196, 112) else Color3.fromRGB(255, 168, 70)
	end
end

local function ensureButton(): TextButton?
	if not isRewardedAdConfigured() then
		if button and button.Parent then
			button:Destroy()
		end

		return nil
	end

	if button and button.Parent then
		updateButtonVisuals()
		return button
	end

	local parent = getButtonParent()
	if not parent then
		return nil
	end

	local referenceButton = findReferenceButton(parent)

	local newButton = Instance.new("TextButton")
	newButton.Name = BUTTON_NAME
	newButton.Text = ""
	newButton.AutoButtonColor = false
	newButton.BorderSizePixel = 0
	newButton.BackgroundColor3 = Color3.fromRGB(26, 33, 53)
	newButton.BackgroundTransparency = 0.08
	newButton.ZIndex = 12

	if parent.Name == "Buttons1" then
		newButton.Size = if referenceButton then referenceButton.Size else UDim2.new(1, 0, 0, 56)
		newButton.LayoutOrder = 999
	else
		newButton.AnchorPoint = Vector2.new(1, 0)
		newButton.Position = UDim2.new(1, -24, 0, 120)
		newButton.Size = if referenceButton then referenceButton.Size else UDim2.fromOffset(188, 60)
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = newButton

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.12
	stroke.Color = Color3.fromRGB(255, 168, 70)
	stroke.Parent = newButton

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 135
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 163, 77)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 207, 107)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 122, 94)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.72),
		NumberSequenceKeypoint.new(0.5, 0.84),
		NumberSequenceKeypoint.new(1, 0.62),
	})
	gradient.Parent = newButton

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -20, 1, -12)
	content.Position = UDim2.new(0, 10, 0, 6)
	content.ZIndex = 13
	content.Parent = newButton

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Vertical
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	contentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	contentLayout.Padding = UDim.new(0, 1)
	contentLayout.Parent = content

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.Text = "WATCH AD"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	title.ZIndex = 13
	title.Parent = content

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.Font = Enum.Font.GothamSemibold
	subtitle.Text = "+100 SOFT"
	subtitle.TextColor3 = Color3.fromRGB(255, 231, 162)
	subtitle.TextSize = 12
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.ZIndex = 13
	subtitle.Parent = content

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = newButton

	button = newButton
	buttonScale = scale
	titleLabel = title
	subtitleLabel = subtitle
	buttonStroke = stroke

	setupButtonAnimation(newButton, scale)

	newButton.Activated:Connect(function()
		if requestPending then
			return
		end

		requestPending = true
		requestSerial += 1
		local currentRequestSerial = requestSerial
		updateButtonVisuals()
		requestRewardedAdEvent:FireServer()

		task.delay(REQUEST_TIMEOUT, function()
			if requestPending and requestSerial == currentRequestSerial then
				requestPending = false
				updateButtonVisuals()
				NotificationManager.show("Rewarded ad request timed out. Try again.", "Error")
			end
		end)
	end)

	newButton.AncestryChanged:Connect(function(_, newParent)
		if newParent then
			return
		end

		button = nil
		buttonScale = nil
		titleLabel = nil
		subtitleLabel = nil
		buttonStroke = nil
	end)

	newButton.Parent = parent
	updateButtonVisuals()
	return newButton
end

rewardedAdResultEvent.OnClientEvent:Connect(function(status: string, message: string?)
	requestPending = false
	if buttonScale then
		TweenService:Create(buttonScale, TWEEN_INFO, {Scale = 1}):Play()
	end
	updateButtonVisuals()

	if status ~= "Success" and type(message) == "string" and message ~= "" then
		NotificationManager.show(message, "Error")
	end
end)

task.defer(ensureButton)

local playerGui = player:WaitForChild("PlayerGui")
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "GUI" then
		task.defer(ensureButton)
	end
end)

player.CharacterAdded:Connect(function()
	task.defer(ensureButton)
end)
