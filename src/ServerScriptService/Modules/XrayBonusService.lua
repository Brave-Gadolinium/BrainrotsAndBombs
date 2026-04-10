--!strict
-- LOCATION: ServerScriptService/Modules/XrayBonusService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Modules.Constants)
local XrayBonusConfiguration = require(ReplicatedStorage.Modules.XrayBonusConfiguration)

local XrayBonusService = {}

local Templates = ReplicatedStorage:WaitForChild("Templates")
local MinesFolder = Workspace:WaitForChild("Mines")

local ATTRIBUTE_HAS_XRAY = "HasXRayBonus"
local ATTRIBUTE_XRAY_ROUND_ID = "XRayRoundId"

local finishEvent: BindableEvent
local roundStartedEvent: BindableEvent

local currentRoundId: number? = nil
local activeBonusModel: Model? = nil
local activeBonusPromptConnection: RBXScriptConnection? = nil
local activeBonusAncestryConnection: RBXScriptConnection? = nil
local spawnScheduleToken = 0
local xrayHolderUserId: number? = nil
local started = false
local warnedMissingTemplate = false

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

local function ensureBindableEvent(name: string): BindableEvent
	local timerFolder = ensureTimerFolder()
	local eventInstance = timerFolder:FindFirstChild(name)
	if not eventInstance then
		eventInstance = Instance.new("BindableEvent")
		eventInstance.Name = name
		eventInstance.Parent = timerFolder
	end

	return eventInstance :: BindableEvent
end

local function getNotificationRemote(): RemoteEvent?
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local remote = eventsFolder and eventsFolder:FindFirstChild("ShowNotification")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function setPlayerXrayState(player: Player, enabled: boolean, roundId: number?)
	player:SetAttribute(ATTRIBUTE_HAS_XRAY, enabled == true)
	player:SetAttribute(ATTRIBUTE_XRAY_ROUND_ID, if enabled then (roundId or 0) else 0)
end

local function clearAllPlayerXrayState()
	for _, player in ipairs(Players:GetPlayers()) do
		setPlayerXrayState(player, false, 0)
	end
end

local function isInsidePart(position: Vector3, part: BasePart): boolean
	local relativePos = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5

	return math.abs(relativePos.X) <= halfSize.X
		and math.abs(relativePos.Y) <= halfSize.Y
		and math.abs(relativePos.Z) <= halfSize.Z
end

local function findMineZonePart(position: Vector3): BasePart?
	local highestZoneLevel = 0
	local containingZonePart: BasePart? = nil

	for _, child in ipairs(MinesFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local zoneLevel = tonumber(string.match(child.Name, "^Zone(%d+)$"))
			if zoneLevel and zoneLevel >= highestZoneLevel and isInsidePart(position, child) then
				highestZoneLevel = zoneLevel
				containingZonePart = child
			end
		end
	end

	return containingZonePart
end

local function getAliveRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function isPlayerEligible(player: Player): boolean
	if player:GetAttribute(ATTRIBUTE_HAS_XRAY) == true then
		return false
	end

	local rootPart = getAliveRootPart(player)
	if not rootPart then
		return false
	end

	return findMineZonePart(rootPart.Position) ~= nil
end

local function getEligiblePlayers(): {Player}
	local eligiblePlayers = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if isPlayerEligible(player) then
			table.insert(eligiblePlayers, player)
		end
	end

	return eligiblePlayers
end

local function getSpawnChance(): number
	local configuredChance = tonumber(XrayBonusConfiguration.SpawnChancePerRound) or 0
	if configuredChance > 1 then
		configuredChance /= 100
	end

	return math.clamp(configuredChance, 0, 1)
end

local function getXrayTemplate(): Model?
	local template = Templates:FindFirstChild("Xray")
	if template and template:IsA("Model") then
		return template
	end

	if not warnedMissingTemplate then
		warn("[XrayBonusService] Templates.Xray is missing or is not a Model.")
		warnedMissingTemplate = true
	end

	return nil
end

local function cleanupActiveBonus()
	if activeBonusPromptConnection then
		activeBonusPromptConnection:Disconnect()
		activeBonusPromptConnection = nil
	end

	if activeBonusAncestryConnection then
		activeBonusAncestryConnection:Disconnect()
		activeBonusAncestryConnection = nil
	end

	if activeBonusModel and activeBonusModel.Parent then
		activeBonusModel:Destroy()
	end

	activeBonusModel = nil
end

local function getModelBottomOffset(model: Model): number
	local boundingBox, size = model:GetBoundingBox()
	return model:GetPivot().Position.Y - (boundingBox.Position.Y - (size.Y * 0.5))
end

local function prepareBonusModel(model: Model)
	local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primaryPart then
		return nil
	end

	model.PrimaryPart = primaryPart
	model.Name = "XrayBonus"
	model:SetAttribute("IsXrayBonus", true)
	model:SetAttribute("SessionRoundId", currentRoundId or 0)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end

	return primaryPart
end

local function findSpawnPositionNearPlayer(player: Player): Vector3?
	local rootPart = getAliveRootPart(player)
	if not rootPart then
		return nil
	end

	local zonePart = findMineZonePart(rootPart.Position)
	if not zonePart then
		return nil
	end

	local minDistance = math.max(0, tonumber(XrayBonusConfiguration.SpawnDistanceMin) or 8)
	local maxDistance = math.max(minDistance, tonumber(XrayBonusConfiguration.SpawnDistanceMax) or 16)
	local maxAttempts = math.max(1, math.floor(tonumber(XrayBonusConfiguration.MaxSpawnPositionAttempts) or 12))
	local raycastHeight = math.max(2, tonumber(XrayBonusConfiguration.SpawnRaycastHeight) or 10)
	local raycastDepth = math.max(4, tonumber(XrayBonusConfiguration.SpawnRaycastDepth) or 32)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {player.Character or player}

	for _ = 1, maxAttempts do
		local angle = math.random() * math.pi * 2
		local distance = minDistance + (math.random() * (maxDistance - minDistance))
		local offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local horizontalPosition = rootPart.Position + offset

		if isInsidePart(horizontalPosition, zonePart) then
			local rayOrigin = horizontalPosition + Vector3.new(0, raycastHeight, 0)
			local rayDirection = Vector3.new(0, -raycastDepth, 0)
			local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
			if result and isInsidePart(result.Position, zonePart) then
				return result.Position
			end
		end
	end

	return nil
end

local function spawnBonusAtPosition(position: Vector3): boolean
	local template = getXrayTemplate()
	if not template then
		return false
	end

	cleanupActiveBonus()

	local model = template:Clone()
	local primaryPart = prepareBonusModel(model)
	if not primaryPart then
		model:Destroy()
		warn("[XrayBonusService] Xray bonus model has no BasePart.")
		return false
	end

	local bottomOffset = getModelBottomOffset(model)
	model:PivotTo(CFrame.new(position + Vector3.new(0, bottomOffset, 0)))
	model.Parent = Workspace
	activeBonusModel = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = tostring(XrayBonusConfiguration.PromptActionText or "Pick Up")
	prompt.ObjectText = tostring(XrayBonusConfiguration.PromptObjectText or "X-ray")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = math.max(1, tonumber(XrayBonusConfiguration.PickupMaxDistance) or 12)
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = primaryPart

	activeBonusPromptConnection = prompt.Triggered:Connect(function(player)
		if activeBonusModel ~= model or xrayHolderUserId ~= nil then
			return
		end

		if not isPlayerEligible(player) then
			return
		end

		xrayHolderUserId = player.UserId
		setPlayerXrayState(player, true, currentRoundId)

		local notificationRemote = getNotificationRemote()
		if notificationRemote then
			notificationRemote:FireClient(player, tostring(XrayBonusConfiguration.NotificationText), "Success")
		end

		cleanupActiveBonus()
	end)

	activeBonusAncestryConnection = model.AncestryChanged:Connect(function(_, parent)
		if model ~= activeBonusModel then
			return
		end

		if parent == nil then
			cleanupActiveBonus()
		end
	end)

	return true
end

local function trySpawnBonusForEligiblePlayers(): boolean
	local eligiblePlayers = getEligiblePlayers()
	if #eligiblePlayers == 0 then
		return false
	end

	local startIndex = math.random(1, #eligiblePlayers)
	for offset = 0, #eligiblePlayers - 1 do
		local playerIndex = ((startIndex + offset - 1) % #eligiblePlayers) + 1
		local player = eligiblePlayers[playerIndex]
		local spawnPosition = findSpawnPositionNearPlayer(player)
		if spawnPosition and spawnBonusAtPosition(spawnPosition) then
			return true
		end
	end

	return false
end

local function scheduleSpawnForRound(roundId: number, startedAt: number?, roundDuration: number?)
	spawnScheduleToken += 1
	local scheduleToken = spawnScheduleToken

	local roundDurationSeconds = math.max(1, math.floor(tonumber(roundDuration) or Constants.SESSION_DURATION))
	local spawnWindowSeconds = math.min(
		math.max(0, tonumber(XrayBonusConfiguration.SpawnRetryWindowSeconds) or 0),
		math.max(0, roundDurationSeconds - 1)
	)
	local retryDelaySeconds = math.max(1, tonumber(XrayBonusConfiguration.RetryDelaySecondsWhenNoEligiblePlayers) or 6)
	local initialDelaySeconds = math.max(0, tonumber(XrayBonusConfiguration.InitialSpawnDelaySeconds) or 0)
	local liveStartedAt = tonumber(startedAt) or Workspace:GetServerTimeNow()
	local elapsedSeconds = math.max(0, Workspace:GetServerTimeNow() - liveStartedAt)
	local effectiveInitialDelay = math.max(0, initialDelaySeconds - elapsedSeconds)
	local attemptDeadline = liveStartedAt + spawnWindowSeconds
	local spawnChance = getSpawnChance()

	task.spawn(function()
		if effectiveInitialDelay > 0 then
			task.wait(effectiveInitialDelay)
		end

		if scheduleToken ~= spawnScheduleToken or currentRoundId ~= roundId or Workspace:GetAttribute("SessionEnded") == true then
			return
		end

		if spawnChance <= 0 or math.random() > spawnChance then
			return
		end

		while scheduleToken == spawnScheduleToken do
			if currentRoundId ~= roundId or Workspace:GetAttribute("SessionEnded") == true then
				return
			end

			if activeBonusModel or xrayHolderUserId ~= nil then
				return
			end

			if Workspace:GetServerTimeNow() > attemptDeadline then
				return
			end

			if trySpawnBonusForEligiblePlayers() then
				return
			end

			task.wait(retryDelaySeconds)
		end
	end)
end

local function handleRoundStarted(roundId: number, startedAt: number?, roundDuration: number?)
	currentRoundId = roundId
	xrayHolderUserId = nil
	cleanupActiveBonus()
	clearAllPlayerXrayState()

	if not XrayBonusConfiguration.Enabled then
		return
	end

	scheduleSpawnForRound(roundId, startedAt, roundDuration)
end

local function handleRoundFinished()
	currentRoundId = nil
	xrayHolderUserId = nil
	spawnScheduleToken += 1
	cleanupActiveBonus()
	clearAllPlayerXrayState()
end

function XrayBonusService:Start()
	if started then
		return
	end

	started = true
	finishEvent = ensureBindableEvent("FinishTime")
	roundStartedEvent = ensureBindableEvent("RoundStarted")

	for _, player in ipairs(Players:GetPlayers()) do
		setPlayerXrayState(player, false, 0)
	end

	Players.PlayerAdded:Connect(function(player)
		setPlayerXrayState(player, false, 0)
	end)

	Players.PlayerRemoving:Connect(function(player)
		if xrayHolderUserId == player.UserId then
			xrayHolderUserId = nil
			setPlayerXrayState(player, false, 0)
		end
	end)

	roundStartedEvent.Event:Connect(handleRoundStarted)
	finishEvent.Event:Connect(handleRoundFinished)

	local liveRoundId = tonumber(Workspace:GetAttribute("SessionRoundId"))
	if liveRoundId and Workspace:GetAttribute("SessionEnded") ~= true then
		handleRoundStarted(
			liveRoundId,
			tonumber(Workspace:GetAttribute("SessionRoundStartedAt")),
			tonumber(Workspace:GetAttribute("SessionTimeRemaining")) or Constants.SESSION_DURATION
		)
	end
end

return XrayBonusService
