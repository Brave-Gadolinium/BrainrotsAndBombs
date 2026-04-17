--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CandyEventConfiguration = require(ReplicatedStorage.Modules.CandyEventConfiguration)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)

type CandyEventState = CandyEventConfiguration.CandyEventState

local player = Players.LocalPlayer
local candyEventRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CandyEvent")
local getStateRemote = candyEventRemotes:WaitForChild("GetState") :: RemoteFunction
local stateUpdatedRemote = candyEventRemotes:WaitForChild("StateUpdated") :: RemoteEvent
local events = ReplicatedStorage:WaitForChild("Events")

local timerWorkspace = Workspace:WaitForChild("TimerWorkspace", 20)
local timerSurfaceGui = timerWorkspace and timerWorkspace:WaitForChild("SurfaceGui", 20)
local titleLabel = if timerSurfaceGui then timerSurfaceGui:WaitForChild("TitleLabel", 20) else nil
local currentState: CandyEventState? = nil
local adminButtonFrame: Frame? = nil
local startEventButton: TextButton? = nil
local endEventButton: TextButton? = nil
local canUseAdminButtons = false
local isAdminActionPending = false

local function createCorner(target: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = target
end

local function createStroke(target: Instance, color: Color3)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = 0.2
	stroke.Thickness = 1
	stroke.Parent = target
end

local function createAdminButton(parent: Instance, name: string, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(170, 40)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 16
	button.Font = Enum.Font.GothamBold
	button.Parent = parent
	createCorner(button, 10)
	createStroke(button, Color3.fromRGB(255, 255, 255))
	return button
end

local function ensureAdminButtons()
	if not timerSurfaceGui or not timerSurfaceGui:IsA("SurfaceGui") then
		return
	end

	if adminButtonFrame and adminButtonFrame.Parent then
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "CandyEventAdminButtons"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 56)
	frame.Size = UDim2.fromOffset(360, 40)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = timerSurfaceGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = frame

	adminButtonFrame = frame
	startEventButton = createAdminButton(frame, "StartEvent", "START EVENT", Color3.fromRGB(70, 166, 97))
	endEventButton = createAdminButton(frame, "EndEvent", "END EVENT", Color3.fromRGB(194, 78, 78))
end

local function updateAdminButtons()
	if not adminButtonFrame or not startEventButton or not endEventButton then
		return
	end

	adminButtonFrame.Visible = canUseAdminButtons
	if not canUseAdminButtons then
		return
	end

	local isActive = currentState ~= nil and currentState.isActive == true
	local startEnabled = not isActive and not isAdminActionPending
	local endEnabled = isActive and not isAdminActionPending

	startEventButton.Active = startEnabled
	startEventButton.Selectable = startEnabled
	startEventButton.AutoButtonColor = startEnabled
	startEventButton.BackgroundTransparency = startEnabled and 0 or 0.45
	startEventButton.TextTransparency = startEnabled and 0 or 0.35

	endEventButton.Active = endEnabled
	endEventButton.Selectable = endEnabled
	endEventButton.AutoButtonColor = endEnabled
	endEventButton.BackgroundTransparency = endEnabled and 0 or 0.45
	endEventButton.TextTransparency = endEnabled and 0 or 0.35
end

local function executeAdminAction(actionId: string)
	if isAdminActionPending or not canUseAdminButtons then
		return
	end

	local testManagerFolder = events:FindFirstChild("TestManager")
	local executeActionRemote = testManagerFolder and testManagerFolder:FindFirstChild("ExecuteAction")
	if not executeActionRemote or not executeActionRemote:IsA("RemoteFunction") then
		NotificationManager.show("Test actions are unavailable right now.", "Error")
		return
	end

	isAdminActionPending = true
	updateAdminButtons()

	local success, result = pcall(function()
		return executeActionRemote:InvokeServer({
			actionId = actionId,
			targetUserId = player.UserId,
			params = {},
		})
	end)

	isAdminActionPending = false

	if not success or type(result) ~= "table" then
		NotificationManager.show("Failed to execute candy event action.", "Error")
		updateAdminButtons()
		return
	end

	if result.Success == true then
		NotificationManager.show(tostring(result.Message or "Candy event action completed."), "Success")
	else
		NotificationManager.show(tostring(result.Error or result.Message or "Candy event action failed."), "Error")
	end

	updateAdminButtons()
end

local function bootstrapAdminButtons()
	ensureAdminButtons()
	if not startEventButton or not endEventButton then
		return
	end

	startEventButton.Activated:Connect(function()
		executeAdminAction("force_candy_event_active")
	end)

	endEventButton.Activated:Connect(function()
		executeAdminAction("force_candy_event_inactive")
	end)

	task.spawn(function()
		local testManagerFolder = events:WaitForChild("TestManager", 15)
		local getBootstrapRemote = testManagerFolder and testManagerFolder:FindFirstChild("GetBootstrap")
		if not getBootstrapRemote or not getBootstrapRemote:IsA("RemoteFunction") then
			updateAdminButtons()
			return
		end

		local success, result = pcall(function()
			return getBootstrapRemote:InvokeServer(nil)
		end)

		if success and type(result) == "table" and result.Allowed == true and type(result.Actions) == "table" then
			local hasStartAction = false
			local hasEndAction = false
			for _, action in ipairs(result.Actions) do
				if type(action) == "table" then
					if action.id == "force_candy_event_active" then
						hasStartAction = true
					elseif action.id == "force_candy_event_inactive" then
						hasEndAction = true
					end
				end
			end

			canUseAdminButtons = hasStartAction and hasEndAction
		end

		updateAdminButtons()
	end)
end

local function formatCountdown(seconds: number): string
	local totalSeconds = math.max(0, math.floor(seconds))
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local remainingSeconds = totalSeconds % 60

	return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
end

local function updateWorldCountdown()
	if not currentState then
		return
	end

	if not titleLabel or not titleLabel:IsA("TextLabel") then
		return
	end

	local serverNow = Workspace:GetServerTimeNow()
	if currentState.isActive and type(currentState.endsAt) == "number" then
		titleLabel.Text = string.format(
			"%s %s",
			CandyEventConfiguration.Text.ActivePrefix,
			formatCountdown(currentState.endsAt - serverNow)
		)
	else
		titleLabel.Text = string.format(
			"%s %s",
			CandyEventConfiguration.Text.CountdownPrefix,
			formatCountdown(currentState.nextStartAt - serverNow)
		)
	end
end

local function applyState(newState: CandyEventState, allowStartAnnouncement: boolean)
	local previousState = currentState
	currentState = newState
	updateWorldCountdown()
	updateAdminButtons()

	if allowStartAnnouncement and previousState and previousState.isActive ~= true and newState.isActive == true then
		NotificationManager.show(CandyEventConfiguration.Text.EventStarted, "Success")
		NotificationManager.show(CandyEventConfiguration.Text.EventHint, "Success")
	end
end

local function bootstrapState()
	local success, response = pcall(function()
		return getStateRemote:InvokeServer()
	end)

	if success and type(response) == "table" and response.Success == true and type(response.State) == "table" then
		applyState(response.State :: CandyEventState, false)
	end
end
bootstrapAdminButtons()
bootstrapState()

stateUpdatedRemote.OnClientEvent:Connect(function(state)
	if type(state) == "table" then
		applyState(state :: CandyEventState, true)
	end
end)

task.spawn(function()
	while true do
		updateWorldCountdown()
		task.wait(1)
	end
end)
