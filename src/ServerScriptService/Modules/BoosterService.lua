--!strict
-- LOCATION: ServerScriptService/Modules/BoosterService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)

local BoosterService = {}

local PlayerController
local BombManager
local showContextualOfferEvent: RemoteEvent?
local requestAutoBombStateEvent: RemoteEvent?
local requestUseBoosterChargeEvent: RemoteEvent?
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
local SHIELD_FORCE_FIELD_NAME = "ShieldBoosterForceField"

local BOOSTER_ATTRIBUTE_BY_NAME = {
	MegaExplosion = "MegaExplosionEndsAt",
	Shield = "ShieldEndsAt",
}

local BOOSTER_PROFILE_KEY_BY_NAME = {
	MegaExplosion = "MegaExplosionEndsAt",
	Shield = "ShieldEndsAt",
}

local BOOSTER_CHARGE_ATTRIBUTE_BY_NAME = {
	MegaExplosion = "MegaExplosionCharges",
	Shield = "ShieldCharges",
	NukeBooster = "NukeBoosterCharges",
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
local shieldCharacterConnections: {[Player]: RBXScriptConnection} = {}

local function resolveOfferKey(offerKey: string): string
	if offerKey == "EarlyGame" then
		return "StarterPack"
	end
	if offerKey == "CrowdedServer" then
		return "NukeBooster"
	end

	return offerKey
end

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

local function getRequestUseBoosterChargeEvent(): RemoteEvent
	if requestUseBoosterChargeEvent and requestUseBoosterChargeEvent.Parent then
		return requestUseBoosterChargeEvent
	end

	requestUseBoosterChargeEvent = ensureRemoteEvent("RequestUseBoosterCharge")
	return requestUseBoosterChargeEvent
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

local function ensureBoosterChargeData(profile): {[string]: number}?
	if not profile or type(profile.Data) ~= "table" then
		return nil
	end

	if type(profile.Data.BoosterCharges) ~= "table" then
		profile.Data.BoosterCharges = {
			MegaExplosion = 0,
			Shield = 0,
			NukeBooster = 0,
		}
	end

	local charges = profile.Data.BoosterCharges
	for boosterName in pairs(BOOSTER_CHARGE_ATTRIBUTE_BY_NAME) do
		charges[boosterName] = math.max(0, math.floor(tonumber(charges[boosterName]) or 0))
	end
	return charges
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

local function getBoosterChargeCount(player: Player, boosterName: string): number
	if not BOOSTER_CHARGE_ATTRIBUTE_BY_NAME[boosterName] then
		return 0
	end

	local profile = getProfile(player)
	local charges = profile and ensureBoosterChargeData(profile)
	if not charges then
		return 0
	end

	return math.max(0, math.floor(tonumber(charges[boosterName]) or 0))
end

local function syncBoosterChargeAttribute(player: Player, boosterName: string)
	local attributeName = BOOSTER_CHARGE_ATTRIBUTE_BY_NAME[boosterName]
	if not attributeName then
		return
	end

	player:SetAttribute(attributeName, getBoosterChargeCount(player, boosterName))
end

local function consumeBoosterCharge(player: Player, boosterName: string): boolean
	local profile = getProfile(player)
	local charges = profile and ensureBoosterChargeData(profile)
	if not charges or getBoosterChargeCount(player, boosterName) <= 0 then
		return false
	end

	charges[boosterName] = math.max(0, math.floor(tonumber(charges[boosterName]) or 0) - 1)
	syncBoosterChargeAttribute(player, boosterName)
	return true
end

local function fireNotification(player: Player, message: string, notificationType: string)
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local notificationEvent = eventsFolder and eventsFolder:FindFirstChild("ShowNotification")
	if notificationEvent and notificationEvent:IsA("RemoteEvent") then
		notificationEvent:FireClient(player, message, notificationType)
	end
end

local function removeShieldForceField(character: Model?)
	if not character then
		return
	end

	local existing = character:FindFirstChild(SHIELD_FORCE_FIELD_NAME)
	if existing and existing:IsA("ForceField") then
		existing:Destroy()
	end
end

local function syncShieldForceField(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local shieldActive = getBoosterEndsAt(player, "Shield") > 0
	if not shieldActive then
		removeShieldForceField(character)
		return
	end

	local existing = character:FindFirstChild(SHIELD_FORCE_FIELD_NAME)
	if existing and existing:IsA("ForceField") then
		existing.Visible = true
		return
	end

	local forceField = Instance.new("ForceField")
	forceField.Name = SHIELD_FORCE_FIELD_NAME
	forceField.Visible = true
	forceField.Parent = character
end

local function bindShieldCharacterSync(player: Player)
	if shieldCharacterConnections[player] then
		return
	end

	shieldCharacterConnections[player] = player.CharacterAdded:Connect(function()
		task.defer(function()
			if player.Parent then
				syncShieldForceField(player)
			end
		end)
	end)
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
	local analyticsPayload = payload or {}
	analyticsPayload.ResolvedOfferKey = resolveOfferKey(offerKey)
	AnalyticsFunnelsService:HandleContextualOfferShown(player, offerKey, analyticsPayload)
	getShowContextualOfferEvent():FireClient(player, offerKey, analyticsPayload)
end

local function hasGamePassAttribute(player: Player, attributeName: string): boolean
	return player:GetAttribute(attributeName) == true
end

local function isInsideZonePart(zonePart: BasePart, position: Vector3): boolean
	local relativePos = zonePart.CFrame:PointToObjectSpace(position)
	local size = zonePart.Size

	return math.abs(relativePos.X) <= size.X * 0.5
		and math.abs(relativePos.Y) <= size.Y * 0.5
		and math.abs(relativePos.Z) <= size.Z * 0.5
end

local function isPlayerInMineZone(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end

	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then
		return false
	end

	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" and isInsideZonePart(zonePart, root.Position) then
			return true
		end
	end

	return false
end

local function isAutoBombBlockedBySession(): boolean
	return Workspace:GetAttribute("SessionEnded") == true
		or Workspace:GetAttribute("TerrainResetInProgress") == true
end

local function setAutoBombEnabled(player: Player, active: boolean)
	local nextValue = active
		and not isAutoBombBlockedBySession()
		and hasGamePassAttribute(player, "HasAutoBomb")
		and isPlayerInMineZone(player)
	player:SetAttribute("AutoBombEnabled", nextValue)
end

local function enforceAutoBombZoneState(player: Player): boolean
	if player:GetAttribute("AutoBombEnabled") ~= true then
		return false
	end

	if isAutoBombBlockedBySession()
		or not hasGamePassAttribute(player, "HasAutoBomb")
		or not isPlayerInMineZone(player)
	then
		player:SetAttribute("AutoBombEnabled", false)
		return false
	end

	return true
end

function BoosterService:GetTimedBoosterEndsAt(player: Player, boosterName: string): number
	return getBoosterEndsAt(player, boosterName)
end

function BoosterService:GetBoosterChargeCount(player: Player, boosterName: string): number
	return getBoosterChargeCount(player, boosterName)
end

function BoosterService:AddBoosterCharges(player: Player, chargesByName: {[string]: any}, _source: string?): boolean
	if type(chargesByName) ~= "table" then
		return false
	end

	local profile = getProfile(player)
	local charges = profile and ensureBoosterChargeData(profile)
	if not charges then
		return false
	end

	local changed = false
	for boosterName, amount in pairs(chargesByName) do
		if BOOSTER_CHARGE_ATTRIBUTE_BY_NAME[boosterName] then
			local increment = math.max(0, math.floor(tonumber(amount) or 0))
			if increment > 0 then
				charges[boosterName] = math.max(0, math.floor(tonumber(charges[boosterName]) or 0)) + increment
				syncBoosterChargeAttribute(player, boosterName)
				changed = true
			end
		end
	end

	return changed
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
	if boosterName == "Shield" then
		syncShieldForceField(player)
	end
	return endsAt
end

function BoosterService:UseBoosterCharge(player: Player, boosterName: string): boolean
	if not BOOSTER_CHARGE_ATTRIBUTE_BY_NAME[boosterName] then
		return false
	end

	if getBoosterChargeCount(player, boosterName) <= 0 then
		fireNotification(player, "No booster charges available.", "Error")
		return false
	end

	local config = getBoosterConfig(boosterName)
	local displayName = if type(config) == "table" and type(config.DisplayName) == "string" then config.DisplayName else boosterName

	if boosterName == "MegaExplosion" or boosterName == "Shield" then
		if getBoosterEndsAt(player, boosterName) > 0 then
			fireNotification(player, displayName .. " is already active.", "Error")
			return false
		end

		local endsAt = self:ActivateTimedBooster(player, boosterName)
		if endsAt <= 0 then
			fireNotification(player, "Failed to activate " .. displayName .. ".", "Error")
			return false
		end

		if not consumeBoosterCharge(player, boosterName) then
			return false
		end

		fireNotification(player, displayName .. " activated for 10 minutes!", "Success")
		return true
	end

	if boosterName == "NukeBooster" then
		local didDetonate = self:TriggerNukeBooster(player)
		if not didDetonate then
			fireNotification(player, "Nuke failed: enter mining zone", "Error")
			return false
		end

		if not consumeBoosterCharge(player, boosterName) then
			return false
		end

		fireNotification(player, "Nuke detonated!", "Success")
		return true
	end

	return false
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
	return player:GetAttribute("AutoBombEnabled") == true
		and not isAutoBombBlockedBySession()
		and self:HasAutoBomb(player)
		and isPlayerInMineZone(player)
end

function BoosterService:SetAutoBombEnabled(player: Player, active: boolean)
	setAutoBombEnabled(player, active)
end

function BoosterService:SyncPlayer(player: Player)
	syncBoosterAttribute(player, "MegaExplosion")
	syncBoosterAttribute(player, "Shield")
	syncShieldForceField(player)
	syncBoosterChargeAttribute(player, "MegaExplosion")
	syncBoosterChargeAttribute(player, "Shield")
	syncBoosterChargeAttribute(player, "NukeBooster")
	player:SetAttribute("HasAutoBomb", player:GetAttribute("HasAutoBomb") == true)
	player:SetAttribute("AutoBombEnabled", player:GetAttribute("AutoBombEnabled") == true and player:GetAttribute("HasAutoBomb") == true)
	enforceAutoBombZoneState(player)
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
			local sessionBlocked = isAutoBombBlockedBySession()
			for _, player in ipairs(Players:GetPlayers()) do
				syncShieldForceField(player)

				if sessionBlocked and player:GetAttribute("AutoBombEnabled") == true then
					player:SetAttribute("AutoBombEnabled", false)
				end

				if enforceAutoBombZoneState(player) and BoosterService:IsAutoBombEnabled(player) then
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
		AnalyticsFunnelsService:HandleAutoBombToggleSuccess(player, nil, player:GetAttribute("AutoBombEnabled") == true)
	end)

	local useBoosterChargeEvent = getRequestUseBoosterChargeEvent()
	useBoosterChargeEvent.OnServerEvent:Connect(function(player, boosterName)
		if type(boosterName) ~= "string" then
			return
		end

		BoosterService:UseBoosterCharge(player, boosterName)
	end)
end

function BoosterService:Start()
	startAutoBombHeartbeat()

	for _, player in ipairs(Players:GetPlayers()) do
		bindShieldCharacterSync(player)
		self:SyncPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		bindShieldCharacterSync(player)
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
		if shieldCharacterConnections[player] then
			shieldCharacterConnections[player]:Disconnect()
			shieldCharacterConnections[player] = nil
		end
	end)
end

return BoosterService
