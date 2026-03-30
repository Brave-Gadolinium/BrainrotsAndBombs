--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local SlotUnlockConfigurations = require(ReplicatedStorage.Modules.SlotUnlockConfigurations)
local QuestChainConfiguration = require(ReplicatedStorage.Modules.QuestChainConfiguration)
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)

type QuestDefinition = {
	Id: string,
	Order: number,
	Type: string,
	Target: number,
	Text: string,
	Reward: number,
}

type QuestState = {
	id: string,
	order: number,
	questType: string,
	uiText: string,
	targetValue: number,
	currentProgress: number,
	rawProgress: number,
	rewardValue: number,
	isCompleted: boolean,
	isClaimed: boolean,
}

local QuestChainService = {}

local PlayerController
local stateSignatures: {[Player]: string} = {}
local playerConnections: {[Player]: {RBXScriptConnection}} = {}
local remotesFolder: Folder? = nil
local getStateRemote: RemoteFunction? = nil
local claimQuestRemote: RemoteFunction? = nil
local stateUpdatedRemote: RemoteEvent? = nil

local function isEnabled(): boolean
	return QuestChainConfiguration.Enabled ~= false
end

local function getActiveSlots(): number
	return math.max(1, tonumber(QuestChainConfiguration.ActiveSlots) or 3)
end

local function getQuestList(): {QuestDefinition}
	local quests = table.clone(QuestChainConfiguration.Quests or {})
	table.sort(quests, function(a: QuestDefinition, b: QuestDefinition)
		return a.Order < b.Order
	end)
	return quests
end

local function getNotificationRemote(): RemoteEvent?
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local remote = eventsFolder and eventsFolder:FindFirstChild("ShowNotification")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

local function ensureQuestData(profile)
	if type(profile.Data.QuestChain) ~= "table" then
		profile.Data.QuestChain = {}
	end

	local questData = profile.Data.QuestChain
	if type(questData.Claimed) ~= "table" then
		questData.Claimed = {}
	end

	return questData
end

local function getProfile(player: Player)
	return PlayerController and PlayerController:GetProfile(player) or nil
end

local function getBestBombTier(profile): number
	local ownedPickaxes = profile.Data.OwnedPickaxes
	if type(ownedPickaxes) ~= "table" then
		return 1
	end

	local bestTier = 1

	for bombName, isOwned in pairs(ownedPickaxes) do
		if isOwned == true and BombsConfigurations.Bombs[bombName] then
			local tier = tonumber(string.match(bombName, "(%d+)")) or 1
			if tier > bestTier then
				bestTier = tier
			end
		end
	end

	return bestTier
end

local function getCurrentDepthLevel(player: Player): number
	local minesFolder = Workspace:FindFirstChild("Mines")
	if not minesFolder then
		return 0
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return 0
	end

	local highestLevel = 0
	for _, child in ipairs(minesFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local zoneLevel = tonumber(string.match(child.Name, "^Zone(%d+)$"))
			if zoneLevel then
				local relativePos = child.CFrame:PointToObjectSpace(root.Position)
				local halfSize = child.Size * 0.5
				local inside = math.abs(relativePos.X) <= halfSize.X
					and math.abs(relativePos.Y) <= halfSize.Y
					and math.abs(relativePos.Z) <= halfSize.Z

				if inside and zoneLevel > highestLevel then
					highestLevel = zoneLevel
				end
			end
		end
	end

	return highestLevel
end

local function getMaxDepthLevelReached(player: Player, profile): number
	local storedDepthLevel = math.max(0, tonumber(profile.Data.MaxDepthLevelReached) or 0)
	local currentDepthLevel = getCurrentDepthLevel(player)
	local bestDepthLevel = math.max(storedDepthLevel, currentDepthLevel)

	if bestDepthLevel ~= storedDepthLevel then
		profile.Data.MaxDepthLevelReached = bestDepthLevel
	end

	player:SetAttribute("MaxDepthLevelReached", bestDepthLevel)
	return bestDepthLevel
end

local function getSlotUpgradeProgress(profile): number
	local unlockedSlots = tonumber(profile.Data.unlocked_slots) or SlotUnlockConfigurations.StartSlots
	return math.max(
		0,
		math.floor((unlockedSlots - SlotUnlockConfigurations.StartSlots) / SlotUnlockConfigurations.SlotsPerUpgrade)
	)
end

local function getProgress(player: Player, profile, questType: string): number
	if questType == "total_money_earned" then
		return math.max(0, tonumber(profile.Data.TotalMoneyEarned) or tonumber(profile.Data.Money) or 0)
	end

	if questType == "collect_money_total" then
		return math.max(0, tonumber(profile.Data.TotalMoneyEarned) or tonumber(profile.Data.Money) or 0)
	end

	if questType == "playtime_minutes_total" then
		return math.floor(math.max(0, tonumber(profile.Data.TimePlayed) or 0) / 60)
	end

	if questType == "brainrots_collected_total" then
		return math.max(0, tonumber(profile.Data.TotalBrainrotsCollected) or 0)
	end

	if questType == "collect_brainrots_total" then
		return math.max(0, tonumber(profile.Data.TotalBrainrotsCollected) or 0)
	end

	if questType == "place_brainrots_total" then
		return math.max(0, tonumber(profile.Data.TotalBrainrotsCollected) or 0)
	end

	if questType == "rebirth_count" then
		return math.max(0, tonumber(profile.Data.Rebirths) or 0)
	end

	if questType == "walk_speed_upgrade_count" then
		return math.max(0, tonumber(profile.Data.BonusSpeed) or 0)
	end

	if questType == "speed_upgrade_count" then
		return math.max(0, tonumber(profile.Data.BonusSpeed) or 0)
	end

	if questType == "carry_capacity_upgrade_count" then
		return math.max(0, tonumber(profile.Data.CarryCapacity) or 0)
	end

	if questType == "carry_upgrade_count" then
		return math.max(0, tonumber(profile.Data.CarryCapacity) or 0)
	end

	if questType == "slot_upgrade_count" then
		return getSlotUpgradeProgress(profile)
	end

	if questType == "base_upgrade_count" then
		return getSlotUpgradeProgress(profile)
	end

	if questType == "bomb_upgrade_count" then
		return math.max(0, getBestBombTier(profile) - 1)
	end

	if questType == "reach_depth" then
		return getMaxDepthLevelReached(player, profile)
	end

	return 0
end

local function buildQuestState(player: Player, quest: QuestDefinition): QuestState?
	local profile = getProfile(player)
	if not profile then
		return nil
	end

	local questData = ensureQuestData(profile)
	local rawProgress = getProgress(player, profile, quest.Type)
	local targetValue = math.max(1, tonumber(quest.Target) or 1)

	return {
		id = quest.Id,
		order = quest.Order,
		questType = quest.Type,
		uiText = quest.Text,
		targetValue = targetValue,
		currentProgress = math.clamp(rawProgress, 0, targetValue),
		rawProgress = rawProgress,
		rewardValue = math.max(0, tonumber(quest.Reward) or 0),
		isCompleted = rawProgress >= targetValue,
		isClaimed = questData.Claimed[quest.Id] == true,
	}
end

local function serializeState(state): string
	local pieces = {
		tostring(state.enabled),
		tostring(state.activeSlots),
	}

	for _, questState in ipairs(state.active) do
		table.insert(
			pieces,
			table.concat({
				questState.id,
				tostring(questState.currentProgress),
				tostring(questState.rawProgress),
				tostring(questState.isCompleted),
				tostring(questState.isClaimed),
			}, ":")
		)
	end

	return table.concat(pieces, "|")
end

function QuestChainService:GetPlayerState(player: Player)
	if not isEnabled() then
		return {
			enabled = false,
			activeSlots = 0,
			active = {},
			all = {},
		}
	end

	local profile = getProfile(player)
	if not profile then
		return nil
	end

	local questData = ensureQuestData(profile)
	local allStates = {}
	local activeStates = {}

	for _, quest in ipairs(getQuestList()) do
		local questState = buildQuestState(player, quest)
		if questState then
			table.insert(allStates, questState)

			if not questState.isClaimed and #activeStates < getActiveSlots() then
				table.insert(activeStates, questState)
			end
		end
	end

	return {
		enabled = true,
		activeSlots = getActiveSlots(),
		active = activeStates,
		all = allStates,
		claimed = questData.Claimed,
	}
end

function QuestChainService:RefreshPlayer(player: Player)
	local state = self:GetPlayerState(player)
	if not state then
		return nil
	end

	local signature = serializeState(state)
	if signature ~= stateSignatures[player] then
		stateSignatures[player] = signature
		if stateUpdatedRemote then
			stateUpdatedRemote:FireClient(player, state)
		end
	end

	return state
end

function QuestChainService:ClaimQuest(player: Player, questId: string)
	local profile = getProfile(player)
	if not profile then
		return {
			Success = false,
			Error = "NO_PROFILE",
		}
	end

	local questData = ensureQuestData(profile)
	local targetQuest: QuestDefinition? = nil

	for _, quest in ipairs(getQuestList()) do
		if quest.Id == questId then
			targetQuest = quest
			break
		end
	end

	if not targetQuest then
		return {
			Success = false,
			Error = "UNKNOWN_QUEST",
		}
	end

	local questState = buildQuestState(player, targetQuest)
	if not questState then
		return {
			Success = false,
			Error = "NO_STATE",
		}
	end

	if questState.isClaimed then
		return {
			Success = false,
			Error = "ALREADY_CLAIMED",
			State = self:GetPlayerState(player),
		}
	end

	if not questState.isCompleted then
		return {
			Success = false,
			Error = "NOT_COMPLETED",
			State = self:GetPlayerState(player),
		}
	end

	questData.Claimed[questId] = true
	PlayerController:AddMoney(player, questState.rewardValue)

	local notificationRemote = getNotificationRemote()
	if notificationRemote then
		notificationRemote:FireClient(
			player,
			("Quest complete! Claimed $" .. NumberFormatter.Format(questState.rewardValue)),
			"Success"
		)
	end

	return {
		Success = true,
		State = self:RefreshPlayer(player),
	}
end

local function disconnectPlayer(player: Player)
	local connections = playerConnections[player]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	playerConnections[player] = nil
	stateSignatures[player] = nil
end

local function bindPlayer(player: Player)
	disconnectPlayer(player)

	local profile = getProfile(player)
	if not profile then
		return
	end

	ensureQuestData(profile)

	local connections = {}
	playerConnections[player] = connections

	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
	if moneyValue and moneyValue:IsA("NumberValue") then
		table.insert(connections, moneyValue.Changed:Connect(function()
			QuestChainService:RefreshPlayer(player)
		end))
	end

	for _, attributeName in ipairs({
		"TimePlayed",
		"TotalMoneyEarned",
		"TotalBrainrotsCollected",
		"MaxDepthLevelReached",
		"Rebirths",
		"UnlockedSlots",
		"BonusSpeed",
		"CarryCapacity",
	}) do
		table.insert(connections, player:GetAttributeChangedSignal(attributeName):Connect(function()
			QuestChainService:RefreshPlayer(player)
		end))
	end

	QuestChainService:RefreshPlayer(player)
end

local function waitForProfileAndBind(player: Player)
	task.spawn(function()
		local retries = 0
		while player.Parent == Players and not getProfile(player) and retries < 120 do
			retries += 1
			task.wait(0.5)
		end

		if player.Parent == Players and getProfile(player) then
			bindPlayer(player)
		end
	end)
end

function QuestChainService:Init(controllers)
	PlayerController = controllers.PlayerController

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	remotesFolder = remotes:FindFirstChild("QuestChain") :: Folder?
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "QuestChain"
		remotesFolder.Parent = remotes
	end

	getStateRemote = remotesFolder:FindFirstChild("GetState") :: RemoteFunction?
	if not getStateRemote then
		getStateRemote = Instance.new("RemoteFunction")
		getStateRemote.Name = "GetState"
		getStateRemote.Parent = remotesFolder
	end

	claimQuestRemote = remotesFolder:FindFirstChild("ClaimQuest") :: RemoteFunction?
	if not claimQuestRemote then
		claimQuestRemote = Instance.new("RemoteFunction")
		claimQuestRemote.Name = "ClaimQuest"
		claimQuestRemote.Parent = remotesFolder
	end

	stateUpdatedRemote = remotesFolder:FindFirstChild("StateUpdated") :: RemoteEvent?
	if not stateUpdatedRemote then
		stateUpdatedRemote = Instance.new("RemoteEvent")
		stateUpdatedRemote.Name = "StateUpdated"
		stateUpdatedRemote.Parent = remotesFolder
	end

	getStateRemote.OnServerInvoke = function(player)
		return self:GetPlayerState(player)
	end

	claimQuestRemote.OnServerInvoke = function(player, questId: string)
		return self:ClaimQuest(player, questId)
	end
end

function QuestChainService:Start()
	Players.PlayerAdded:Connect(waitForProfileAndBind)
	Players.PlayerRemoving:Connect(disconnectPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		waitForProfileAndBind(player)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				if getProfile(player) then
					self:RefreshPlayer(player)
				end
			end
		end
	end)
end

return QuestChainService
