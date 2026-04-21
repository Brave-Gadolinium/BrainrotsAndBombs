--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BrainrotEventConfiguration = require(ReplicatedStorage.Modules.BrainrotEventConfiguration)
local Constants = require(ReplicatedStorage.Modules.Constants)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local ItemManager = require(ServerScriptService.Modules.ItemManager)
local TerrainGeneratorManager = require(ServerScriptService.Modules.TerrainGeneratorManager)

type EventDefinition = BrainrotEventConfiguration.EventDefinition

type ActiveEventState = {
	RoundId: number?,
	EventTypeId: string,
	Token: string,
	ItemName: string,
	Rarity: string,
	Message: string,
	CarrierUserId: number?,
	WorldItem: Model?,
	WorldItemConnection: RBXScriptConnection?,
}

local RoundBrainrotEventManager = {}
local ROUND_BRAINROT_EVENTS_ENABLED = true

local MinesFolder = Workspace:WaitForChild("Mines")
local workspaceAttributes = BrainrotEventConfiguration.WorkspaceAttributes
local itemAttributes = BrainrotEventConfiguration.ItemAttributes

local finishEvent: BindableEvent
local roundStartedEvent: BindableEvent

local activeEventState: ActiveEventState? = nil
local lastEventTypeId: string? = nil
local currentRoundId: number? = nil
local scheduleNonce = 0
local started = false
local pendingEventDefinition: EventDefinition? = nil
local pendingEventRoundId: number? = nil

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

local function setWorkspaceActiveState(message: string, token: string, itemName: string, rarity: string, carrierUserId: number?)
	Workspace:SetAttribute(workspaceAttributes.Active, true)
	Workspace:SetAttribute(workspaceAttributes.Message, message)
	Workspace:SetAttribute(workspaceAttributes.Token, token)
	Workspace:SetAttribute(workspaceAttributes.ItemName, itemName)
	Workspace:SetAttribute(workspaceAttributes.Rarity, rarity)
	Workspace:SetAttribute(workspaceAttributes.CarrierUserId, carrierUserId)
end

local function clearWorkspaceActiveState()
	Workspace:SetAttribute(workspaceAttributes.Active, false)
	Workspace:SetAttribute(workspaceAttributes.Message, "")
	Workspace:SetAttribute(workspaceAttributes.Token, nil)
	Workspace:SetAttribute(workspaceAttributes.ItemName, nil)
	Workspace:SetAttribute(workspaceAttributes.Rarity, nil)
	Workspace:SetAttribute(workspaceAttributes.CarrierUserId, nil)
end

local function disconnectWorldItemConnection(state: ActiveEventState)
	if state.WorldItemConnection then
		state.WorldItemConnection:Disconnect()
		state.WorldItemConnection = nil
	end
end

local function buildEventAttributes(token: string, rarity: string, itemName: string): {[string]: any}
	return {
		[itemAttributes.IsEventBrainrot] = true,
		[itemAttributes.Token] = token,
		[itemAttributes.Rarity] = rarity,
		[itemAttributes.ItemName] = itemName,
	}
end

local function syncWorkspaceFromActiveState()
	local state = activeEventState
	if not state then
		clearWorkspaceActiveState()
		return
	end

	setWorkspaceActiveState(state.Message, state.Token, state.ItemName, state.Rarity, state.CarrierUserId)
end

local function trackWorldItem(itemModel: Model?)
	local state = activeEventState
	if not state then
		if itemModel and itemModel.Parent then
			itemModel:Destroy()
		end
		return
	end

	disconnectWorldItemConnection(state)
	state.WorldItem = itemModel

	if not itemModel then
		return
	end

	state.WorldItemConnection = itemModel.AncestryChanged:Connect(function(_, parent)
		local currentState = activeEventState
		if currentState ~= state then
			return
		end

		if parent == nil and currentState.WorldItem == itemModel then
			currentState.WorldItem = nil
			disconnectWorldItemConnection(currentState)
		end
	end)
end

local function clearActiveEventState(destroyWorldItem: boolean)
	local state = activeEventState
	if not state then
		clearWorkspaceActiveState()
		return
	end

	activeEventState = nil
	disconnectWorldItemConnection(state)

	if destroyWorldItem and state.WorldItem and state.WorldItem.Parent then
		state.WorldItem:Destroy()
	end

	clearWorkspaceActiveState()
end

local function getSpawnZonePart(): BasePart?
	local zonePart = MinesFolder:FindFirstChild(BrainrotEventConfiguration.SpawnZoneName)
	if zonePart and zonePart:IsA("BasePart") then
		return zonePart
	end

	return nil
end

local function getRandomSpawnPosition(zonePart: BasePart): Vector3
	local randomX = (math.random() - 0.5) * (zonePart.Size.X * 0.85)
	local randomZ = (math.random() - 0.5) * (zonePart.Size.Z * 0.85)
	local surfaceOffsetY = (zonePart.Size.Y * 0.5) + 8

	return (zonePart.CFrame * CFrame.new(randomX, surfaceOffsetY, randomZ)).Position
end

local function chooseEventDefinition(preferredEventTypeId: string?): EventDefinition?
	if preferredEventTypeId then
		return BrainrotEventConfiguration.GetEventDefinition(preferredEventTypeId)
	end

	local candidates = {}

	for _, definition in ipairs(BrainrotEventConfiguration.EventTypes) do
		if definition.Id ~= lastEventTypeId then
			table.insert(candidates, definition)
		end
	end

	if #candidates == 0 then
		candidates = BrainrotEventConfiguration.EventTypes
	end

	if #candidates == 0 then
		return nil
	end

	return candidates[math.random(1, #candidates)]
end

local function spawnConfiguredEvent(definition: EventDefinition, roundId: number?): (boolean, string?)
	local zonePart = getSpawnZonePart()
	if not zonePart then
		return false, "Spawn zone not found."
	end

	if not TerrainGeneratorManager.IsZoneReady(zonePart.Name) then
		return false, "Spawn zone is not ready yet."
	end

	local possibleItems = ItemConfigurations.GetItemsByRarity(definition.Rarity)
	if #possibleItems == 0 then
		return false, "No items configured for event rarity."
	end

	local itemName = possibleItems[math.random(1, #possibleItems)]
	local token = HttpService:GenerateGUID(false)
	local spawnPosition = getRandomSpawnPosition(zonePart)
	local worldItem = ItemManager.SpawnWorldItemAtPosition(
		itemName,
		BrainrotEventConfiguration.DefaultMutation,
		definition.Rarity,
		spawnPosition,
		{
			Level = 1,
			Parent = Workspace,
			ExtraAttributes = buildEventAttributes(token, definition.Rarity, itemName),
		}
	)

	if not worldItem then
		return false, "Failed to spawn event brainrot."
	end

	lastEventTypeId = definition.Id
	activeEventState = {
		RoundId = roundId,
		EventTypeId = definition.Id,
		Token = token,
		ItemName = itemName,
		Rarity = definition.Rarity,
		Message = definition.Message,
		CarrierUserId = nil,
		WorldItem = nil,
		WorldItemConnection = nil,
	}

	trackWorldItem(worldItem)
	syncWorkspaceFromActiveState()

	local notificationRemote = getNotificationRemote()
	if notificationRemote then
		notificationRemote:FireAllClients(definition.Message, "Success")
	end

	return true, nil
end

local function trySpawnPendingEvent()
	local definition = pendingEventDefinition
	if not definition then
		return
	end

	if pendingEventRoundId ~= currentRoundId then
		pendingEventDefinition = nil
		pendingEventRoundId = nil
		return
	end

	if activeEventState then
		return
	end

	local zonePart = getSpawnZonePart()
	if not zonePart or not TerrainGeneratorManager.IsZoneReady(zonePart.Name) then
		return
	end

	local success, errorMessage = spawnConfiguredEvent(definition, pendingEventRoundId)
	if not success then
		if errorMessage and errorMessage ~= "Spawn zone is not ready yet." then
			warn("[RoundBrainrotEventManager]", errorMessage)
			pendingEventDefinition = nil
			pendingEventRoundId = nil
		end
		return
	end

	pendingEventDefinition = nil
	pendingEventRoundId = nil
end

local function scheduleRoundEvent(roundId: number, roundDuration: number)
	scheduleNonce += 1
	local currentNonce = scheduleNonce
	local configuredDelay = tonumber(BrainrotEventConfiguration.RoundSpawnDelaySeconds) or 30
	local maxSafeDelay = math.max(1, math.floor(roundDuration) - 1)
	local delaySeconds = math.clamp(math.floor(configuredDelay), 1, maxSafeDelay)

	task.delay(delaySeconds, function()
		if scheduleNonce ~= currentNonce then
			return
		end

		if currentRoundId ~= roundId then
			return
		end

		if activeEventState then
			return
		end

		local definition = chooseEventDefinition(nil)
		if not definition then
			return
		end

		local success, errorMessage = spawnConfiguredEvent(definition, roundId)
		if success then
			return
		end

		pendingEventDefinition = definition
		pendingEventRoundId = roundId
		if errorMessage and errorMessage ~= "Spawn zone is not ready yet." then
			warn("[RoundBrainrotEventManager]", errorMessage)
		end

		trySpawnPendingEvent()
	end)
end

local function handleRoundStarted(roundId: number, _startedAt: number?, roundDuration: number?)
	if currentRoundId == roundId then
		return
	end

	currentRoundId = roundId
	pendingEventDefinition = nil
	pendingEventRoundId = nil
	clearActiveEventState(true)
	scheduleRoundEvent(roundId, roundDuration or Constants.SESSION_DURATION)
end

local function handleRoundFinished()
	currentRoundId = nil
	pendingEventDefinition = nil
	pendingEventRoundId = nil
	scheduleNonce += 1
	clearActiveEventState(true)
end

function RoundBrainrotEventManager:IsTokenActive(token: string?): boolean
	local state = activeEventState
	return state ~= nil and type(token) == "string" and token ~= "" and state.Token == token
end

function RoundBrainrotEventManager:GetActiveEventState()
	return activeEventState
end

function RoundBrainrotEventManager:HandleEventItemPickedUp(player: Player, token: string?): boolean
	local state = activeEventState
	if not state or state.Token ~= token then
		return false
	end

	state.CarrierUserId = player.UserId
	trackWorldItem(nil)
	syncWorkspaceFromActiveState()
	return true
end

function RoundBrainrotEventManager:HandleEventItemDropped(itemData, targetPos: Vector3, originPos: Vector3?): boolean
	local state = activeEventState
	if not state then
		return false
	end

	local eventAttributes = type(itemData) == "table" and itemData.EventAttributes or nil
	local token = type(eventAttributes) == "table" and eventAttributes[itemAttributes.Token] or nil
	if state.Token ~= token then
		return false
	end

	local worldItem = ItemManager.SpawnDroppedItem(
		itemData.Name,
		itemData.Mutation,
		itemData.Rarity,
		targetPos,
		originPos,
		{
			Level = itemData.Level or 1,
			ExtraAttributes = buildEventAttributes(state.Token, state.Rarity, state.ItemName),
		}
	)

	if not worldItem then
		return false
	end

	state.CarrierUserId = nil
	trackWorldItem(worldItem)
	syncWorkspaceFromActiveState()
	return true
end

function RoundBrainrotEventManager:HandleEventItemDelivered(itemInstance: Instance?): boolean
	local state = activeEventState
	if not state or not itemInstance then
		return false
	end

	local token = itemInstance:GetAttribute(itemAttributes.Token)
	if state.Token ~= token then
		return false
	end

	clearActiveEventState(false)
	return true
end

function RoundBrainrotEventManager:ForceStartEvent(eventTypeId: string?): (boolean, string)
	if not ROUND_BRAINROT_EVENTS_ENABLED then
		return false, "Round brainrot events are temporarily disabled for tests."
	end

	local definition = chooseEventDefinition(eventTypeId)
	if not definition then
		return false, "Event definition not found."
	end

	scheduleNonce += 1
	clearActiveEventState(true)

	local success, errorMessage = spawnConfiguredEvent(definition, currentRoundId)
	if success then
		return true, `Started {definition.Id} event.`
	end

	pendingEventDefinition = definition
	pendingEventRoundId = currentRoundId
	trySpawnPendingEvent()
	if errorMessage == "Spawn zone is not ready yet." then
		return true, `Queued {definition.Id} event until {BrainrotEventConfiguration.SpawnZoneName} is ready.`
	end

	if not success then
		return false, errorMessage or "Failed to start event."
	end

	return true, `Started {definition.Id} event.`
end

function RoundBrainrotEventManager:ForceClearActiveEvent(): (boolean, string)
	scheduleNonce += 1
	clearActiveEventState(true)
	return true, "Cleared active brainrot event."
end

function RoundBrainrotEventManager:Start()
	if started then
		return
	end

	started = true
	clearActiveEventState(true)

	if not ROUND_BRAINROT_EVENTS_ENABLED then
		currentRoundId = nil
		pendingEventDefinition = nil
		pendingEventRoundId = nil
		scheduleNonce += 1
		return
	end

	finishEvent = ensureBindableEvent("FinishTime")
	roundStartedEvent = ensureBindableEvent("RoundStarted")

	roundStartedEvent.Event:Connect(handleRoundStarted)
	finishEvent.Event:Connect(handleRoundFinished)
	TerrainGeneratorManager.ZoneReadyChanged:Connect(function()
		trySpawnPendingEvent()
	end)

	local liveRoundId = tonumber(Workspace:GetAttribute("SessionRoundId"))
	local sessionEnded = Workspace:GetAttribute("SessionEnded") == true
	if liveRoundId and not sessionEnded then
		handleRoundStarted(liveRoundId, tonumber(Workspace:GetAttribute("SessionRoundStartedAt")), Constants.SESSION_DURATION)
	end

	trySpawnPendingEvent()
end

return RoundBrainrotEventManager
