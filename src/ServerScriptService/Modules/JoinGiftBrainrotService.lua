--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local JoinGiftBrainrotConfiguration = require(ReplicatedStorage.Modules.JoinGiftBrainrotConfiguration)
local TutorialService = require(ServerScriptService.Modules.TutorialService)

type PendingGiftState = {
	Token: string,
	ItemName: string,
	Mutation: string,
	Rarity: string,
	Level: number,
	PreviewShownAt: number?,
	PreviewPosition: Vector3?,
	AutoClaimNonce: number,
	IsClaiming: boolean,
}

local JoinGiftBrainrotService = {}

local PlayerController
local CarrySystem

local remotesFolder: Folder
local getStateRemote: RemoteFunction
local markPreviewShownRemote: RemoteEvent
local requestPickupRemote: RemoteFunction
local stateUpdatedRemote: RemoteEvent

local pendingStates: {[Player]: PendingGiftState} = {}
local randomObject = Random.new()
local started = false
local PROFILE_LOAD_TIMEOUT_SECONDS = 30
local TUTORIAL_SPECIAL_BRAINROT_GRANTED_KEY = "TutorialSpecialBrainrotGranted"

local function getJoinGiftRemotes(): Folder
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("JoinGiftBrainrot") :: Folder
end

local function getAliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

local function getAliveRootPart(player: Player): BasePart?
	local humanoid = getAliveHumanoid(player)
	local character = humanoid and humanoid.Parent
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function isInsideAnyMineZone(position: Vector3): boolean
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then
		return false
	end

	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePosition = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size
			local isInside = math.abs(relativePosition.X) <= size.X / 2
				and math.abs(relativePosition.Y) <= size.Y / 2
				and math.abs(relativePosition.Z) <= size.Z / 2
			if isInside then
				return true
			end
		end
	end

	return false
end

local function getPlayerProfile(player: Player)
	if not PlayerController or not PlayerController.GetProfile then
		return nil
	end

	return PlayerController:GetProfile(player)
end

local function hasGrantedSpecialBrainrot(player: Player, profileOverride): boolean
	local profile = profileOverride or getPlayerProfile(player)
	local data = profile and profile.Data
	return type(data) == "table" and data[TUTORIAL_SPECIAL_BRAINROT_GRANTED_KEY] == true
end

local function markSpecialBrainrotGranted(player: Player, profileOverride)
	local profile = profileOverride or getPlayerProfile(player)
	local data = profile and profile.Data
	if type(data) ~= "table" then
		return false
	end

	data[TUTORIAL_SPECIAL_BRAINROT_GRANTED_KEY] = true
	player:SetAttribute(TUTORIAL_SPECIAL_BRAINROT_GRANTED_KEY, true)
	return true
end

local function waitForProfile(player: Player, timeoutSeconds: number?): any
	local timeout = tonumber(timeoutSeconds)
	local deadline = if type(timeout) == "number" and timeout > 0 then os.clock() + timeout else math.huge

	while player.Parent do
		local profile = getPlayerProfile(player)
		if profile then
			return profile
		end

		if os.clock() >= deadline then
			return nil
		end

		task.wait(0.1)
	end

	return nil
end

local function chooseRandomGiftItem(): string?
	local rarity = tostring(JoinGiftBrainrotConfiguration.Rarity or "Legendary")
	local items = ItemConfigurations.GetItemsByRarity(rarity)
	if #items <= 0 then
		return nil
	end

	return items[randomObject:NextInteger(1, #items)]
end

local function fireStateUpdated(player: Player, status: string, token: string?)
	if stateUpdatedRemote then
		stateUpdatedRemote:FireClient(player, {
			status = status,
			token = token,
		})
	end
end

local function getPublicStateForPlayer(player: Player)
	if JoinGiftBrainrotConfiguration.Enabled ~= true then
		return nil
	end

	if hasGrantedSpecialBrainrot(player) then
		clearPendingState(player, false)
		return nil
	end

	local state = pendingStates[player]
	if not state then
		return nil
	end

	return {
		Token = state.Token,
		ItemName = state.ItemName,
		Mutation = state.Mutation,
		Rarity = state.Rarity,
		Level = state.Level,
		ServerNow = Workspace:GetServerTimeNow(),
	}
end

local function clearPendingState(player: Player, shouldNotifyClient: boolean?, status: string?)
	local previousState = pendingStates[player]
	pendingStates[player] = nil

	if shouldNotifyClient == true and previousState then
		fireStateUpdated(player, status or "cancelled", previousState.Token)
	end
end

local function armGiftForPlayer(player: Player, shouldNotifyClient: boolean?): (boolean, string)
	if JoinGiftBrainrotConfiguration.Enabled ~= true then
		clearPendingState(player, shouldNotifyClient, "cancelled")
		return false, "Join gift is disabled."
	end

	local profile = getPlayerProfile(player)
	if profile and hasGrantedSpecialBrainrot(player, profile) then
		clearPendingState(player, shouldNotifyClient, "cancelled")
		return false, "Special tutorial brainrot was already granted."
	end

	local itemName = chooseRandomGiftItem()
	if not itemName then
		clearPendingState(player, shouldNotifyClient, "cancelled")
		return false, "No legendary brainrots are configured."
	end

	local itemData = ItemConfigurations.GetItemData(itemName)
	local rarity = itemData and itemData.Rarity or tostring(JoinGiftBrainrotConfiguration.Rarity or "Legendary")
	local state: PendingGiftState = {
		Token = HttpService:GenerateGUID(false),
		ItemName = itemName,
		Mutation = tostring(JoinGiftBrainrotConfiguration.Mutation or "Normal"),
		Rarity = rarity,
		Level = math.max(1, math.floor(tonumber(JoinGiftBrainrotConfiguration.Level) or 1)),
		AutoClaimNonce = 0,
		IsClaiming = false,
	}

	pendingStates[player] = state
	if shouldNotifyClient == true then
		fireStateUpdated(player, "rearm", state.Token)
	end

	return true, `Armed join gift: {itemName}.`
end

local function grantPendingGift(player: Player, state: PendingGiftState, _source: string): {Success: boolean, Error: string?}
	if not PlayerController then
		return {Success = false, Error = "DependenciesMissing"}
	end
	if not CarrySystem then
		CarrySystem = require(ServerScriptService.Modules.CarrySystem)
	end

	local profile = getPlayerProfile(player)
	if not profile then
		return {Success = false, Error = "ProfileNotLoaded"}
	end
	if hasGrantedSpecialBrainrot(player, profile) then
		return {Success = false, Error = "AlreadyGranted"}
	end

	local rootPart = getAliveRootPart(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not rootPart or not head or not head:IsA("BasePart") then
		return {Success = false, Error = "CharacterUnavailable"}
	end

	local isInMineZone = isInsideAnyMineZone(rootPart.Position)
	if not isInMineZone and CarrySystem.DeliverCarriedItems then
		CarrySystem.DeliverCarriedItems(player)
	end

	if not CarrySystem.CanCarryMore(player) then
		return {Success = false, Error = "CarryLimitReached"}
	end

	local pickedUp = CarrySystem.AddItemToCarry(
		player,
		state.ItemName,
		state.Mutation,
		state.Rarity,
		nil,
		{
			Level = state.Level,
		}
	)
	if not pickedUp then
		return {Success = false, Error = "CarryGrantFailed"}
	end

	markSpecialBrainrotGranted(player, profile)

	TutorialService:HandleBrainrotPickedUp(player, true)
	AnalyticsFunnelsService:HandleMineBrainrotPickedUp(player)

	if not isInMineZone and CarrySystem.DeliverCarriedItems then
		CarrySystem.DeliverCarriedItems(player)
	end

	return {Success = true}
end

local function tryClaimGift(player: Player, token: string, source: string): {Success: boolean, Error: string?}
	local state = pendingStates[player]
	if not state or state.Token ~= token then
		return {Success = false, Error = "NoPendingState"}
	end

	if state.IsClaiming then
		return {Success = false, Error = "AlreadyProcessing"}
	end

	state.IsClaiming = true
	local grantResult = grantPendingGift(player, state, source)
	state.IsClaiming = false

	if not grantResult.Success then
		return grantResult
	end

	pendingStates[player] = nil
	fireStateUpdated(player, "claimed", token)
	return grantResult
end

local function validateManualPickup(player: Player, state: PendingGiftState, token: string): (boolean, string?)
	if state.Token ~= token then
		return false, "TokenMismatch"
	end

	local rootPart = getAliveRootPart(player)
	if not rootPart then
		return false, "CharacterUnavailable"
	end

	if state.PreviewShownAt == nil or state.PreviewPosition == nil then
		return false, "PreviewNotShown"
	end

	local allowedDistance = math.max(
		1,
		tonumber(JoinGiftBrainrotConfiguration.PreviewMaxActivationDistance) or 12
	) + math.max(0, tonumber(JoinGiftBrainrotConfiguration.PickupDistanceTolerance) or 0)
	local distance = (rootPart.Position - state.PreviewPosition).Magnitude
	if distance > allowedDistance then
		return false, "TooFar"
	end

	return true, nil
end

local function handlePreviewShown(player: Player, token: any, previewPosition: any)
	if hasGrantedSpecialBrainrot(player) then
		clearPendingState(player, true, "cancelled")
		return
	end

	local state = pendingStates[player]
	if not state or type(token) ~= "string" or state.Token ~= token then
		return
	end

	if typeof(previewPosition) ~= "Vector3" then
		return
	end

	state.PreviewShownAt = Workspace:GetServerTimeNow()
	state.PreviewPosition = previewPosition
	state.AutoClaimNonce += 1
	local autoClaimNonce = state.AutoClaimNonce

	task.delay(math.max(0, tonumber(JoinGiftBrainrotConfiguration.AutoPickupDelaySeconds) or 0), function()
		if not player.Parent then
			return
		end

		local latestState = pendingStates[player]
		if latestState ~= state or latestState.Token ~= token or latestState.AutoClaimNonce ~= autoClaimNonce then
			return
		end

		tryClaimGift(player, token, "auto")
	end)
end

function JoinGiftBrainrotService:GetStateForPlayer(player: Player)
	return getPublicStateForPlayer(player)
end

function JoinGiftBrainrotService:HandlePickupRequest(player: Player, token: string)
	if type(token) ~= "string" or token == "" then
		return {
			Success = false,
			Error = "InvalidToken",
		}
	end

	local state = pendingStates[player]
	if not state then
		return {
			Success = false,
			Error = "NoPendingState",
		}
	end
	if hasGrantedSpecialBrainrot(player) then
		clearPendingState(player, true, "cancelled")
		return {
			Success = false,
			Error = "AlreadyGranted",
		}
	end

	local isValid, validationError = validateManualPickup(player, state, token)
	if not isValid then
		return {
			Success = false,
			Error = validationError,
		}
	end

	local result = tryClaimGift(player, token, "manual")
	return {
		Success = result.Success,
		Error = result.Error,
	}
end

function JoinGiftBrainrotService:ForceRearmForTesting(player: Player): (boolean, string)
	if not player or not player:IsA("Player") then
		return false, "Player is required."
	end

	return armGiftForPlayer(player, true)
end

function JoinGiftBrainrotService:Init(controllers)
	PlayerController = controllers.PlayerController

	remotesFolder = getJoinGiftRemotes()
	getStateRemote = remotesFolder:WaitForChild("GetState") :: RemoteFunction
	markPreviewShownRemote = remotesFolder:WaitForChild("MarkPreviewShown") :: RemoteEvent
	requestPickupRemote = remotesFolder:WaitForChild("RequestPickup") :: RemoteFunction
	stateUpdatedRemote = remotesFolder:WaitForChild("StateUpdated") :: RemoteEvent

	getStateRemote.OnServerInvoke = function(player)
		return self:GetStateForPlayer(player)
	end

	markPreviewShownRemote.OnServerEvent:Connect(function(player, token, previewPosition)
		handlePreviewShown(player, token, previewPosition)
	end)

	requestPickupRemote.OnServerInvoke = function(player, token)
		return self:HandlePickupRequest(player, token)
	end

	Players.PlayerRemoving:Connect(function(player)
		pendingStates[player] = nil
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local profile = waitForProfile(player, PROFILE_LOAD_TIMEOUT_SECONDS)
			if not profile or not player.Parent then
				return
			end
			if hasGrantedSpecialBrainrot(player, profile) then
				clearPendingState(player, false, "cancelled")
				return
			end
			armGiftForPlayer(player, false)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			local profile = waitForProfile(player, PROFILE_LOAD_TIMEOUT_SECONDS)
			if not profile or not player.Parent then
				return
			end
			if hasGrantedSpecialBrainrot(player, profile) then
				clearPendingState(player, false, "cancelled")
				return
			end
			armGiftForPlayer(player, false)
		end)
	end
end

function JoinGiftBrainrotService:Start()
	if started then
		return
	end

	started = true
end

return JoinGiftBrainrotService
