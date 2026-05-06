--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GlobalEventConfiguration = require(ReplicatedStorage.Modules.GlobalEventConfiguration)

type PublicState = GlobalEventConfiguration.PublicState
type EventDefinition = GlobalEventConfiguration.EventDefinition

type TransparencyEntry = {
	Instance: Instance,
	Property: string,
	TargetValue: number,
}

type EventFrameUi = {
	Frame: GuiObject,
	Start: GuiObject?,
	Timer: GuiObject,
	End: GuiObject?,
	TimerLabel: TextLabel,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local globalEventRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GlobalTimedEvents")
local getStateRemote = globalEventRemotes:WaitForChild("GetState") :: RemoteFunction
local stateUpdatedRemote = globalEventRemotes:WaitForChild("StateUpdated") :: RemoteEvent

local START_MESSAGE_SECONDS = 2
local END_MESSAGE_SECONDS = 2
local FALLBACK_START_MESSAGE_SECONDS = 2
local NON_BLOCKING_ATTRIBUTE = "IgnoreFrameManagerBlocking"
local EVENT_FRAMES_ROOT_NAME = "Events"
local FADE_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SCALE_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDDEN_OVERLAY_SCALE = 0.94
local VISIBLE_OVERLAY_SCALE = 1

local currentState: PublicState? = nil
local currentDefinition: EventDefinition? = nil
local activeEventUi: EventFrameUi? = nil
local uiSequence = 0

local fallbackBanner: Frame? = nil
local fallbackAccent: Frame? = nil
local fallbackTitleLabel: TextLabel? = nil
local fallbackSubtitleLabel: TextLabel? = nil
local fallbackTimerLabel: TextLabel? = nil
local fallbackStroke: UIStroke? = nil
local fallbackScale: UIScale? = nil
local fallbackStartedAt = 0
local fallbackEndMessageUntil = 0
local fallbackEndDefinition: EventDefinition? = nil
local warnedFallbackShape = false

local originalTransparencyValues: {[Instance]: {[string]: number}} = {}

local function formatTime(seconds: number): string
	return tostring(math.max(0, math.ceil(seconds)))
end

local function getMainGui(): Instance?
	local mainGui = playerGui:FindFirstChild("GUI")
	if not mainGui then
		return nil
	end

	return mainGui
end

local function getHudContainer(): Instance?
	local mainGui = getMainGui()
	if not mainGui then
		return nil
	end

	return mainGui:FindFirstChild("HUD")
end

local function getFramesContainer(): Instance?
	local mainGui = getMainGui()
	if not mainGui then
		return nil
	end

	return mainGui:FindFirstChild("Frames")
end

local function getEventFramesRoot(): Instance?
	local hudContainer = getHudContainer()
	local eventsRoot = hudContainer and hudContainer:FindFirstChild(EVENT_FRAMES_ROOT_NAME)
	if eventsRoot and eventsRoot:IsA("GuiObject") then
		eventsRoot:SetAttribute(NON_BLOCKING_ATTRIBUTE, true)
		return eventsRoot
	end

	local framesContainer = getFramesContainer()
	eventsRoot = framesContainer and framesContainer:FindFirstChild(EVENT_FRAMES_ROOT_NAME)
	if eventsRoot and eventsRoot:IsA("GuiObject") then
		eventsRoot:SetAttribute(NON_BLOCKING_ATTRIBUTE, true)
	end

	return eventsRoot
end

local function setEventFramesRootVisible(isVisible: boolean)
	local eventsRoot = getEventFramesRoot()
	if eventsRoot and eventsRoot:IsA("GuiObject") then
		eventsRoot.Visible = isVisible
	end
end

local function findTimerLabel(timerFrame: GuiObject): TextLabel?
	if timerFrame:IsA("TextLabel") then
		return timerFrame
	end

	local namedTimer = timerFrame:FindFirstChild("Timer", true)
	if namedTimer and namedTimer:IsA("TextLabel") then
		return namedTimer
	end

	return nil
end

local function getDirectGuiChild(parent: Instance, childName: string): GuiObject?
	local child = parent:FindFirstChild(childName)
	if child and child:IsA("GuiObject") then
		return child
	end

	return nil
end

local function resolveEventUi(definition: EventDefinition): EventFrameUi?
	local uiFrameName = definition.UiFrameName or definition.SkyboxName
	if type(uiFrameName) ~= "string" or uiFrameName == "" then
		return nil
	end

	local eventsRoot = getEventFramesRoot()
	if not eventsRoot then
		return nil
	end

	local eventFrame = eventsRoot:FindFirstChild(uiFrameName)
	if not eventFrame or not eventFrame:IsA("GuiObject") then
		return nil
	end

	local timerFrame = getDirectGuiChild(eventFrame, "Timer")
	if not timerFrame then
		return nil
	end

	local timerLabel = findTimerLabel(timerFrame)
	if not timerLabel then
		return nil
	end

	eventFrame:SetAttribute(NON_BLOCKING_ATTRIBUTE, true)

	return {
		Frame = eventFrame,
		Start = getDirectGuiChild(eventFrame, "Start"),
		Timer = timerFrame,
		End = getDirectGuiChild(eventFrame, "End"),
		TimerLabel = timerLabel,
	}
end

local function getTransparencyProperties(instance: Instance): {string}
	local properties = {}

	if instance:IsA("GuiObject") then
		table.insert(properties, "BackgroundTransparency")
	end

	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		table.insert(properties, "TextTransparency")
		table.insert(properties, "TextStrokeTransparency")
	end

	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		table.insert(properties, "ImageTransparency")
	end

	if instance:IsA("ScrollingFrame") then
		table.insert(properties, "ScrollBarImageTransparency")
	end

	if instance:IsA("UIStroke") then
		table.insert(properties, "Transparency")
	end

	return properties
end

local function getOriginalTransparency(instance: Instance, propertyName: string): number?
	local valuesForInstance = originalTransparencyValues[instance]
	if valuesForInstance and valuesForInstance[propertyName] ~= nil then
		return valuesForInstance[propertyName]
	end

	local success, currentValue = pcall(function()
		return (instance :: any)[propertyName]
	end)
	if not success or type(currentValue) ~= "number" then
		return nil
	end

	if not valuesForInstance then
		valuesForInstance = {}
		originalTransparencyValues[instance] = valuesForInstance
	end
	valuesForInstance[propertyName] = currentValue

	return currentValue
end

local function collectTransparencyEntries(root: GuiObject, isVisible: boolean): {TransparencyEntry}
	local entries = {}

	local function collect(instance: Instance)
		for _, propertyName in ipairs(getTransparencyProperties(instance)) do
			local originalValue = getOriginalTransparency(instance, propertyName)
			if originalValue ~= nil then
				table.insert(entries, {
					Instance = instance,
					Property = propertyName,
					TargetValue = if isVisible then originalValue else 1,
				})
			end
		end
	end

	collect(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		collect(descendant)
	end

	return entries
end

local function setTransparency(root: GuiObject, isVisible: boolean)
	for _, entry in ipairs(collectTransparencyEntries(root, isVisible)) do
		pcall(function()
			local target = entry.Instance :: any
			target[entry.Property] = entry.TargetValue
		end)
	end
end

local function tweenTransparency(root: GuiObject, isVisible: boolean)
	for _, entry in ipairs(collectTransparencyEntries(root, isVisible)) do
		local goal = {
			[entry.Property] = entry.TargetValue,
		}
		TweenService:Create(entry.Instance :: any, FADE_TWEEN_INFO, goal):Play()
	end
end

local function getOrCreateOverlayScale(overlay: GuiObject): UIScale
	local existing = overlay:FindFirstChild("GlobalTimedEventScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = "GlobalTimedEventScale"
	scale.Scale = VISIBLE_OVERLAY_SCALE
	scale.Parent = overlay
	return scale
end

local function showOverlay(overlay: GuiObject)
	overlay.Visible = true
	setTransparency(overlay, false)

	local overlayScale = getOrCreateOverlayScale(overlay)
	overlayScale.Scale = HIDDEN_OVERLAY_SCALE

	tweenTransparency(overlay, true)
	TweenService:Create(overlayScale, SCALE_TWEEN_INFO, {
		Scale = VISIBLE_OVERLAY_SCALE,
	}):Play()
end

local function hideOverlay(overlay: GuiObject, token: number, onHidden: (() -> ())?)
	local overlayScale = getOrCreateOverlayScale(overlay)
	tweenTransparency(overlay, false)

	local scaleTween = TweenService:Create(overlayScale, SCALE_TWEEN_INFO, {
		Scale = HIDDEN_OVERLAY_SCALE,
	})
	scaleTween:Play()
	scaleTween.Completed:Once(function()
		if token ~= uiSequence then
			return
		end

		overlay.Visible = false
		if onHidden then
			onHidden()
		end
	end)
end

local function hideOverlayImmediate(overlay: GuiObject?)
	if not overlay then
		return
	end

	setTransparency(overlay, false)
	overlay.Visible = false
	local overlayScale = overlay:FindFirstChild("GlobalTimedEventScale")
	if overlayScale and overlayScale:IsA("UIScale") then
		overlayScale.Scale = HIDDEN_OVERLAY_SCALE
	end
end

local function hideAllEventFrames(exceptFrame: GuiObject?)
	local eventsRoot = getEventFramesRoot()
	if not eventsRoot then
		return
	end

	for _, child in ipairs(eventsRoot:GetChildren()) do
		if child:IsA("GuiObject") and child ~= exceptFrame then
			child.Visible = false
		end
	end

	setEventFramesRootVisible(exceptFrame ~= nil)
end

local function hideEventUiImmediate(ui: EventFrameUi)
	hideOverlayImmediate(ui.Start)
	hideOverlayImmediate(ui.End)
	ui.Timer.Visible = false
	ui.Frame.Visible = false
end

local function updateEventUiTimer()
	if not activeEventUi or not currentState or not currentState.activeEventId or type(currentState.endsAt) ~= "number" then
		return
	end

	setEventFramesRootVisible(true)
	activeEventUi.Frame.Visible = true
	activeEventUi.Timer.Visible = true
	activeEventUi.TimerLabel.Text = formatTime(currentState.endsAt - Workspace:GetServerTimeNow())
end

local function showStartOverlay(ui: EventFrameUi, token: number)
	if not ui.Start then
		return
	end

	showOverlay(ui.Start)
	task.delay(START_MESSAGE_SECONDS, function()
		if token ~= uiSequence or not ui.Start or not ui.Start.Parent then
			return
		end

		hideOverlay(ui.Start, token, nil)
	end)
end

local function showEndOverlay(ui: EventFrameUi, token: number)
	if not ui.End then
		hideEventUiImmediate(ui)
		hideAllEventFrames(nil)
		return
	end

	ui.Frame.Visible = true
	ui.Timer.Visible = false
	showOverlay(ui.End)

	task.delay(END_MESSAGE_SECONDS, function()
		if token ~= uiSequence or not ui.End or not ui.End.Parent then
			return
		end

		hideOverlay(ui.End, token, function()
			if token ~= uiSequence then
				return
			end

			hideEventUiImmediate(ui)
			hideAllEventFrames(nil)
		end)
	end)
end

local function showActiveEventUi(ui: EventFrameUi, state: PublicState)
	uiSequence += 1
	local token = uiSequence

	hideAllEventFrames(ui.Frame)
	hideOverlayImmediate(ui.Start)
	hideOverlayImmediate(ui.End)

	ui.Frame.Visible = true
	ui.Timer.Visible = true
	activeEventUi = ui
	updateEventUiTimer()

	if state.transition == "Started" then
		showStartOverlay(ui, token)
	end
end

local function showEndedEventUi(ui: EventFrameUi)
	uiSequence += 1
	local token = uiSequence

	activeEventUi = nil
	currentDefinition = nil
	hideAllEventFrames(ui.Frame)
	hideOverlayImmediate(ui.Start)
	hideOverlayImmediate(ui.End)
	setEventFramesRootVisible(true)
	showEndOverlay(ui, token)
end

local function resolveFallbackBanner(waitSeconds: number?): boolean
	if fallbackBanner and fallbackBanner.Parent then
		return true
	end

	local screenGui: Instance? = playerGui:FindFirstChild("GlobalTimedEventGui")
	local timeoutSeconds = math.max(0, tonumber(waitSeconds) or 0)
	if not screenGui and timeoutSeconds > 0 then
		screenGui = playerGui:WaitForChild("GlobalTimedEventGui", timeoutSeconds)
	end

	if not screenGui or not screenGui:IsA("ScreenGui") then
		return false
	end

	local banner = screenGui:FindFirstChild("Banner")
	local accent = banner and banner:FindFirstChild("Accent", true)
	local titleLabel = banner and banner:FindFirstChild("Title", true)
	local subtitleLabel = banner and banner:FindFirstChild("Subtitle", true)
	local timerLabel = banner and banner:FindFirstChild("Timer", true)
	local stroke = banner and banner:FindFirstChildOfClass("UIStroke")
	local scale = banner and banner:FindFirstChildOfClass("UIScale")

	if banner and banner:IsA("Frame")
		and accent and accent:IsA("Frame")
		and titleLabel and titleLabel:IsA("TextLabel")
		and subtitleLabel and subtitleLabel:IsA("TextLabel")
		and timerLabel and timerLabel:IsA("TextLabel")
		and stroke
	then
		fallbackBanner = banner
		fallbackAccent = accent
		fallbackTitleLabel = titleLabel
		fallbackSubtitleLabel = subtitleLabel
		fallbackTimerLabel = timerLabel
		fallbackStroke = stroke
		fallbackScale = if scale and scale:IsA("UIScale") then scale else nil
		return true
	end

	if not warnedFallbackShape then
		warn("[GlobalTimedEventController] GlobalTimedEventGui is missing Banner/Accent/Title/Subtitle/Timer/UIStroke.")
		warnedFallbackShape = true
	end

	return false
end

local function setFallbackBannerColor(color: Color3)
	if not resolveFallbackBanner(nil) then
		return
	end

	local stroke = fallbackStroke :: UIStroke
	local accent = fallbackAccent :: Frame
	local timerLabel = fallbackTimerLabel :: TextLabel

	stroke.Color = color
	accent.BackgroundColor3 = color
	timerLabel.TextColor3 = color
end

local function showFallbackBanner()
	if not resolveFallbackBanner(nil) then
		return
	end

	local banner = fallbackBanner :: Frame
	if banner.Visible then
		return
	end

	banner.Visible = true
	banner.BackgroundTransparency = 1
	if fallbackScale then
		local scale = fallbackScale :: UIScale
		scale.Scale = 0.94
	end
	TweenService:Create(banner, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.12,
	}):Play()
	if fallbackScale then
		local scale = fallbackScale :: UIScale
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
end

local function hideFallbackBanner(immediate: boolean?)
	if not resolveFallbackBanner(nil) then
		return
	end

	local banner = fallbackBanner :: Frame
	if not banner.Visible then
		return
	end

	if immediate == true then
		banner.Visible = false
		return
	end

	local fade = TweenService:Create(banner, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	fade:Play()
	fade.Completed:Once(function()
		if currentState == nil and os.clock() >= fallbackEndMessageUntil then
			banner.Visible = false
		end
	end)
end

local function applyFallbackActiveState(state: PublicState, definition: EventDefinition)
	if not resolveFallbackBanner(5) then
		return
	end

	fallbackEndMessageUntil = 0
	fallbackEndDefinition = nil
	fallbackStartedAt = if state.transition == "Started" then os.clock() else 0
	setFallbackBannerColor(definition.Color)

	local titleLabel = fallbackTitleLabel :: TextLabel
	local subtitleLabel = fallbackSubtitleLabel :: TextLabel
	local timerLabel = fallbackTimerLabel :: TextLabel

	titleLabel.Text = if state.transition == "Started" then definition.StartText else definition.DisplayName
	subtitleLabel.Text = definition.DisplayName
	timerLabel.Visible = true
	showFallbackBanner()
end

local function applyFallbackEndedState(definition: EventDefinition)
	if not resolveFallbackBanner(5) then
		return
	end

	fallbackEndDefinition = definition
	fallbackEndMessageUntil = os.clock() + END_MESSAGE_SECONDS
	setFallbackBannerColor(definition.Color)

	local titleLabel = fallbackTitleLabel :: TextLabel
	local subtitleLabel = fallbackSubtitleLabel :: TextLabel
	local timerLabel = fallbackTimerLabel :: TextLabel

	titleLabel.Text = definition.EndText
	subtitleLabel.Text = definition.DisplayName
	timerLabel.Visible = false
	showFallbackBanner()
end

local function applyState(state: PublicState)
	currentState = state

	if state.activeEventId then
		local definition = GlobalEventConfiguration.GetEventDefinition(state.activeEventId)
		if not definition then
			return
		end

		currentDefinition = definition
		fallbackEndMessageUntil = 0
		fallbackEndDefinition = nil

		local eventUi = resolveEventUi(definition)
		if eventUi then
			hideFallbackBanner(true)
			showActiveEventUi(eventUi, state)
			return
		end

		uiSequence += 1
		activeEventUi = nil
		hideAllEventFrames(nil)
		applyFallbackActiveState(state, definition)
		return
	end

	currentDefinition = nil

	if state.transition == "Ended" and state.endedEventId then
		local definition = GlobalEventConfiguration.GetEventDefinition(state.endedEventId)
		if definition then
			local eventUi = resolveEventUi(definition)
			if eventUi then
				currentState = nil
				hideFallbackBanner(true)
				showEndedEventUi(eventUi)
				return
			end

			uiSequence += 1
			activeEventUi = nil
			hideAllEventFrames(nil)
			applyFallbackEndedState(definition)
			return
		end
	end

	currentState = nil
	activeEventUi = nil
	uiSequence += 1
	hideAllEventFrames(nil)
	hideFallbackBanner(false)
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
		if activeEventUi then
			updateEventUiTimer()
		elseif currentState and currentState.activeEventId and currentDefinition and type(currentState.endsAt) == "number" then
			local remaining = currentState.endsAt - Workspace:GetServerTimeNow()
			if fallbackStartedAt > 0 and os.clock() - fallbackStartedAt >= FALLBACK_START_MESSAGE_SECONDS then
				if fallbackTitleLabel then
					local titleLabel = fallbackTitleLabel :: TextLabel
					titleLabel.Text = currentDefinition.DisplayName
				end
				fallbackStartedAt = 0
			end

			if fallbackTimerLabel then
				local timerLabel = fallbackTimerLabel :: TextLabel
				timerLabel.Text = formatTime(remaining)
			end
			if remaining <= 0 then
				currentState = nil
			end
		elseif fallbackEndDefinition and os.clock() >= fallbackEndMessageUntil then
			fallbackEndDefinition = nil
			hideFallbackBanner(false)
		end

		task.wait(0.1)
	end
end)
