--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BombToolClient = {}

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bomb"):WaitForChild("PlaceBomb") :: RemoteEvent
local timerTemplate = ReplicatedStorage:WaitForChild("Templates"):WaitForChild("TimerGUI") :: BillboardGui

type ToolState = {
	RunId: number,
	ActiveTween: Tween?,
	RequestId: number,
	WaitingForServer: boolean,
}

local toolStates: {[Tool]: ToolState} = {}

local function getToolState(tool: Tool): ToolState
	local existingState = toolStates[tool]
	if existingState then
		return existingState
	end

	local newState = {
		RunId = 0,
		ActiveTween = nil,
		RequestId = 0,
		WaitingForServer = false,
	}
	toolStates[tool] = newState
	return newState
end

local function ensureTimerGui(tool: Tool): BillboardGui?
	local handle = tool:FindFirstChild("Handle") or tool:WaitForChild("Handle", 2)
	if not handle or not handle:IsA("BasePart") then
		return nil
	end

	local existing = handle:FindFirstChild("TimerGUI")
	if existing and existing:IsA("BillboardGui") then
		return existing
	end

	local timerGui = timerTemplate:Clone()
	timerGui.Enabled = false
	timerGui.Parent = handle
	return timerGui
end

local function getTimerWidgets(timerGui: BillboardGui): (Frame?, TextLabel?)
	local bar = timerGui:FindFirstChild("Bar")
	if not bar then
		return nil, nil
	end

	local progress = bar:FindFirstChild("Progress")
	local textLabel = bar:FindFirstChild("Text")
	if progress and progress:IsA("Frame") and textLabel and textLabel:IsA("TextLabel") then
		return progress, textLabel
	end

	return nil, nil
end

local function clearCooldownVisual(tool: Tool)
	local state = getToolState(tool)
	state.RunId += 1
	state.WaitingForServer = false

	if state.ActiveTween then
		state.ActiveTween:Cancel()
		state.ActiveTween = nil
	end

	local timerGui = ensureTimerGui(tool)
	if not timerGui then
		return
	end

	local progress, textLabel = getTimerWidgets(timerGui)
	if progress then
		progress.Size = UDim2.fromScale(1, 1)
	end
	if textLabel then
		textLabel.Text = "0.0s"
	end

	timerGui.Enabled = false
end

local function playCooldownVisual(tool: Tool)
	local cooldownEndsAt = tool:GetAttribute("CooldownEndsAt")
	if type(cooldownEndsAt) ~= "number" then
		clearCooldownVisual(tool)
		return
	end

	local remaining = math.max(0, cooldownEndsAt - Workspace:GetServerTimeNow())
	if remaining <= 0 then
		clearCooldownVisual(tool)
		return
	end

	local duration = tool:GetAttribute("CooldownDuration")
	if type(duration) ~= "number" or duration <= 0 then
		duration = remaining
	end

	local timerGui = ensureTimerGui(tool)
	if not timerGui then
		return
	end

	local progress, textLabel = getTimerWidgets(timerGui)
	if not progress or not textLabel then
		return
	end

	local state = getToolState(tool)
	state.RunId += 1
	local runId = state.RunId

	if state.ActiveTween then
		state.ActiveTween:Cancel()
		state.ActiveTween = nil
	end

	timerGui.Enabled = true
	progress.Size = UDim2.fromScale(math.clamp(remaining / duration, 0, 1), 1)
	textLabel.Text = string.format("%.1fs", remaining)

	local tween = TweenService:Create(
		progress,
		TweenInfo.new(remaining, Enum.EasingStyle.Linear),
		{Size = UDim2.fromScale(0, 1)}
	)
	state.ActiveTween = tween
	tween:Play()

	task.spawn(function()
		while tool.Parent and runId == state.RunId do
			local timeLeft = cooldownEndsAt - Workspace:GetServerTimeNow()
			if timeLeft <= 0 then
				break
			end

			textLabel.Text = string.format("%.1fs", timeLeft)
			task.wait(0.03)
		end

		if runId ~= state.RunId then
			return
		end

		if state.ActiveTween == tween then
			state.ActiveTween = nil
		end

		textLabel.Text = "0.0s"
		timerGui.Enabled = false
	end)
end

function BombToolClient.Bind(tool: Tool)
	ensureTimerGui(tool)

	tool.Activated:Connect(function()
		if tool.Parent ~= player.Character then
			return
		end

		local state = getToolState(tool)
		if state.WaitingForServer then
			return
		end

		local cooldownEndsAt = tool:GetAttribute("CooldownEndsAt")
		if type(cooldownEndsAt) == "number" and cooldownEndsAt > Workspace:GetServerTimeNow() then
			return
		end

		state.RequestId += 1
		local requestId = state.RequestId
		state.WaitingForServer = true

		task.delay(0.35, function()
			local currentState = toolStates[tool]
			if not currentState then
				return
			end

			if currentState.RequestId == requestId then
				currentState.WaitingForServer = false
			end
		end)

		local camera = Workspace.CurrentCamera
		local cameraLookVector = if camera then camera.CFrame.LookVector else nil
		remote:FireServer(cameraLookVector)
	end)

	tool:GetAttributeChangedSignal("CooldownEndsAt"):Connect(function()
		local state = getToolState(tool)
		state.WaitingForServer = false
		playCooldownVisual(tool)
	end)

	tool.AncestryChanged:Connect(function()
		if not tool.Parent then
			clearCooldownVisual(tool)
			toolStates[tool] = nil
		end
	end)

	playCooldownVisual(tool)
end

return BombToolClient
