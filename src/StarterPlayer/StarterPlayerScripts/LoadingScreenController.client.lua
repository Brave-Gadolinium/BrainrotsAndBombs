--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FRAME_INFO = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local ICON_SLIDE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DOT_FINISH_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
local DOT_LOAD_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local SLIDER_INFO_IN = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SLIDER_INFO_OUT = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ROTATION_INFO = TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1)

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

local function getSortedDots(dotHolder: Instance): {Frame}
	local dots: {Frame} = {}

	for _, child in ipairs(dotHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(dots, child)
		end
	end

	table.sort(dots, function(a, b)
		local aOrder = tonumber(a.Name) or a.LayoutOrder
		local bOrder = tonumber(b.Name) or b.LayoutOrder

		if aOrder == bOrder then
			return a.Name < b.Name
		end

		return aOrder < bOrder
	end)

	return dots
end

local function playLoadingScreen()
	local loadingScreen = getLoadingScreen()
	local background = loadingScreen:WaitForChild("Background") :: GuiObject
	local slider = loadingScreen:WaitForChild("Slider") :: GuiObject
	local canvasGroup = loadingScreen:WaitForChild("Frame") :: CanvasGroup
	local dotHolder = canvasGroup:WaitForChild("Dots")
	local frontFrame = background:WaitForChild("Front")
	local gradient = frontFrame:WaitForChild("UIGradient") :: UIGradient
	local dots = getSortedDots(dotHolder)
	local loopTweens: {[number]: Tween} = {}

	canvasGroup.GroupTransparency = 1

	local rotationTween = playTween(gradient, ROTATION_INFO, {
		Rotation = 360,
	})

	task.wait(0.65)

	local frameTween = playTween(canvasGroup, FRAME_INFO, {
		GroupTransparency = 0,
	})
	frameTween.Completed:Wait()
	frameTween:Destroy()

	for index, dotFrame in ipairs(dots) do
		local icon = dotFrame:WaitForChild("Icon") :: ImageLabel

		loopTweens[index] = playTween(icon, DOT_LOAD_INFO, {
			Position = UDim2.fromScale(0.5, 0),
		})

		task.wait(0.1)
	end

	for index, dotFrame in ipairs(dots) do
		local icon = dotFrame:WaitForChild("Icon") :: ImageLabel
		local loopTween = loopTweens[index]

		task.wait(0.2)

		icon.Position = UDim2.fromScale(0.5, -0.5)
		icon.ImageColor3 = Color3.new(1, 1, 1)

		if loopTween then
			loopTween:Cancel()
			loopTween:Destroy()
			loopTweens[index] = nil
		end

		playTween(icon, ICON_SLIDE_INFO, {
			Position = UDim2.fromScale(0.5, 0.5),
		})
	end

	task.wait(0.4)

	for _, dotFrame in ipairs(dots) do
		local icon = dotFrame:WaitForChild("Icon") :: ImageLabel

		playTween(icon, DOT_FINISH_INFO, {
			Position = UDim2.fromScale(0.5, 0),
		})

		task.wait(0.1)
	end

	local sliderTweenIn = playTween(slider, SLIDER_INFO_IN, {
		Position = UDim2.fromScale(0.5, 0.5),
	})
	sliderTweenIn.Completed:Wait()
	sliderTweenIn:Destroy()

	background.Visible = false
	canvasGroup.Visible = false

	local sliderTweenOut = playTween(slider, SLIDER_INFO_OUT, {
		Position = UDim2.fromScale(-1.5, 0.5),
	})
	sliderTweenOut.Completed:Wait()
	sliderTweenOut:Destroy()

	rotationTween:Cancel()
	rotationTween:Destroy()

	loadingScreen:Destroy()
end

task.defer(playLoadingScreen)
