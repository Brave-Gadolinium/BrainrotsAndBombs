--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FADE_OUT_DURATION = 0.22
local FADE_IN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_INFO = TweenInfo.new(FADE_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local MAX_VISIBLE_TIME = 5
local READINESS_POLL_INTERVAL = 0.05
local LOG_PREFIX = "[LoadingScreenController]"
local ROTATE_TAG = "RotateGui"
local SIZE_TAG = "SizeGui"
local LOADING_ROTATE_ATTRIBUTE = "LoadingRotate"
local LOADING_PULSE_ATTRIBUTE = "LoadingPulse"
local LOADING_DOTS_ATTRIBUTE = "LoadingDots"
local LOADING_ANIMATION_SCALE_NAME = "LoadingAnimationScale"
local LOADING_ROTATION_DEGREES_PER_SECOND = 180
local LOADING_PULSE_FREQUENCY = 2.4
local LOADING_PULSE_AMPLITUDE = 0.045
local LOADING_DOTS_INTERVAL = 0.35
local ROTATING_NAME_TOKENS = { "spinner", "loadingicon", "loadingimage", "loader", "rotator", "circle", "ring", "spin", "animation" }
local PULSE_NAME_TOKENS = { "loadinglogo", "logo", "loadingicon", "loadingimage", "icon" }
local DOTS_TEXT_NAME_TOKENS = { "loadingtext", "loadinglabel", "statuslabel", "progresslabel" }

local function log(message: string, ...: any)
	print(LOG_PREFIX, message, ...)
end

local function playTween(target: Instance, tweenInfo: TweenInfo, goal: {[string]: any}): Tween
	log("Playing tween", target:GetFullName(), goal)
	local tween = TweenService:Create(target, tweenInfo, goal)
	tween:Play()
	return tween
end

local function getLoadingScreen(): ScreenGui
	log("Resolving loading screen GUI")
	local existing = playerGui:FindFirstChild("LoadingScreen")
	if existing and existing:IsA("ScreenGui") then
		log("Found existing LoadingScreen in PlayerGui")
		existing.Enabled = true
		existing.DisplayOrder = math.max(existing.DisplayOrder, 10_000)
		return existing
	end

	log("LoadingScreen not found in PlayerGui, waiting for ReplicatedStorage template")
	local template = ReplicatedStorage:WaitForChild("LoadingScreen") :: ScreenGui
	log("ReplicatedStorage template resolved", template:GetFullName(), "Class:", template.ClassName)
	local loadingScreen = template:Clone() :: ScreenGui
	loadingScreen.DisplayOrder = 10_000
	loadingScreen.Parent = playerGui
	loadingScreen.Enabled = true
	log("Cloned LoadingScreen into PlayerGui", loadingScreen:GetFullName())

	return loadingScreen
end

local function isCharacterReady(): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid ~= nil and root ~= nil
end

local function getStartupProgress(): number
	return math.clamp(tonumber(Workspace:GetAttribute("MineStartupProgress")) or 0, 0, 1)
end

local function findSlider(root: Instance): GuiObject?
	local slider = root:FindFirstChild("Slider", true)
	if slider and slider:IsA("GuiObject") then
		return slider
	end

	return nil
end

local function findSliderFill(slider: GuiObject?): GuiObject?
	if not slider then
		return nil
	end

	for _, candidateName in ipairs({ "Fill", "Progress", "Bar" }) do
		local candidate = slider:FindFirstChild(candidateName, true)
		if candidate and candidate:IsA("GuiObject") then
			return candidate
		end
	end

	for _, child in ipairs(slider:GetChildren()) do
		if child:IsA("GuiObject") then
			return child
		end
	end

	return nil
end

local function setSliderProgress(fill: GuiObject?, progress: number)
	if not fill then
		return
	end

	local currentSize = fill.Size
	fill.Size = UDim2.new(progress, 0, currentSize.Y.Scale, currentSize.Y.Offset)
end

local function hasAttributeFlag(instance: Instance, attributeName: string): boolean
	return instance:GetAttribute(attributeName) == true
end

local function hasNameToken(instance: Instance, tokens: {string}): boolean
	local normalizedName = string.lower(instance.Name):gsub("%W", "")
	for _, token in ipairs(tokens) do
		if string.find(normalizedName, token, 1, true) ~= nil then
			return true
		end
	end

	return false
end

local function findAnimationTarget(
	root: Instance,
	attributeName: string,
	tagName: string,
	fallbackNameTokens: {string}
): GuiObject?
	for _, descendant in ipairs(root:GetDescendants()) do
		if
			descendant:IsA("GuiObject")
			and (hasAttributeFlag(descendant, attributeName) or CollectionService:HasTag(descendant, tagName))
		then
			return descendant
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") and hasNameToken(descendant, fallbackNameTokens) then
			return descendant
		end
	end

	return nil
end

local function findDotsText(root: Instance): TextLabel?
	for _, descendant in ipairs(root:GetDescendants()) do
		if
			descendant:IsA("TextLabel")
			and (hasAttributeFlag(descendant, LOADING_DOTS_ATTRIBUTE) or hasNameToken(descendant, DOTS_TEXT_NAME_TOKENS))
		then
			return descendant
		end
	end

	return nil
end

local function ensureLoadingScale(guiObject: GuiObject): UIScale
	local existing = guiObject:FindFirstChild(LOADING_ANIMATION_SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = LOADING_ANIMATION_SCALE_NAME
	scale.Scale = 1
	scale.Parent = guiObject
	return scale
end

local function startLoadingAnimations(root: Instance)
	local rotateTarget = findAnimationTarget(root, LOADING_ROTATE_ATTRIBUTE, ROTATE_TAG, ROTATING_NAME_TOKENS)
	local pulseTarget = findAnimationTarget(root, LOADING_PULSE_ATTRIBUTE, SIZE_TAG, PULSE_NAME_TOKENS)
	local dotsText = findDotsText(root)

	if not rotateTarget and not pulseTarget and not dotsText then
		log("No loading animation targets found")
		return function() end
	end

	log(
		"Starting loading animations",
		("rotateTarget=%s pulseTarget=%s dotsText=%s"):format(
			if rotateTarget then rotateTarget:GetFullName() else "nil",
			if pulseTarget then pulseTarget:GetFullName() else "nil",
			if dotsText then dotsText:GetFullName() else "nil"
		)
	)

	local baseRotation = if rotateTarget then rotateTarget.Rotation else 0
	local rotationOffset = 0
	local pulseElapsed = 0
	local pulseScale = if pulseTarget then ensureLoadingScale(pulseTarget) else nil
	local dotsElapsed = 0
	local dotsCount = 0
	local baseDotsText = if dotsText then (dotsText.Text:gsub("%.*$", "")) else ""

	local connection = RunService.RenderStepped:Connect(function(dt: number)
		if rotateTarget and rotateTarget.Parent and rotateTarget:IsDescendantOf(root) then
			rotationOffset = (rotationOffset + LOADING_ROTATION_DEGREES_PER_SECOND * dt) % 360
			rotateTarget.Rotation = baseRotation + rotationOffset
		end

		if pulseScale and pulseScale.Parent then
			pulseElapsed += dt
			pulseScale.Scale = 1 + math.sin(pulseElapsed * LOADING_PULSE_FREQUENCY * math.pi * 2) * LOADING_PULSE_AMPLITUDE
		end

		if dotsText and dotsText.Parent and dotsText:IsDescendantOf(root) then
			dotsElapsed += dt
			if dotsElapsed >= LOADING_DOTS_INTERVAL then
				dotsElapsed = 0
				dotsCount = (dotsCount % 3) + 1
				dotsText.Text = baseDotsText .. string.rep(".", dotsCount)
			end
		end
	end)

	return function()
		connection:Disconnect()

		if rotateTarget and rotateTarget.Parent then
			rotateTarget.Rotation = baseRotation
		end

		if pulseScale and pulseScale.Parent then
			pulseScale.Scale = 1
		end

		if dotsText and dotsText.Parent then
			dotsText.Text = baseDotsText
		end
	end
end

local function isClientReady(): boolean
	local serverSystemsReady = Workspace:GetAttribute("ServerSystemsReady") == true
	local mineStartupPlayable = Workspace:GetAttribute("MineStartupPlayable") == true
	local terrainResetInProgress = Workspace:GetAttribute("TerrainResetInProgress") == true
	local profileReady = player:GetAttribute("ProfileReady") == true
	local hasSessionRoundId = type(Workspace:GetAttribute("SessionRoundId")) == "number"
	local gui = playerGui:FindFirstChild("GUI")
	local hasGui = gui ~= nil and gui:IsA("ScreenGui")
	local characterReady = isCharacterReady()

	if Workspace:GetAttribute("ServerSystemsReady") ~= true then
		return false
	end

	if Workspace:GetAttribute("MineStartupPlayable") ~= true then
		return false
	end

	if Workspace:GetAttribute("TerrainResetInProgress") == true then
		return false
	end

	if player:GetAttribute("ProfileReady") ~= true then
		return false
	end

	if type(Workspace:GetAttribute("SessionRoundId")) ~= "number" then
		return false
	end

	if not gui or not gui:IsA("ScreenGui") then
		return false
	end

	local ready = characterReady
	log(
		"Readiness check",
		("serverSystemsReady=%s mineStartupPlayable=%s terrainResetInProgress=%s profileReady=%s hasSessionRoundId=%s hasGui=%s characterReady=%s final=%s"):format(
			tostring(serverSystemsReady),
			tostring(mineStartupPlayable),
			tostring(terrainResetInProgress),
			tostring(profileReady),
			tostring(hasSessionRoundId),
			tostring(hasGui),
			tostring(characterReady),
			tostring(ready)
		)
	)

	return ready
end

local function playLoadingScreen()
	log("Lifecycle start")
	local startedAt = os.clock()
	local fadeOutAt = math.max(0, MAX_VISIBLE_TIME - FADE_OUT_DURATION)
	local loadingScreen = getLoadingScreen()
	log("Loading screen acquired", loadingScreen:GetFullName())
	local background = loadingScreen:WaitForChild("Background") :: GuiObject
	local canvasGroup = loadingScreen:WaitForChild("Frame") :: CanvasGroup
	local slider = findSlider(loadingScreen)
	local sliderFill = findSliderFill(slider)
	log(
		"Resolved UI references",
		("background=%s frameClass=%s slider=%s sliderFill=%s"):format(
			background:GetFullName(),
			canvasGroup.ClassName,
			if slider then slider:GetFullName() else "nil",
			if sliderFill then sliderFill:GetFullName() else "nil"
		)
	)

	canvasGroup.GroupTransparency = 1
	background.Visible = true
	canvasGroup.Visible = true
	if slider then
		slider.Visible = true
	end
	log("Initialized loading screen visuals")
	local stopLoadingAnimations = startLoadingAnimations(loadingScreen)

	local initialProgress = getStartupProgress()
	log("Initial startup progress", initialProgress)
	setSliderProgress(sliderFill, initialProgress)

	log("Starting fade-in")
	local fadeInTween = playTween(canvasGroup, FADE_IN_INFO, {
		GroupTransparency = 0,
	})
	fadeInTween.Completed:Wait()
	fadeInTween:Destroy()
	log("Fade-in completed")

	local lastLoggedProgress = -1
	local lastReadinessLogAt = 0
	while true do
		local elapsed = os.clock() - startedAt
		local clientReady = isClientReady()
		local progress = getStartupProgress()
		setSliderProgress(sliderFill, progress)

		if math.abs(progress - lastLoggedProgress) >= 0.05 then
			lastLoggedProgress = progress
			log("Progress updated", progress)
		end

		if not clientReady and elapsed - lastReadinessLogAt >= 0.5 then
			lastReadinessLogAt = elapsed
			log("Waiting for readiness", ("elapsed=%.2f progress=%.2f fadeOutAt=%.2f"):format(elapsed, progress, fadeOutAt))
		end

		if clientReady or elapsed >= fadeOutAt then
			log("Exiting wait loop", ("clientReady=%s elapsed=%.2f"):format(tostring(clientReady), elapsed))
			break
		end

		task.wait(READINESS_POLL_INTERVAL)
	end

	setSliderProgress(sliderFill, 1)
	log("Slider forced to 100%")

	log("Starting fade-out")
	local fadeOutTween = playTween(canvasGroup, FADE_OUT_INFO, {
		GroupTransparency = 1,
	})
	fadeOutTween.Completed:Wait()
	fadeOutTween:Destroy()
	log("Fade-out completed, destroying loading screen")

	stopLoadingAnimations()
	loadingScreen:Destroy()
	log("Lifecycle complete")
end

log("Script initialized")
task.defer(playLoadingScreen)
