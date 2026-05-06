--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local CandyEventConfiguration = require(ReplicatedStorage.Modules.CandyEventConfiguration)
local GlobalEventConfiguration = require(ReplicatedStorage.Modules.GlobalEventConfiguration)

local GlobalEventLightingService = require(ServerScriptService.Modules.GlobalEventLightingService)

type EventDefinition = GlobalEventConfiguration.EventDefinition
type PublicState = GlobalEventConfiguration.PublicState

local TimedGlobalEventService = {}

local RANDOM = Random.new()
local LIGHTING_OWNER_KEY = "TimedGlobalEvent"
local LIGHTING_PRIORITY = 10

local PlayerController
local CarrySystem
local PickaxeController
local BoosterService

local globalEventRemotes: Folder
local getStateRemote: RemoteFunction
local stateUpdatedRemote: RemoteEvent

local started = false
local activeEventId: string? = nil
local activeEventEndsAt: number? = nil
local pendingOrdinaryEvent = false
local lastProcessedSlotIndex = 0
local scheduleStartedAt = 0

local function ensureScheduleStartedAt(): number
	local attributeName = GlobalEventConfiguration.WorkspaceAttributes.ScheduleStartedAt
	local existingValue = Workspace:GetAttribute(attributeName)
	if type(existingValue) == "number" and existingValue > 0 then
		scheduleStartedAt = existingValue
		return scheduleStartedAt
	end

	scheduleStartedAt = Workspace:GetServerTimeNow()
	Workspace:SetAttribute(attributeName, scheduleStartedAt)
	return scheduleStartedAt
end

local function getSlotIndex(now: number): number
	local elapsed = now - ensureScheduleStartedAt()
	if elapsed < GlobalEventConfiguration.SchedulePeriodSeconds then
		return 0
	end

	return math.max(0, math.floor(elapsed / GlobalEventConfiguration.SchedulePeriodSeconds))
end

local function isCandyEventActive(now: number): boolean
	local candyActiveAttribute = Workspace:GetAttribute("CandyEventActive")
	if type(candyActiveAttribute) == "boolean" then
		return candyActiveAttribute
	end

	return CandyEventConfiguration.GetCurrentState(now, ensureScheduleStartedAt()).isActive
end

local function getPublicState(transition: string?, endedEventId: string?): PublicState
	return {
		activeEventId = activeEventId,
		endsAt = activeEventEndsAt,
		serverNow = Workspace:GetServerTimeNow(),
		transition = transition,
		endedEventId = endedEventId,
	}
end

local function pushState(transition: string?, endedEventId: string?)
	if stateUpdatedRemote then
		stateUpdatedRemote:FireAllClients(getPublicState(transition, endedEventId))
	end
end

local function syncWorkspaceAttributes()
	Workspace:SetAttribute(GlobalEventConfiguration.WorkspaceAttributes.ActiveEventId, activeEventId)
	Workspace:SetAttribute(GlobalEventConfiguration.WorkspaceAttributes.EndsAt, activeEventEndsAt)
end

local function getStrongestBombName(): string?
	local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
	if BombsConfigurations.GetStrongestBombName then
		return BombsConfigurations.GetStrongestBombName()
	end

	return "Bomb 15"
end

local function applyRuntimeEffect(eventDefinition: EventDefinition, isActive: boolean)
	if eventDefinition.RuntimeEffect == "SuperRun" and PlayerController and PlayerController.SetTimedWalkSpeedOverride then
		PlayerController:SetTimedWalkSpeedOverride(if isActive then GlobalEventConfiguration.SuperRunWalkSpeed else nil)
		return
	end

	if eventDefinition.RuntimeEffect == "CarryMore" and CarrySystem and CarrySystem.SetGlobalCarryCapacityOverride then
		CarrySystem.SetGlobalCarryCapacityOverride(if isActive then GlobalEventConfiguration.GetMaxCarryCapacity() else nil)
		return
	end

	if eventDefinition.RuntimeEffect == "TntBomb" and PickaxeController and PickaxeController.SetRuntimePickaxeOverride then
		PickaxeController.SetRuntimePickaxeOverride(if isActive then getStrongestBombName() else nil)
		return
	end

	if eventDefinition.RuntimeEffect == "NukeAll" and BoosterService and BoosterService.SetFreeNukeOverride then
		BoosterService:SetFreeNukeOverride(isActive)
	end
end

local function applyLighting(eventDefinition: EventDefinition?)
	if eventDefinition then
		GlobalEventLightingService:SetEffect(LIGHTING_OWNER_KEY, {
			Priority = LIGHTING_PRIORITY,
			SkyboxName = eventDefinition.SkyboxName,
		})
	else
		GlobalEventLightingService:ClearEffect(LIGHTING_OWNER_KEY)
	end
end

local function startRandomEvent()
	local eventDefinition = GlobalEventConfiguration.GetRandomEvent(RANDOM)
	if not eventDefinition then
		return
	end

	local now = Workspace:GetServerTimeNow()
	activeEventId = eventDefinition.Id
	activeEventEndsAt = now + math.max(1, tonumber(eventDefinition.DurationSeconds) or GlobalEventConfiguration.EventDurationSeconds)
	syncWorkspaceAttributes()
	applyRuntimeEffect(eventDefinition, true)
	applyLighting(eventDefinition)
	pushState("Started", nil)
end

local function endActiveEvent()
	local endedEventId = activeEventId
	local eventDefinition = GlobalEventConfiguration.GetEventDefinition(activeEventId)

	if eventDefinition then
		applyRuntimeEffect(eventDefinition, false)
	end

	activeEventId = nil
	activeEventEndsAt = nil
	syncWorkspaceAttributes()
	applyLighting(nil)
	pushState("Ended", endedEventId)
end

local function tryStartPendingEvent(now: number)
	if not pendingOrdinaryEvent or activeEventId ~= nil or isCandyEventActive(now) then
		return
	end

	pendingOrdinaryEvent = false
	startRandomEvent()
end

local function processDueScheduleSlots(now: number)
	local dueSlotIndex = getSlotIndex(now)
	while lastProcessedSlotIndex < dueSlotIndex do
		lastProcessedSlotIndex += 1

		if activeEventId ~= nil or isCandyEventActive(now) then
			pendingOrdinaryEvent = true
		else
			startRandomEvent()
		end
	end
end

local function refresh()
	local now = Workspace:GetServerTimeNow()
	if activeEventId ~= nil and type(activeEventEndsAt) == "number" and now >= activeEventEndsAt then
		endActiveEvent()
	end

	tryStartPendingEvent(now)
	processDueScheduleSlots(now)
	tryStartPendingEvent(now)
end

function TimedGlobalEventService:GetStateForPlayer(_player: Player)
	return {
		Success = true,
		State = getPublicState(nil, nil),
	}
end

function TimedGlobalEventService:GetActiveEventId(): string?
	return activeEventId
end

function TimedGlobalEventService:IsEventActive(eventId: string): boolean
	return activeEventId == eventId
end

function TimedGlobalEventService:Init(controllers)
	PlayerController = controllers.PlayerController
	CarrySystem = require(ServerScriptService.Modules.CarrySystem)
	PickaxeController = require(ServerScriptService.Controllers.PickaxeController)
	BoosterService = require(ServerScriptService.Modules.BoosterService)

	globalEventRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GlobalTimedEvents")
	getStateRemote = globalEventRemotes:WaitForChild("GetState") :: RemoteFunction
	stateUpdatedRemote = globalEventRemotes:WaitForChild("StateUpdated") :: RemoteEvent

	ensureScheduleStartedAt()
	lastProcessedSlotIndex = getSlotIndex(Workspace:GetServerTimeNow())
	syncWorkspaceAttributes()

	getStateRemote.OnServerInvoke = function(player)
		return self:GetStateForPlayer(player)
	end
end

function TimedGlobalEventService:Start()
	if started then
		return
	end

	started = true
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

return TimedGlobalEventService
