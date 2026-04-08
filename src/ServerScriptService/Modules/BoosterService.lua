--!strict
-- LOCATION: ServerScriptService/Modules/BoosterService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local BoosterService = {}

local PlayerController
local BombManager
local showContextualOfferEvent: RemoteEvent?
local requestAutoBombStateEvent: RemoteEvent?
local autoBombHeartbeatStarted = false

local depthBlockedTimestamps: {[Player]: {number}} = {}
local manualCollectTimestamps: {[Player]: {number}} = {}

local DEPTH_BLOCK_WINDOW = 60
local DEPTH_BLOCK_THRESHOLD = 2
local MANUAL_COLLECT_WINDOW = 5 * 60
local MANUAL_COLLECT_THRESHOLD = 3
local AUTO_BOMB_CHECK_INTERVAL = 0.2
local GLOBAL_OFFER_COOLDOWN = 60
local PER_OFFER_COOLDOWN = 180

local BOOSTER_ATTRIBUTE_BY_NAME = {
	MegaExplosion = "MegaExplosionEndsAt",
	Shield = "ShieldEndsAt",
}

local BOOSTER_PROFILE_KEY_BY_NAME = {
	MegaExplosion = "MegaExplosionEndsAt",
	Shield = "ShieldEndsAt",
}

local oneTimeSessionOfferKeys = {
	EarlyGame = true,
	CrowdedServer = true,
}

type OfferState = {
	LastAnyOfferAt: number,
	LastOfferAt: {[string]: number},
	ShownThisSession: {[string]: boolean},
}

local offerStateByPlayer: {[Player]: OfferState} = {}

local function getPlayerController()
	if PlayerController then
		return PlayerController
	end

	PlayerController = require(ServerScriptService.Controllers.PlayerController)
	return PlayerController
end

local function getBombManager()
	if BombManager then
		return BombManager
	end

	BombManager = require(ServerScriptService.Modules.BombManager)
	return BombManager
end

local function getEventsFolder(): Folder
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder and eventsFolder:IsA("Folder") then
		return eventsFolder
	end

	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
	return eventsFolder
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local eventsFolder = getEventsFolder()
	local existing = eventsFolder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = eventsFolder
	return remote
end

local function getShowContextualOfferEvent(): RemoteEvent
	if showContextualOfferEvent and showContextualOfferEvent.Parent then
		return showContextualOfferEvent
	end

	showContextualOfferEvent = ensureRemoteEvent("ShowContextualOffer")
	return showContextualOfferEvent
end

local function getRequestAutoBombStateEvent(): RemoteEvent
	if requestAutoBombStateEvent and requestAutoBombStateEvent.Parent then
		return requestAutoBombStateEvent
	end

	requestAutoBombStateEvent = ensureRemoteEvent("RequestAutoBombState")
	return requestAutoBombStateEvent
end

local function getBoosterConfig(boosterName: string)
	return ProductConfigurations.Boosters[boosterName]
end

local function getProfile(player: Player)
	local playerController = getPlayerController()
	return playerController and playerController:GetProfile(player)
end

local function ensureBoosterData(profile): {[string]: number}?
	if not profile or type(profile.Data) ~= "table" then
		return nil
	end

	if type(profile.Data.Boosters) ~= "table" then
		profile.Data.Boosters = {
			MegaExplosionEndsAt = 0,
			ShieldEndsAt = 0,
		}
	end

	local boosters = profile.Data.Boosters
	boosters.MegaExplosionEndsAt = math.max(0, tonumber(boosters.MegaExplosionEndsAt) or 0)
	boosters.ShieldEndsAt = math.max(0, tonumber(boosters.ShieldEndsAt) or 0)
	return boosters
end

local function getBoosterEndsAt(player: Player, boosterName: string): number
	local profile = getProfile(player)
	local boosters = profile and ensureBoosterData(profile)
	local profileKey = BOOSTER_PROFILE_KEY_BY_NAME[boosterName]
	if not boosters or not profileKey then
		return 0
	end

	local endsAt = math.max(0, tonumber(boosters[profileKey]) or 0)
	if endsAt <= os.time() then
		return 0
	end

	return endsAt
end

local function syncBoosterAttribute(player: Player, boosterName: string)
	local attributeName = BOOSTER_ATTRIBUTE_BY_NAME[boosterName]
	if not attributeName then
		return
	end

	player:SetAttribute(attributeName, getBoosterEndsAt(player, boosterName))
end

local function pruneTimestamps(list: {number}, cutoff: number)
	local nextIndex = 1
	for _, timestamp in ipairs(list) do
		if timestamp >= cutoff then
			list[nextIndex] = timestamp
			nextIndex += 1
		end
	end

	for index = #list, nextIndex, -1 do
		list[index] = nil
	end
end

local function fireOffer(player: Player, offerKey: string, payload: {[string]: any}?)
	local state = offerStateByPlayer[player]
	if not state then
		state = {
			LastAnyOfferAt = 0,
			LastOfferAt = {},
			ShownThisSession = {},
		}
		offerStateByPlayer[player] = state
	end

	local now = os.clock()
	if (now - state.LastAnyOfferAt) < GLOBAL_OFFER_COOLDOWN then
		return
	end

	local lastOfferAt = state.LastOfferAt[offerKey] or 0
	if (now - lastOfferAt) < PER_OFFER_COOLDOWN then
		return
	end

	if oneTimeSessionOfferKeys[offerKey] and state.ShownThisSession[offerKey] then
		return
	end

	state.LastAnyOfferAt = now
	state.LastOfferAt[offerKey] = now
	state.ShownThisSession[offerKey] = true
	getShowContextualOfferEvent():FireClient(player, offerKey, payload or {})
end

local function hasGamePassAttribute(player: Player, attributeName: string): boolean
	return player:GetAttribute(attributeName) == true
end

local function setAutoBombEnabled(player: Player, active: boolean)
	local nextValue = active and hasGamePassAttribute(player, "HasAutoBomb")
	player:SetAttribute("AutoBombEnabled", nextValue)
end

function BoosterService:GetTimedBoosterEndsAt(player: Player, boosterName: string): number
	return getBoosterEndsAt(player, boosterName)
end

function BoosterService:ActivateTimedBooster(player: Player, boosterName: string): number
	local config = getBoosterConfig(boosterName)
	local profile = getProfile(player)
	local boosters = profile and ensureBoosterData(profile)
	local profileKey = BOOSTER_PROFILE_KEY_BY_NAME[boosterName]
	if not config or not boosters or not profileKey then
		return 0
	end

	local endsAt = os.time() + math.max(0, tonumber(config.Duration) or 0)
	boosters[profileKey] = endsAt
	syncBoosterAttribute(player, boosterName)
	return endsAt
end

function BoosterService:HasActiveMegaExplosion(player: Player): boolean
	return getBoosterEndsAt(player, "MegaExplosion") > 0
end

function BoosterService:HasActiveShield(player: Player): boolean
	return getBoosterEndsAt(player, "Shield") > 0
end

function BoosterService:HasAutoBomb(player: Player): boolean
	return hasGamePassAttribute(player, "HasAutoBomb")
end

function BoosterService:IsAutoBombEnabled(player: Player): boolean
	return player:GetAttribute("AutoBombEnabled") == true and self:HasAutoBomb(player)
end

function BoosterService:SetAutoBombEnabled(player: Player, active: boolean)
	setAutoBombEnabled(player, active)
end

function BoosterService:SyncPlayer(player: Player)
	syncBoosterAttribute(player, "MegaExplosion")
	syncBoosterAttribute(player, "Shield")
	player:SetAttribute("HasAutoBomb", player:GetAttribute("HasAutoBomb") == true)
	player:SetAttribute("AutoBombEnabled", player:GetAttribute("AutoBombEnabled") == true and player:GetAttribute("HasAutoBomb") == true)
end

function BoosterService:PromptShieldOffer(player: Player)
	fireOffer(player, "Shield")
end

function BoosterService:TriggerOffer(player: Player, offerKey: string, payload: {[string]: any}?)
	if type(offerKey) ~= "string" or offerKey == "" then
		return
	end

	fireOffer(player, offerKey, payload)
end

function BoosterService:RecordDepthBlocked(player: Player)
	local now = os.time()
	local timestamps = depthBlockedTimestamps[player]
	if not timestamps then
		timestamps = {}
		depthBlockedTimestamps[player] = timestamps
	end

	timestamps[#timestamps + 1] = now
	pruneTimestamps(timestamps, now - DEPTH_BLOCK_WINDOW)

	if #timestamps >= DEPTH_BLOCK_THRESHOLD then
		table.clear(timestamps)
		fireOffer(player, "BombUpgrade")
	end
end

function BoosterService:RecordManualCollect(player: Player)
	if hasGamePassAttribute(player, "HasCollectAll") then
		return
	end

	local now = os.time()
	local timestamps = manualCollectTimestamps[player]
	if not timestamps then
		timestamps = {}
		manualCollectTimestamps[player] = timestamps
	end

	timestamps[#timestamps + 1] = now
	pruneTimestamps(timestamps, now - MANUAL_COLLECT_WINDOW)

	if #timestamps >= MANUAL_COLLECT_THRESHOLD then
		table.clear(timestamps)
		fireOffer(player, "AutoCollect")
	end
end

function BoosterService:TriggerNukeBooster(player: Player): boolean
	local bombManager = getBombManager()
	if bombManager and bombManager.TriggerNukeBlast then
		return bombManager.TriggerNukeBlast(player) == true
	end

	return false
end

local function startAutoBombHeartbeat()
	if autoBombHeartbeatStarted then
		return
	end

	autoBombHeartbeatStarted = true
	task.spawn(function()
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				if BoosterService:IsAutoBombEnabled(player) then
					local bombManager = getBombManager()
					if bombManager and bombManager.TryThrowBomb then
						bombManager.TryThrowBomb(player, nil, {
							Silent = true,
							IsAutoBomb = true,
						})
					end
				end
			end

			task.wait(AUTO_BOMB_CHECK_INTERVAL)
		end
	end)
end

function BoosterService:Init(controllers)
	PlayerController = controllers.PlayerController

	local autoBombEvent = getRequestAutoBombStateEvent()
	autoBombEvent.OnServerEvent:Connect(function(player, active)
		if type(active) ~= "boolean" then
			return
		end

		setAutoBombEnabled(player, active)
	end)
end

function BoosterService:Start()
	startAutoBombHeartbeat()

	for _, player in ipairs(Players:GetPlayers()) do
		self:SyncPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			if player.Parent then
				BoosterService:SyncPlayer(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		depthBlockedTimestamps[player] = nil
		manualCollectTimestamps[player] = nil
		offerStateByPlayer[player] = nil
	end)
end

return BoosterService
