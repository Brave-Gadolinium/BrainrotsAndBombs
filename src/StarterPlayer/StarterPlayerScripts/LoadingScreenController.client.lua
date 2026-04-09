--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FADE_IN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local MIN_VISIBLE_TIME = 0.35
local HARD_TIMEOUT = 8
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

local function isClientReady(): boolean
	if Workspace:GetAttribute("ServerSystemsReady") ~= true then
		return false
	end

	if Workspace:GetAttribute("TerrainResetInProgress") == true then
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
	local loadingScreen = getLoadingScreen()
	local background = loadingScreen:WaitForChild("Background") :: GuiObject
	local canvasGroup = loadingScreen:WaitForChild("Frame") :: CanvasGroup
	local slider = loadingScreen:FindFirstChild("Slider")

	canvasGroup.GroupTransparency = 1
	background.Visible = true
	canvasGroup.Visible = true
	if slider and slider:IsA("GuiObject") then
		slider.Visible = false
	end

	local fadeInTween = playTween(canvasGroup, FADE_IN_INFO, {
		GroupTransparency = 0,
	})
	fadeInTween.Completed:Wait()
	fadeInTween:Destroy()

	while true do
		local elapsed = os.clock() - startedAt
		if isClientReady() and elapsed >= MIN_VISIBLE_TIME then
			break
		end

		if elapsed >= HARD_TIMEOUT then
			break
		end

		task.wait(READINESS_POLL_INTERVAL)
	end

	local fadeOutTween = playTween(canvasGroup, FADE_OUT_INFO, {
		GroupTransparency = 1,
	})
	fadeOutTween.Completed:Wait()
	fadeOutTween:Destroy()

	loadingScreen:Destroy()
end

task.defer(playLoadingScreen)
