local TweenService = game:GetService("TweenService")
local GUI = game.Players.LocalPlayer:WaitForChild('PlayerGui')

local POSITION_DEFAULT = UDim2.new(0.499, 0, 0.323, 0)
local POSITION_HOVER = UDim2.new(0.499, 0, 0.37, 0)
local POSITION_PRESSED = UDim2.new(0.499, 0, 0.4, 0)
local TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local wheelHolder
local wheelButton
local isHovering = false
local isPressed = false
local rotationTween

local function getComponents()
	local mainGui = GUI:WaitForChild('GUI', 20):WaitForChild('HUD', 20)
	if not mainGui then
		return nil, nil
	end

	local spinnyWheel = mainGui:FindFirstChild("SpinnyWheel")
	if not spinnyWheel or not spinnyWheel:IsA("Frame") then
		return nil, nil
	end

	local holder = spinnyWheel:FindFirstChild("WheelHolder")
	if not holder or not holder:IsA("Frame") then
		return nil, nil
	end

	local wheel = holder:FindFirstChild("Wheel")
	if not wheel or not wheel:IsA("GuiButton") then
		return nil, nil
	end

	return holder, wheel
end

local function tweenToPosition(position)
	if not wheelHolder then
		return
	end
	TweenService:Create(wheelHolder, TWEEN_INFO, {Position = position}):Play()
end

local function startWheelRotation()
	if not wheelButton then
		return
	end

	if rotationTween then
		rotationTween:Cancel()
	end

	rotationTween = TweenService:Create(
		wheelButton, 
		TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false), 
		{Rotation = 360}
	)

	if rotationTween then
		rotationTween:Play()
	end
end

local function onMouseEnter()
	if isPressed then
		return
	end

	isHovering = true
	if not wheelHolder then
		return
	end

	TweenService:Create(wheelHolder, TWEEN_INFO, {Position = POSITION_HOVER}):Play()
end

local function onMouseLeave()
	isHovering = false

	if isPressed then
		return
	end

	if not wheelHolder then
		return
	end

	TweenService:Create(wheelHolder, TWEEN_INFO, {Position = POSITION_DEFAULT}):Play()
end

local function onMouseButton1Down()
	isPressed = true

	if not wheelHolder then
		return
	end

	TweenService:Create(wheelHolder, TWEEN_INFO, {Position = POSITION_PRESSED}):Play()
end

local function onMouseButton1Up()
	isPressed = false

	if not wheelHolder then
		return
	end

	if isHovering then
		TweenService:Create(wheelHolder, TWEEN_INFO, {Position = POSITION_HOVER}):Play()
	else
		TweenService:Create(wheelHolder, TWEEN_INFO, {Position = POSITION_DEFAULT}):Play()
	end
end

local function onActivated()
	--game.ReplicatedStorage.Remotes.Wheel.OpenSpinnyWheel:FireServer("Galaxy")
	--Signal.Fire("OpenSpinnyWheel", "Galaxy")
end

local function initialize()
	wheelHolder, wheelButton = getComponents()

	if not wheelHolder or not wheelButton then
		warn("[SpinnyWheelTab] Failed to get components")
		return
	end

	--wheelButton.MouseEnter:Connect(onMouseEnter)
	--wheelButton.MouseLeave:Connect(onMouseLeave)
	--wheelButton.MouseButton1Down:Connect(onMouseButton1Down)
	--wheelButton.MouseButton1Up:Connect(onMouseButton1Up)
	--wheelButton.Activated:Connect(onActivated)

	startWheelRotation()
end

initialize()