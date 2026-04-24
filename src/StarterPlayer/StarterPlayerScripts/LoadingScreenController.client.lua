--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

	loadingScreen:Destroy()
	log("Lifecycle complete")
end

log("Script initialized")
task.defer(playLoadingScreen)
