--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GlobalEventConfiguration = require(ReplicatedStorage.Modules.GlobalEventConfiguration)

type PublicState = GlobalEventConfiguration.PublicState

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local globalEventRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GlobalTimedEvents")
local getStateRemote = globalEventRemotes:WaitForChild("GetState") :: RemoteFunction
local stateUpdatedRemote = globalEventRemotes:WaitForChild("StateUpdated") :: RemoteEvent

local START_MESSAGE_SECONDS = 2
local END_MESSAGE_SECONDS = 2

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GlobalTimedEventGui"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 950
screenGui.Parent = playerGui

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.28)
banner.Size = UDim2.fromScale(0.42, 0.105)
banner.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
banner.BackgroundTransparency = 0.12
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = screenGui

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(260, 78)
sizeConstraint.MaxSize = Vector2.new(520, 108)
sizeConstraint.Parent = banner

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = banner

local stroke = Instance.new("UIStroke")
stroke.Thickness = 3
stroke.Transparency = 0.05
stroke.Parent = banner

local scale = Instance.new("UIScale")
scale.Scale = 0.94
scale.Parent = banner

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.BackgroundColor3 = Color3.new(1, 1, 1)
accent.BorderSizePixel = 0
accent.Size = UDim2.new(0, 7, 1, -16)
accent.Position = UDim2.new(0, 10, 0, 8)
accent.Parent = banner

local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(0, 4)
accentCorner.Parent = accent

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.Text = ""
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextYAlignment = Enum.TextYAlignment.Center
titleLabel.Size = UDim2.new(1, -132, 0.52, 0)
titleLabel.Position = UDim2.new(0, 30, 0.08, 0)
titleLabel.Parent = banner

local titleTextConstraint = Instance.new("UITextSizeConstraint")
titleTextConstraint.MinTextSize = 18
titleTextConstraint.MaxTextSize = 34
titleTextConstraint.Parent = titleLabel

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Font = Enum.Font.GothamBold
subtitleLabel.Text = ""
subtitleLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
subtitleLabel.TextScaled = true
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.TextYAlignment = Enum.TextYAlignment.Center
subtitleLabel.Size = UDim2.new(1, -132, 0.3, 0)
subtitleLabel.Position = UDim2.new(0, 31, 0.58, 0)
subtitleLabel.Parent = banner

local subtitleTextConstraint = Instance.new("UITextSizeConstraint")
subtitleTextConstraint.MinTextSize = 12
subtitleTextConstraint.MaxTextSize = 18
subtitleTextConstraint.Parent = subtitleLabel

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.BackgroundTransparency = 1
timerLabel.Font = Enum.Font.GothamBlack
timerLabel.Text = "60"
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.TextScaled = true
timerLabel.TextXAlignment = Enum.TextXAlignment.Center
timerLabel.TextYAlignment = Enum.TextYAlignment.Center
timerLabel.Size = UDim2.new(0, 82, 0.68, 0)
timerLabel.Position = UDim2.new(1, -96, 0.16, 0)
timerLabel.Parent = banner

local timerTextConstraint = Instance.new("UITextSizeConstraint")
timerTextConstraint.MinTextSize = 24
timerTextConstraint.MaxTextSize = 46
timerTextConstraint.Parent = timerLabel

local currentState: PublicState? = nil
local currentDefinition: GlobalEventConfiguration.EventDefinition? = nil
local startedAt = 0
local endMessageUntil = 0
local endDefinition: GlobalEventConfiguration.EventDefinition? = nil

local function setBannerColor(color: Color3)
	stroke.Color = color
	accent.BackgroundColor3 = color
	timerLabel.TextColor3 = color
end

local function formatTime(seconds: number): string
	return tostring(math.max(0, math.ceil(seconds)))
end

local function showBanner()
	if banner.Visible then
		return
	end

	banner.Visible = true
	banner.BackgroundTransparency = 1
	scale.Scale = 0.94
	TweenService:Create(banner, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.12,
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function hideBanner()
	if not banner.Visible then
		return
	end

	local fade = TweenService:Create(banner, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	fade:Play()
	fade.Completed:Once(function()
		if currentState == nil and os.clock() >= endMessageUntil then
			banner.Visible = false
		end
	end)
end

local function applyState(state: PublicState)
	currentState = state

	if state.activeEventId then
		local definition = GlobalEventConfiguration.GetEventDefinition(state.activeEventId)
		if not definition then
			return
		end

		currentDefinition = definition
		endMessageUntil = 0
		endDefinition = nil
		startedAt = if state.transition == "Started" then os.clock() else 0
		setBannerColor(definition.Color)
		titleLabel.Text = if state.transition == "Started" then definition.StartText else definition.DisplayName
		subtitleLabel.Text = definition.DisplayName
		timerLabel.Visible = true
		showBanner()
		return
	end

	currentDefinition = nil

	if state.transition == "Ended" and state.endedEventId then
		local definition = GlobalEventConfiguration.GetEventDefinition(state.endedEventId)
		if definition then
			endDefinition = definition
			endMessageUntil = os.clock() + END_MESSAGE_SECONDS
			setBannerColor(definition.Color)
			titleLabel.Text = definition.EndText
			subtitleLabel.Text = definition.DisplayName
			timerLabel.Visible = false
			showBanner()
			return
		end
	end

	currentState = nil
	hideBanner()
end

local function bootstrapState()
	local success, response = pcall(function()
		return getStateRemote:InvokeServer()
	end)

	if success and type(response) == "table" and response.Success == true and type(response.State) == "table" then
		applyState(response.State :: PublicState)
	end
end

bootstrapState()

stateUpdatedRemote.OnClientEvent:Connect(function(state)
	if type(state) == "table" then
		applyState(state :: PublicState)
	end
end)

task.spawn(function()
	while true do
		if currentState and currentState.activeEventId and currentDefinition and type(currentState.endsAt) == "number" then
			local remaining = currentState.endsAt - Workspace:GetServerTimeNow()
			if startedAt > 0 and os.clock() - startedAt >= START_MESSAGE_SECONDS then
				titleLabel.Text = currentDefinition.DisplayName
				startedAt = 0
			end

			timerLabel.Text = formatTime(remaining)
			if remaining <= 0 then
				currentState = nil
			end
		elseif endDefinition and os.clock() >= endMessageUntil then
			endDefinition = nil
			hideBanner()
		end

		task.wait(0.1)
	end
end)
