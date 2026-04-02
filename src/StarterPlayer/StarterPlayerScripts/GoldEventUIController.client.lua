--!strict
-- LOCATION: StarterPlayerScripts/GoldEventUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BrainrotEventConfiguration = require(ReplicatedStorage.Modules.BrainrotEventConfiguration)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("GUI")
local frames = mainGui:WaitForChild("Frames")
local notifications = frames:WaitForChild("Notifications")

local workspaceAttributes = BrainrotEventConfiguration.WorkspaceAttributes

local banner: Frame? = nil
local bannerScale: UIScale? = nil
local bannerCard: Frame? = nil
local bannerAccent: Frame? = nil
local bannerMessage: TextLabel? = nil
local bannerGlow: Frame? = nil
local bannerGradient: UIGradient? = nil
local showing = false
local animationConnection: RBXScriptConnection? = nil

local SHOW_TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function disconnectAnimation()
	if animationConnection then
		animationConnection:Disconnect()
		animationConnection = nil
	end
end

local function getBannerPalette(): (Color3, Color3, Color3, Color3)
	local rarity = Workspace:GetAttribute(workspaceAttributes.Rarity)
	local rarityConfig = type(rarity) == "string" and (RarityConfigurations[rarity] :: any) or nil
	if rarityConfig then
		local accent = rarityConfig.StrokeColor or Color3.fromRGB(255, 176, 66)
		local bright = rarityConfig.TextColor or Color3.fromRGB(255, 245, 214)
		local gradientColor = rarityConfig.GradientColor
		if typeof(gradientColor) == "ColorSequence" then
			local first = gradientColor.Keypoints[1] and gradientColor.Keypoints[1].Value or bright
			local last = gradientColor.Keypoints[#gradientColor.Keypoints] and gradientColor.Keypoints[#gradientColor.Keypoints].Value or accent
			return accent, bright, first, last
		end

		return accent, bright, accent, bright
	end

	return Color3.fromRGB(255, 176, 66), Color3.fromRGB(255, 245, 214), Color3.fromRGB(255, 140, 40), Color3.fromRGB(255, 219, 126)
end

local function ensureBanner(): Frame
	if banner and banner.Parent then
		return banner
	end

	local root = Instance.new("Frame")
	root.Name = "EventBrainrotBanner"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 24)
	root.Size = UDim2.fromOffset(620, 92)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 30
	root.Parent = notifications

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(340, 76)
	sizeConstraint.MaxSize = Vector2.new(660, 104)
	sizeConstraint.Parent = root

	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = root

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.52)
	glow.Size = UDim2.new(1, 34, 1, 20)
	glow.BackgroundColor3 = Color3.fromRGB(255, 170, 70)
	glow.BackgroundTransparency = 0.82
	glow.BorderSizePixel = 0
	glow.ZIndex = 29
	glow.Parent = root

	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 28)
	glowCorner.Parent = glow

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(17, 16, 22)
	card.BackgroundTransparency = 0.08
	card.BorderSizePixel = 0
	card.ZIndex = 30
	card.Parent = root

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 24)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(255, 170, 70)
	cardStroke.Thickness = 2
	cardStroke.Transparency = 0.08
	cardStroke.Parent = card

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 18
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 149, 44)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 216, 122)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 149, 44)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.12),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	gradient.Parent = card

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.AnchorPoint = Vector2.new(0.5, 0)
	accent.Position = UDim2.new(0.5, 0, 0, 10)
	accent.Size = UDim2.new(1, -48, 0, 4)
	accent.BackgroundColor3 = Color3.fromRGB(255, 176, 66)
	accent.BorderSizePixel = 0
	accent.ZIndex = 31
	accent.Parent = card

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.58)
	content.Size = UDim2.new(1, -42, 1, -24)
	content.BackgroundTransparency = 1
	content.ZIndex = 31
	content.Parent = card

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.BackgroundTransparency = 1
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.Position = UDim2.fromScale(0.5, 0.5)
	message.Size = UDim2.new(1, 0, 1, 0)
	message.Font = Enum.Font.GothamBlack
	message.Text = ""
	message.TextColor3 = Color3.fromRGB(255, 245, 214)
	message.TextScaled = true
	message.TextWrapped = true
	message.TextStrokeTransparency = 0.82
	message.TextXAlignment = Enum.TextXAlignment.Center
	message.TextYAlignment = Enum.TextYAlignment.Center
	message.ZIndex = 32
	message.Parent = content

	local messageSizeConstraint = Instance.new("UITextSizeConstraint")
	messageSizeConstraint.MinTextSize = 18
	messageSizeConstraint.MaxTextSize = 30
	messageSizeConstraint.Parent = message

	banner = root
	bannerScale = scale
	bannerCard = card
	bannerAccent = accent
	bannerMessage = message
	bannerGlow = glow
	bannerGradient = gradient

	return root
end

local function applyBannerStyle()
	local root = ensureBanner()
	local card = bannerCard
	local accent = bannerAccent
	local message = bannerMessage
	local glow = bannerGlow
	local gradient = bannerGradient

	if not root or not card or not accent or not message or not glow or not gradient then
		return
	end

	local accentColor, brightText, gradientStart, gradientEnd = getBannerPalette()
	accent.BackgroundColor3 = accentColor
	message.TextColor3 = brightText
	glow.BackgroundColor3 = accentColor

	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = accentColor
	end

	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, gradientStart),
		ColorSequenceKeypoint.new(0.55, brightText),
		ColorSequenceKeypoint.new(1, gradientEnd),
	})
end

local function startAmbientAnimation()
	disconnectAnimation()

	local root = ensureBanner()
	local scale = bannerScale
	local glow = bannerGlow
	local gradient = bannerGradient
	if not root or not scale or not glow or not gradient then
		return
	end

	animationConnection = RunService.RenderStepped:Connect(function()
		if not showing or not root.Visible then
			return
		end

		local t = Workspace:GetServerTimeNow()
		root.Position = UDim2.new(0.5, 0, 0, 24 + math.sin(t * 1.7) * 2)
		glow.BackgroundTransparency = 0.84 + ((math.sin(t * 2.1) + 1) * 0.04)
		gradient.Rotation = 18 + math.sin(t * 0.6) * 6
	end)
end

local function setBannerVisible(visible: boolean)
	local root = ensureBanner()
	local scale = bannerScale
	local card = bannerCard
	local message = bannerMessage
	local glow = bannerGlow

	if not scale or not card or not message or not glow then
		return
	end

	if visible then
		root.Visible = true
		if not showing then
			showing = true
			root.Position = UDim2.new(0.5, 0, 0, 12)
			scale.Scale = 0.88
			card.BackgroundTransparency = 0.22
			glow.BackgroundTransparency = 0.92
			message.TextTransparency = 1

			TweenService:Create(scale, SHOW_TWEEN_INFO, {Scale = 1}):Play()
			TweenService:Create(card, FADE_TWEEN_INFO, {BackgroundTransparency = 0.08}):Play()
			TweenService:Create(glow, FADE_TWEEN_INFO, {BackgroundTransparency = 0.84}):Play()
			TweenService:Create(message, FADE_TWEEN_INFO, {TextTransparency = 0}):Play()
		end

		startAmbientAnimation()
	else
		showing = false
		disconnectAnimation()
		root.Visible = false
	end
end

local function updateBanner()
	local isActive = Workspace:GetAttribute(workspaceAttributes.Active) == true
	local message = Workspace:GetAttribute(workspaceAttributes.Message)
	local root = ensureBanner()

	if isActive and type(message) == "string" and message ~= "" then
		applyBannerStyle()

		if bannerMessage then
			bannerMessage.Text = message
		end

		root.Position = UDim2.new(0.5, 0, 0, 24)
		setBannerVisible(true)
	else
		setBannerVisible(false)
	end
end

for _, attributeName in pairs(workspaceAttributes) do
	Workspace:GetAttributeChangedSignal(attributeName):Connect(updateBanner)
end

updateBanner()
