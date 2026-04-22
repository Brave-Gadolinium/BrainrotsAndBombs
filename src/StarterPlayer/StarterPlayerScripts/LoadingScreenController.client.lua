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

local function playTween(target: Instance, tweenInfo: TweenInfo, goal: {[string]: any}): Tween
	local tween = TweenService:Create(target, tweenInfo, goal)
	tween:Play()
	return tween
end

local function getLoadingScreen(): ScreenGui
	local existing = playerGui:FindFirstChild("LoadingScreen")
	if existing and existing:IsA("ScreenGui") then
		existing.Enabled = true
		existing.DisplayOrder = math.max(existing.DisplayOrder, 10_000)
		return existing
	end

	local template = ReplicatedStorage:WaitForChild("LoadingScreen") :: ScreenGui
	local loadingScreen = template:Clone() :: ScreenGui
	loadingScreen.DisplayOrder = 10_000
	loadingScreen.Parent = playerGui
	loadingScreen.Enabled = true

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

	local gui = playerGui:FindFirstChild("GUI")
	if not gui or not gui:IsA("ScreenGui") then
		return false
	end

	return isCharacterReady()
end

local function playLoadingScreen()
	local startedAt = os.clock()
	local fadeOutAt = math.max(0, MAX_VISIBLE_TIME - FADE_OUT_DURATION)
	local loadingScreen = getLoadingScreen()
	local background = loadingScreen:WaitForChild("Background") :: GuiObject
	local canvasGroup = loadingScreen:WaitForChild("Frame") :: CanvasGroup
	local slider = findSlider(loadingScreen)
	local sliderFill = findSliderFill(slider)

	canvasGroup.GroupTransparency = 1
	background.Visible = true
	canvasGroup.Visible = true
	if slider then
		slider.Visible = true
	end

	setSliderProgress(sliderFill, getStartupProgress())

	local fadeInTween = playTween(canvasGroup, FADE_IN_INFO, {
		GroupTransparency = 0,
	})
	fadeInTween.Completed:Wait()
	fadeInTween:Destroy()

	while true do
		local elapsed = os.clock() - startedAt
		local clientReady = isClientReady()
		setSliderProgress(sliderFill, getStartupProgress())

		if clientReady or elapsed >= fadeOutAt then
			break
		end

		task.wait(READINESS_POLL_INTERVAL)
	end

	setSliderProgress(sliderFill, 1)

	local fadeOutTween = playTween(canvasGroup, FADE_OUT_INFO, {
		GroupTransparency = 1,
	})
	fadeOutTween.Completed:Wait()
	fadeOutTween:Destroy()

	loadingScreen:Destroy()
end

task.defer(playLoadingScreen)
