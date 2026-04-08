local TimerManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Modules.Constants)
local DepthLevelUtils = require(ServerScriptService.Modules.DepthLevelUtils)
local SpawnUtils = require(ServerScriptService.Modules.SpawnUtils)

local function ensureTimerFolder(): Folder
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local timerFolder = remotesFolder:FindFirstChild("Timer")
	if not timerFolder then
		timerFolder = Instance.new("Folder")
		timerFolder.Name = "Timer"
		timerFolder.Parent = remotesFolder
	end

	return timerFolder
end

local function ensureTimerFinishEvent(): BindableEvent
	local timerFolder = ensureTimerFolder()
	local finishTime = timerFolder:FindFirstChild("FinishTime")
	if not finishTime then
		finishTime = Instance.new("BindableEvent")
		finishTime.Name = "FinishTime"
		finishTime.Parent = timerFolder
	end

	return finishTime :: BindableEvent
end

local function ensureRoundStartedEvent(): BindableEvent
	local timerFolder = ensureTimerFolder()
	local roundStarted = timerFolder:FindFirstChild("RoundStarted")
	if not roundStarted then
		roundStarted = Instance.new("BindableEvent")
		roundStarted.Name = "RoundStarted"
		roundStarted.Parent = timerFolder
	end

	return roundStarted :: BindableEvent
end

local FinishTime = ensureTimerFinishEvent()
local RoundStarted = ensureRoundStartedEvent()
local currentRoundId = 0

local function isInsideMineZone(position: Vector3): boolean
	return DepthLevelUtils.GetDepthLevelAtPosition(position) > 0
end

local function teleportPlayerToBase(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	if not isInsideMineZone(root.Position) then
		return
	end

	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then
		return
	end

	local spawnCFrame = SpawnUtils.GetPlotSpawnCFrame(plot, 3)
	if spawnCFrame then
		root.CFrame = spawnCFrame
	end
end

function TimerManager:Start()
	task.spawn(function()
		while true do
			currentRoundId += 1
			local remaining = Constants.SESSION_DURATION
			local startedAt = Workspace:GetServerTimeNow()
			Workspace:SetAttribute("SessionRoundId", currentRoundId)
			Workspace:SetAttribute("SessionRoundStartedAt", startedAt)
			Workspace:SetAttribute("SessionTimeRemaining", remaining)
			Workspace:SetAttribute("SessionMessage", "")
			Workspace:SetAttribute("SessionEnded", false)
			RoundStarted:Fire(currentRoundId, startedAt, Constants.SESSION_DURATION)

			while remaining > 0 do
				task.wait(1)
				remaining -= 1
				Workspace:SetAttribute("SessionTimeRemaining", remaining)
			end

			Workspace:SetAttribute("SessionEnded", true)
			Workspace:SetAttribute("SessionMessage", "Тайм закончен!")

			for _, player in ipairs(Players:GetPlayers()) do
				teleportPlayerToBase(player)
			end

			FinishTime:Fire()
			task.wait(Constants.SESSION_END_MESSAGE_DURATION)
		end
	end)
end

return TimerManager
