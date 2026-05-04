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

local screenGui = playerGui:WaitForChild("GlobalTimedEventGui", 20)
if not screenGui or not screenGui:IsA("ScreenGui") then
	warn("[GlobalTimedEventController] PlayerGui.GlobalTimedEventGui was not found.")
	return
end

local banner = screenGui:WaitForChild("Banner", 10)
local accent = banner and banner:FindFirstChild("Accent", true)
local titleLabel = banner and banner:FindFirstChild("Title", true)
local subtitleLabel = banner and banner:FindFirstChild("Subtitle", true)
local timerLabel = banner and banner:FindFirstChild("Timer", true)
local stroke = banner and banner:FindFirstChildOfClass("UIStroke")
local scale = banner and banner:FindFirstChildOfClass("UIScale")

if not banner or not banner:IsA("Frame")
	or not accent or not accent:IsA("Frame")
	or not titleLabel or not titleLabel:IsA("TextLabel")
	or not subtitleLabel or not subtitleLabel:IsA("TextLabel")
	or not timerLabel or not timerLabel:IsA("TextLabel")
	or not stroke
then
	warn("[GlobalTimedEventController] GlobalTimedEventGui is missing Banner/Accent/Title/Subtitle/Timer/UIStroke.")
	return
end

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
	if scale then
		scale.Scale = 0.94
	end
	TweenService:Create(banner, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.12,
	}):Play()
	if scale then
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
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
