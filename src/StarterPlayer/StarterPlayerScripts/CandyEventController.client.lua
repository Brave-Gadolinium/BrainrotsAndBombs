--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CandyEventConfiguration = require(ReplicatedStorage.Modules.CandyEventConfiguration)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)

type CandyEventState = CandyEventConfiguration.CandyEventState

local candyEventRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CandyEvent")
local getStateRemote = candyEventRemotes:WaitForChild("GetState") :: RemoteFunction
local stateUpdatedRemote = candyEventRemotes:WaitForChild("StateUpdated") :: RemoteEvent

local timerWorkspace = Workspace:WaitForChild("TimerWorkspace", 20)
local timerSurfaceGui = timerWorkspace and timerWorkspace:WaitForChild("SurfaceGui", 20)
local titleLabel = if timerSurfaceGui then timerSurfaceGui:WaitForChild("TitleLabel", 20) else nil
local currentState: CandyEventState? = nil

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
