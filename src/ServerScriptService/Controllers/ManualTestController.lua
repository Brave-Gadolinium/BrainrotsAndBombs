--!strict
-- LOCATION: ServerScriptService/Controllers/ManualTestController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ManualTestAccessConfiguration = require(ServerScriptService.Modules.ManualTestAccessConfiguration)
local DailyRewardManager = require(ServerScriptService.Modules.DailyRewardManager)
local PlaytimeRewardManager = require(ServerScriptService.Modules.PlaytimeRewardManager)
local CarrySystem = require(ServerScriptService.Modules.CarrySystem)
local ItemManager = require(ServerScriptService.Modules.ItemManager)
local QuestChainService = require(ServerScriptService.Modules.QuestChainService)
local SlotManager = require(ServerScriptService.Modules.SlotManager)
local UpgradesSystem = require(ServerScriptService.Modules.UpgradesSystem)
local RebirthSystem = require(ServerScriptService.Modules.RebirthSystem)
local PlotRuntimeBridge = require(ServerScriptService.Modules.PlotRuntimeBridge)
local SpawnUtils = require(ServerScriptService.Modules.SpawnUtils)
local TutorialService = require(ServerScriptService.Modules.TutorialService)

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local LuckyBlockConfiguration = require(ReplicatedStorage.Modules.LuckyBlockConfiguration)
local SlotUnlockConfigurations = require(ReplicatedStorage.Modules.SlotUnlockConfigurations)
local DailyRewardConfiguration = require(ReplicatedStorage.Modules.DailyRewardConfiguration)
local PlaytimeRewardConfiguration = require(ReplicatedStorage.Modules.PlaytimeRewardConfiguration)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)
local PostTutorialConfiguration = require(ReplicatedStorage.Modules.PostTutorialConfiguration)
local QuestChainConfiguration = require(ReplicatedStorage.Modules.QuestChainConfiguration)
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local Constants = require(ReplicatedStorage.Modules.Constants)
local DailySpinConfiguration = require(ReplicatedStorage.Modules.DailySpinConfiguration)

local ManualTestController = {}

local PlayerController
local PickaxeController
local DailyRewardController
local PlaytimeRewardController

local eventsFolder: Folder? = nil
local remotesFolder: Folder? = nil
local getBootstrapRemote: RemoteFunction? = nil
local getTargetSnapshotRemote: RemoteFunction? = nil
local executeActionRemote: RemoteFunction? = nil

local orderedActions = {}
local actionsById = {}
local auditEntries = {}

local ACCESS_ORDER = {
	none = 0,
	tester = 1,
	admin = 2,
	studio_admin = 3,
}

local CATEGORY_ORDER = {
	["Economy"] = 1,
	["Inventory"] = 2,
	["Progression"] = 3,
	["Rewards"] = 4,
	["World / QA"] = 5,
	["Danger"] = 6,
}

local FREE_SPIN_COOLDOWN_SECONDS = math.max(0, tonumber(DailySpinConfiguration.FreeSpinCooldownSeconds) or (15 * 60))
local MAX_AUDIT_ENTRIES = math.max(10, tonumber(ManualTestAccessConfiguration.MaxAuditEntries) or 100)
local MAX_TEST_USER_ID = 10 ^ 12

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local clone = {}
	for key, childValue in pairs(value) do
		clone[deepCopy(key)] = deepCopy(childValue)
	end

	return clone
end

local function normalizeInteger(value, defaultValue: number, minValue: number?, maxValue: number?): number
	local resolved = math.floor(tonumber(value) or defaultValue)
	if minValue ~= nil then
		resolved = math.max(minValue, resolved)
	end
	if maxValue ~= nil then
		resolved = math.min(maxValue, resolved)
	end
	return resolved
end

local function normalizeString(value, defaultValue: string?): string?
	if type(value) == "string" and value ~= "" then
		return value
	end
	return defaultValue
end

local function normalizeBoolean(value, defaultValue: boolean?): boolean
	if type(value) == "boolean" then
		return value
	end
	return defaultValue == true
end

local function countDictionaryEntries(source): number
	if type(source) ~= "table" then
		return 0
	end

	local total = 0
	for _, isEnabled in pairs(source) do
		if isEnabled == true then
			total += 1
		end
	end
	return total
end

local function isAccessAtLeast(currentAccess: string, requiredAccess: string): boolean
	return (ACCESS_ORDER[currentAccess] or 0) >= (ACCESS_ORDER[requiredAccess] or 0)
end

local function normalizeAccessLevel(value): string
	if value == "tester" or value == "admin" or value == "studio_admin" then
		return value
	end
	return "none"
end

local function getProfile(player: Player)
	if not PlayerController then
		return nil
	end

	return PlayerController:GetProfile(player)
end

local function getEventsFolder(): Folder
	local resolved = eventsFolder
	if resolved and resolved.Parent then
		return resolved
	end

	local existing = ReplicatedStorage:FindFirstChild("Events")
	if existing and existing:IsA("Folder") then
		eventsFolder = existing
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = "Events"
	created.Parent = ReplicatedStorage
	eventsFolder = created
	return created
end

local function getNotificationRemote(): RemoteEvent?
	local events = getEventsFolder()
	local remote = events:FindFirstChild("ShowNotification")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

local function getUIEffectRemote(): RemoteEvent?
	local events = getEventsFolder()
	local remote = events:FindFirstChild("TriggerUIEffect")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

local function getRefreshIndexRemote(): RemoteEvent?
	local events = getEventsFolder()
	local remote = events:FindFirstChild("RefreshIndex")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

local function showNotification(player: Player, message: string, messageType: string?)
	local remote = getNotificationRemote()
	if remote then
		remote:FireClient(player, message, messageType or "Success")
	end
end

local function refreshIndex(player: Player)
	local remote = getRefreshIndexRemote()
	if remote then
		remote:FireClient(player)
	end
end

local function getConfiguredGroupId(): number?
	if ManualTestAccessConfiguration.UseCreatorGroup == true and game.CreatorType == Enum.CreatorType.Group then
		return game.CreatorId
	end

	local explicitGroupId = tonumber(ManualTestAccessConfiguration.ExplicitGroupId)
	if explicitGroupId and explicitGroupId > 0 then
		return explicitGroupId
	end

	return nil
end

local function getAccessLevel(player: Player): string
	if RunService:IsStudio() then
		return "studio_admin"
	end

	local allowedUsers = ManualTestAccessConfiguration.AllowedUsers
	if type(allowedUsers) == "table" then
		local whitelistedAccess = normalizeAccessLevel(allowedUsers[player.UserId])
		if whitelistedAccess ~= "none" then
			return whitelistedAccess
		end
	end

	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return "admin"
	end

	local groupId = getConfiguredGroupId()
	if groupId then
		local success, rank = pcall(function()
			return player:GetRankInGroup(groupId)
		end)

		if success then
			local minAdminRank = tonumber(ManualTestAccessConfiguration.MinAdminRank) or math.huge
			local minTesterRank = tonumber(ManualTestAccessConfiguration.MinTesterRank) or math.huge

			if rank >= minAdminRank then
				return "admin"
			end

			if rank >= minTesterRank then
				return "tester"
			end
		end
	end

	return "none"
end

local function getTargetPlayer(userId: number): Player?
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local function sortTargets(targets)
	table.sort(targets, function(a, b)
		if a.IsSelf ~= b.IsSelf then
			return a.IsSelf
		end
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	return targets
end

local function getAvailableTargets(executor: Player, accessLevel: string)
	local targets = {}
	if isAccessAtLeast(accessLevel, "admin") then
		for _, target in ipairs(Players:GetPlayers()) do
			table.insert(targets, {
				UserId = target.UserId,
				Name = target.Name,
				DisplayName = target.DisplayName,
				IsSelf = target == executor,
			})
		end
	else
		table.insert(targets, {
			UserId = executor.UserId,
			Name = executor.Name,
			DisplayName = executor.DisplayName,
			IsSelf = true,
		})
	end

	return sortTargets(targets)
end

local function addAuditEntry(executor: Player, target: Player?, actionId: string, success: boolean, resultMessage: string)
	table.insert(auditEntries, 1, {
		Time = os.time(),
		ExecutorUserId = executor.UserId,
		ExecutorName = executor.Name,
		TargetUserId = target and target.UserId or executor.UserId,
		TargetName = target and target.Name or executor.Name,
		ActionId = actionId,
		Success = success,
		Result = resultMessage,
	})

	while #auditEntries > MAX_AUDIT_ENTRIES do
		table.remove(auditEntries, #auditEntries)
	end
end

local function getVisibleAuditEntries(executor: Player, accessLevel: string)
	local visibleEntries = {}
	for _, entry in ipairs(auditEntries) do
		if isAccessAtLeast(accessLevel, "admin")
			or entry.ExecutorUserId == executor.UserId
			or entry.TargetUserId == executor.UserId
		then
			table.insert(visibleEntries, deepCopy(entry))
		end
	end
	return visibleEntries
end

local function buildOption(value: string, label: string, search: string?)
	return {
		value = value,
		label = label,
		search = search or string.lower(label .. " " .. value),
	}
end

local function numberInput(id: string, label: string, defaultValue: number, presets, minValue: number?, maxValue: number?)
	return {
		id = id,
		kind = "number",
		label = label,
		default = defaultValue,
		presets = presets or {},
		min = minValue,
		max = maxValue,
		placeholder = tostring(defaultValue),
	}
end

local function textInput(id: string, label: string, defaultValue: string, placeholder: string?)
	return {
		id = id,
		kind = "text",
		label = label,
		default = defaultValue,
		placeholder = placeholder or defaultValue,
	}
end

local function searchSelectInput(id: string, label: string, defaultValue: string?, options, placeholder: string?)
	return {
		id = id,
		kind = "search_select",
		label = label,
		default = defaultValue,
		options = options,
		placeholder = placeholder or "Search...",
	}
end

local function booleanInput(id: string, label: string, defaultValue: boolean)
	return {
		id = id,
		kind = "boolean",
		label = label,
		default = defaultValue,
	}
end

local function registerAction(definition)
	table.insert(orderedActions, definition)
	actionsById[definition.id] = definition
end

local function buildMutationOptions()
	local preferredOrder = { "Normal", "Golden", "Diamond", "Ruby", "Neon" }
	local seen = {}
	local options = {}

	for _, mutationName in ipairs(preferredOrder) do
		if Constants.MUTATION_MULTIPLIERS[mutationName] ~= nil then
			seen[mutationName] = true
			table.insert(options, buildOption(mutationName, mutationName))
		end
	end

	for mutationName in pairs(Constants.MUTATION_MULTIPLIERS) do
		if not seen[mutationName] then
			table.insert(options, buildOption(mutationName, mutationName))
		end
	end

	table.sort(options, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)

	return options
end

local function buildItemOptions()
	local options = {}
	for itemName, itemData in pairs(ItemConfigurations.Items) do
		local displayName = itemData.DisplayName or itemName
		table.insert(
			options,
			buildOption(
				itemName,
				`{displayName} [{itemData.Rarity}]`,
				string.lower(displayName .. " " .. itemName .. " " .. (itemData.Rarity or ""))
			)
		)
	end

	table.sort(options, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)

	return options
end

local function buildRarityOptions()
	local order = {
		Common = 1,
		Uncommon = 2,
		Rare = 3,
		Epic = 4,
		Legendary = 5,
		Mythic = 6,
		Secret = 7,
		Brainrotgod = 8,
	}

	local rarities = {}
	for _, itemData in pairs(ItemConfigurations.Items) do
		if type(itemData.Rarity) == "string" then
			rarities[itemData.Rarity] = true
		end
	end

	local options = {}
	for rarity in pairs(rarities) do
		table.insert(options, buildOption(rarity, rarity))
	end

	table.sort(options, function(a, b)
		local orderA = order[a.value] or math.huge
		local orderB = order[b.value] or math.huge
		if orderA ~= orderB then
			return orderA < orderB
		end
		return string.lower(a.label) < string.lower(b.label)
	end)

	return options
end

local function buildLuckyBlockOptions()
	local options = {}
	for blockId, blockData in pairs(LuckyBlockConfiguration.GetAllBlocks()) do
		table.insert(
			options,
			buildOption(
				blockId,
				`{blockData.DisplayName} [{blockData.Rarity}]`,
				string.lower(blockData.DisplayName .. " " .. blockId .. " " .. blockData.Rarity)
			)
		)
	end

	table.sort(options, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)

	return options
end

local function buildPickaxeOptions()
	local options = {}
	for pickaxeName, pickaxeData in pairs(BombsConfigurations.Bombs) do
		table.insert(
			options,
			buildOption(
				pickaxeName,
				`{pickaxeData.DisplayName or pickaxeName} [$${tostring(pickaxeData.Price or 0)}]`,
				string.lower((pickaxeData.DisplayName or pickaxeName) .. " " .. pickaxeName)
			)
		)
	end

	table.sort(options, function(a, b)
		local dataA = BombsConfigurations.Bombs[a.value]
		local dataB = BombsConfigurations.Bombs[b.value]
		local priceA = dataA and tonumber(dataA.Price) or 0
		local priceB = dataB and tonumber(dataB.Price) or 0
		if priceA ~= priceB then
			return priceA < priceB
		end
		return string.lower(a.label) < string.lower(b.label)
	end)

	return options
end

local function buildQuestOptions()
	local options = {}
	for _, quest in ipairs(QuestChainConfiguration.Quests or {}) do
		table.insert(
			options,
			buildOption(
				quest.Id,
				`{quest.Text} ({quest.Id})`,
				string.lower(quest.Text .. " " .. quest.Id)
			)
		)
	end

	table.sort(options, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)

	return options
end

local function buildDailyDayOptions()
	local options = {}
	for day = 1, DailyRewardConfiguration.GetMaxDay() do
		table.insert(options, buildOption(tostring(day), "Day " .. tostring(day)))
	end
	return options
end

local function buildPlaytimeRewardOptions()
	local options = {}
	for _, reward in ipairs(PlaytimeRewardConfiguration.Rewards) do
		table.insert(options, buildOption(tostring(reward.Id), `Reward #{reward.Id} [{reward.Type}]`))
	end
	return options
end

local function buildPackOptions()
	local options = {}
	for packName in pairs(ProductConfigurations.PackRewards) do
		table.insert(options, buildOption(packName, packName))
	end
	table.sort(options, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)
	return options
end

local function buildItemProductOptions()
	local options = {}
	for productName in pairs(ProductConfigurations.ItemProductRewards) do
		table.insert(options, buildOption(productName, productName))
	end
	table.sort(options, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)
	return options
end

local function buildCashProductOptions()
	local options = {}
	for productName, amount in pairs(ProductConfigurations.CashProductRewards) do
		table.insert(options, buildOption(productName, `{productName} [$${tostring(amount)}]`))
	end
	table.sort(options, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)
	return options
end

local function buildSpinProductOptions()
	return {
		buildOption("SpinsX3", "SpinsX3 (+3 spins)"),
		buildOption("SpinsX9", "SpinsX9 (+9 spins)"),
	}
end

local function buildTeleportOptions()
	return {
		buildOption("plot_spawn", "Plot Spawn"),
		buildOption("shop", "Shop"),
		buildOption("upgrader", "Upgrader"),
		buildOption("rebirth", "Rebirth"),
		buildOption("mine_zone", "Mine Zone"),
	}
end

local function buildNotificationTypeOptions()
	return {
		buildOption("Success", "Success"),
		buildOption("Error", "Error"),
	}
end

local function buildUIEffectOptions()
	return {
		buildOption("FOVPop", "FOVPop"),
	}
end

local itemOptions = buildItemOptions()
local rarityOptions = buildRarityOptions()
local mutationOptions = buildMutationOptions()
local luckyBlockOptions = buildLuckyBlockOptions()
local pickaxeOptions = buildPickaxeOptions()
local questOptions = buildQuestOptions()
local dailyDayOptions = buildDailyDayOptions()
local playtimeRewardOptions = buildPlaytimeRewardOptions()
local packOptions = buildPackOptions()
local itemProductOptions = buildItemProductOptions()
local cashProductOptions = buildCashProductOptions()
local spinProductOptions = buildSpinProductOptions()
local teleportOptions = buildTeleportOptions()
local notificationTypeOptions = buildNotificationTypeOptions()
local uiEffectOptions = buildUIEffectOptions()

local function buildAccessBadgeColor(accessLevel: string): Color3
	if accessLevel == "studio_admin" then
		return Color3.fromRGB(255, 196, 76)
	end
	if accessLevel == "admin" then
		return Color3.fromRGB(255, 127, 80)
	end
	if accessLevel == "tester" then
		return Color3.fromRGB(92, 184, 92)
	end
	return Color3.fromRGB(100, 100, 100)
end

local function getLuckyBlockCount(player: Player): number
	local total = 0
	local function scanContainer(container: Instance?)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsLuckyBlock") == true then
				total += 1
			end
		end
	end

	scanContainer(player:FindFirstChild("Backpack"))
	scanContainer(player.Character)
	scanContainer(player:FindFirstChild("StarterGear"))
	return total
end

local function buildTargetSnapshot(player: Player, executor: Player, accessLevel: string)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return nil
	end

	local ownedPickaxesCount = countDictionaryEntries(profile.Data.OwnedPickaxes)
	local luckyBlockCount = getLuckyBlockCount(player)
	local dailyStatus = DailyRewardManager.GetStatus(profile.Data)
	local playtimeStatus = PlaytimeRewardManager.GetStatus(profile.Data)
	local freeSpinRemaining = math.max(0, FREE_SPIN_COOLDOWN_SECONDS - (os.time() - (tonumber(profile.Data.LastDailySpin) or 0)))

	return {
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
		AccessLevel = accessLevel,
		AccessColor = buildAccessBadgeColor(accessLevel),
		Money = tonumber(profile.Data.Money) or 0,
		TotalMoneyEarned = tonumber(profile.Data.TotalMoneyEarned) or 0,
		Spins = tonumber(profile.Data.SpinNumber) or 0,
		LastDailySpin = tonumber(profile.Data.LastDailySpin) or 0,
		FreeSpinReady = freeSpinRemaining <= 0,
		FreeSpinRemaining = freeSpinRemaining,
		Rebirths = tonumber(profile.Data.Rebirths) or 0,
		UnlockedSlots = PlayerController and PlayerController.GetUnlockedSlots and PlayerController:GetUnlockedSlots(player) or (tonumber(profile.Data.unlocked_slots) or SlotUnlockConfigurations.StartSlots),
		EquippedPickaxe = tostring(profile.Data.EquippedPickaxe or "Bomb 1"),
		OwnedPickaxesCount = ownedPickaxesCount,
		InventoryCount = type(profile.Data.Inventory) == "table" and #profile.Data.Inventory or 0,
		LuckyBlockCount = luckyBlockCount,
		TotalBrainrotsCollected = tonumber(profile.Data.TotalBrainrotsCollected) or 0,
		TimePlayed = tonumber(profile.Data.TimePlayed) or 0,
		OnboardingStep = tonumber(profile.Data.OnboardingStep) or 1,
		PostTutorialStage = tonumber(profile.Data.PostTutorialStage) or PostTutorialConfiguration.Stages.WaitingForCharacterMoney,
		MaxDepthLevelReached = tonumber(profile.Data.MaxDepthLevelReached) or 0,
		GroupRewardClaimed = player:GetAttribute("GroupRewardClaimed") == true,
		DailyRewardClaimDay = dailyStatus.ClaimDay,
		DailyRewardCanClaim = dailyStatus.CanClaim,
		DailyRewardClaimedToday = dailyStatus.ClaimedToday,
		PlaytimeSeconds = playtimeStatus.PlaytimeSeconds,
		PlaytimeClaimableCount = #playtimeStatus.ClaimableRewardIds,
		PlaytimeNextRewardId = playtimeStatus.NextRewardId,
		PlaytimeSpeedMultiplier = playtimeStatus.SpeedMultiplier,
		AuditLog = getVisibleAuditEntries(executor, accessLevel),
	}
end

local function ensureProfileTables(target: Player)
	local profile = getProfile(target)
	if not profile or not profile.Data then
		return nil
	end

	if type(profile.Data.Inventory) ~= "table" then
		profile.Data.Inventory = {}
	end
	if type(profile.Data.DiscoveredItems) ~= "table" then
		profile.Data.DiscoveredItems = {}
	end
	if type(profile.Data.ClaimedPacks) ~= "table" then
		profile.Data.ClaimedPacks = {}
	end
	if type(profile.Data.OwnedPickaxes) ~= "table" then
		profile.Data.OwnedPickaxes = { ["Bomb 1"] = true }
	end
	if type(profile.Data.QuestChain) ~= "table" then
		profile.Data.QuestChain = { Claimed = {} }
	elseif type(profile.Data.QuestChain.Claimed) ~= "table" then
		profile.Data.QuestChain.Claimed = {}
	end

	return profile
end

local function refreshTargetState(target: Player, options)
	options = options or {}

	if PlayerController and PlayerController.SyncPublicState then
		PlayerController:SyncPublicState(target)
	end

	if options.reloadInventory == true and PlayerController and PlayerController.ReloadInventoryFromProfile then
		PlayerController:ReloadInventoryFromProfile(target)
	end

	if PickaxeController then
		if PickaxeController.RefreshUI then
			PickaxeController.RefreshUI(target)
		end

		if options.ensureBombSlot ~= false and PickaxeController.EnsureBombFirstSlot then
			task.defer(function()
				if target.Parent then
					PickaxeController.EnsureBombFirstSlot(target)
				end
			end)
		end
	end

	if UpgradesSystem and UpgradesSystem.UpdateClientUI then
		UpgradesSystem.UpdateClientUI(target)
	end

	if RebirthSystem and RebirthSystem.RefreshUIForTesting then
		RebirthSystem.RefreshUIForTesting(target)
	end

	if options.refreshPlot == true then
		if SlotManager and SlotManager.RefreshAllSlots then
			SlotManager.RefreshAllSlots(target)
		end

		if PlotRuntimeBridge and PlotRuntimeBridge.RefreshPlayerPlot then
			PlotRuntimeBridge.RefreshPlayerPlot(target)
		end
	end

	if DailyRewardController and DailyRewardController.PushStatusForTesting then
		DailyRewardController:PushStatusForTesting(target)
	end

	if PlaytimeRewardController and PlaytimeRewardController.PushStatusForTesting then
		PlaytimeRewardController:PushStatusForTesting(target)
	end

	if QuestChainService and QuestChainService.RefreshPlayer then
		QuestChainService:RefreshPlayer(target)
	end

	if TutorialService then
		if TutorialService.SyncPlayer then
			TutorialService:SyncPlayer(target)
		end

		if TutorialService.EvaluatePostTutorial then
			TutorialService:EvaluatePostTutorial(target)
		end
	end

	if options.refreshIndex == true then
		refreshIndex(target)
	end
end

local function setMoneyDirect(target: Player, newMoney: number): boolean
	local profile = ensureProfileTables(target)
	if not profile then
		return false
	end

	profile.Data.Money = math.max(0, math.floor(newMoney))
	refreshTargetState(target)
	return true
end

local function addMoneyDirect(target: Player, delta: number, countAsEarned: boolean): boolean
	local profile = ensureProfileTables(target)
	if not profile then
		return false
	end

	profile.Data.Money = math.max(0, math.floor((tonumber(profile.Data.Money) or 0) + delta))
	if delta > 0 and countAsEarned == true then
		profile.Data.TotalMoneyEarned = math.max(0, math.floor((tonumber(profile.Data.TotalMoneyEarned) or 0) + delta))
	end

	refreshTargetState(target)
	return true
end

local function grantInventoryEntries(target: Player, entries, incrementCollected: boolean?): (boolean, string)
	local profile = ensureProfileTables(target)
	if not profile then
		return false, "Profile not loaded."
	end

	local addedCount = 0
	for _, entry in ipairs(entries) do
		local itemName = normalizeString(entry.Name or entry.name, nil)
		local itemData = itemName and ItemConfigurations.GetItemData(itemName) or nil
		if itemName and itemData then
			local mutation = normalizeString(entry.Mutation or entry.mutation, "Normal") or "Normal"
			local level = math.max(1, normalizeInteger(entry.Level or entry.level, 1, 1, 999))

			table.insert(profile.Data.Inventory, {
				Name = itemName,
				Mutation = mutation,
				Rarity = itemData.Rarity or "Common",
				Level = level,
			})
			profile.Data.DiscoveredItems[mutation .. "_" .. itemName] = true
			addedCount += 1
		end
	end

	if addedCount <= 0 then
		return false, "No valid items to grant."
	end

	if incrementCollected ~= false and PlayerController and PlayerController.IncrementBrainrotsCollected then
		PlayerController:IncrementBrainrotsCollected(target, addedCount)
	end

	refreshTargetState(target, {
		reloadInventory = true,
		refreshIndex = true,
	})

	return true, `Granted {addedCount} brainrot(s).`
end

local function grantRandomItemsByRarity(target: Player, rarity: string, mutation: string, level: number, quantity: number)
	local itemNames = ItemConfigurations.GetItemsByRarity(rarity)
	if type(itemNames) ~= "table" or #itemNames == 0 then
		return false, `No brainrots found for rarity "{rarity}".`
	end

	local entries = {}
	for _ = 1, quantity do
		local selectedItem = itemNames[math.random(1, #itemNames)]
		table.insert(entries, {
			Name = selectedItem,
			Mutation = mutation,
			Level = level,
		})
	end

	return grantInventoryEntries(target, entries, true)
end

local function grantLuckyBlocks(target: Player, blockId: string, quantity: number)
	local blockConfig = LuckyBlockConfiguration.GetBlockConfig(blockId)
	if not blockConfig then
		return false, `Unknown lucky block "{blockId}".`
	end

	local grantedCount = 0
	for _ = 1, quantity do
		local tool = ItemManager.GiveLuckyBlockToPlayer(target, blockId)
		if tool then
			grantedCount += 1
		end
	end

	if grantedCount <= 0 then
		return false, "Failed to grant lucky block."
	end

	refreshTargetState(target, {
		ensureBombSlot = false,
	})

	return true, `Granted {grantedCount} lucky block(s).`
end

local function discoverAllIndexEntries(target: Player)
	local profile = ensureProfileTables(target)
	if not profile then
		return false, "Profile not loaded."
	end

	for itemName in pairs(ItemConfigurations.Items) do
		for mutation in pairs(Constants.MUTATION_MULTIPLIERS) do
			profile.Data.DiscoveredItems[mutation .. "_" .. itemName] = true
		end
	end

	refreshIndex(target)
	return true, "Marked all index entries as discovered."
end

local function clearDiscoveredIndexEntries(target: Player)
	local profile = ensureProfileTables(target)
	if not profile then
		return false, "Profile not loaded."
	end

	profile.Data.DiscoveredItems = {}
	refreshIndex(target)
	return true, "Cleared discovered index entries."
end

local function grantDailyRewardForTesting(target: Player, reward)
	if not reward then
		return false, "Reward is missing."
	end

	if reward.Type == "Money" then
		local success = addMoneyDirect(target, math.max(0, tonumber(reward.Amount) or 0), true)
		if not success then
			return false, "Failed to add money reward."
		end
		return true, "Granted daily money reward."
	end

	if reward.Type == "RandomItemByRarity" then
		return grantRandomItemsByRarity(target, tostring(reward.Rarity or "Common"), "Normal", 1, 1)
	end

	if reward.Type == "Pickaxe" then
		local pickaxeName = normalizeString(reward.PickaxeName, nil)
		if not pickaxeName or not PickaxeController then
			return false, "Daily pickaxe reward is unavailable."
		end

		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		if profile.Data.OwnedPickaxes[pickaxeName] == true then
			if reward.CompensationType == "Money" and type(reward.CompensationAmount) == "number" then
				local success = addMoneyDirect(target, reward.CompensationAmount, true)
				if success then
					return true, "Granted pickaxe compensation money."
				end
				return false, "Failed to grant compensation money."
			end
			return false, "Pickaxe is already owned and no compensation is configured."
		end

		if PickaxeController.UnlockPickaxeForTesting and PickaxeController.UnlockPickaxeForTesting(target, pickaxeName, true) then
			refreshTargetState(target)
			return true, `Unlocked {pickaxeName}.`
		end

		return false, "Failed to unlock pickaxe reward."
	end

	return false, `Unsupported daily reward type "{tostring(reward.Type)}".`
end

local function grantPlaytimeRewardForTesting(target: Player, reward)
	if not reward then
		return false, "Reward is missing."
	end

	if reward.Type == "Money" then
		local success = addMoneyDirect(target, math.max(0, tonumber(reward.Amount) or 0), true)
		if not success then
			return false, "Failed to add money reward."
		end
		return true, "Granted playtime money reward."
	end

	if reward.Type == "LuckyBlock" then
		local blockId = normalizeString(reward.LuckyBlockId, nil)
		if not blockId then
			return false, "Lucky block reward is missing."
		end
		return grantLuckyBlocks(target, blockId, 1)
	end

	if reward.Type == "Item" then
		local itemName = normalizeString(reward.ItemName, nil)
		if not itemName then
			return false, "Item reward is missing."
		end
		return grantInventoryEntries(target, {
			{
				Name = itemName,
				Mutation = reward.Mutation or "Normal",
				Level = reward.Level or 1,
			},
		}, true)
	end

	return false, `Unsupported playtime reward type "{tostring(reward.Type)}".`
end

local function grantPackRewardsForTesting(target: Player, packName: string)
	local packRewards = ProductConfigurations.PackRewards[packName]
	if not packRewards then
		return false, `Unknown pack "{packName}".`
	end

	local profile = ensureProfileTables(target)
	if not profile then
		return false, "Profile not loaded."
	end

	profile.Data.ClaimedPacks[packName] = true

	if type(packRewards.Money) == "number" and packRewards.Money > 0 then
		profile.Data.Money = math.max(0, math.floor((tonumber(profile.Data.Money) or 0) + packRewards.Money))
		profile.Data.TotalMoneyEarned = math.max(0, math.floor((tonumber(profile.Data.TotalMoneyEarned) or 0) + packRewards.Money))
	end

	local entries = {}
	for _, rewardItem in ipairs(packRewards.Items or {}) do
		table.insert(entries, {
			Name = rewardItem.Name,
			Mutation = rewardItem.Mutation or "Normal",
			Level = rewardItem.Level or 1,
		})
	end

	if #entries > 0 then
		for _, entry in ipairs(entries) do
			local itemData = ItemConfigurations.GetItemData(entry.Name)
			if itemData then
				table.insert(profile.Data.Inventory, {
					Name = entry.Name,
					Mutation = entry.Mutation,
					Rarity = itemData.Rarity or "Common",
					Level = entry.Level,
				})
				profile.Data.DiscoveredItems[entry.Mutation .. "_" .. entry.Name] = true
			end
		end

		if PlayerController and PlayerController.IncrementBrainrotsCollected then
			PlayerController:IncrementBrainrotsCollected(target, #entries)
		end
	end

	refreshTargetState(target, {
		reloadInventory = #entries > 0,
		refreshIndex = #entries > 0,
	})

	return true, `Granted configured rewards for {packName}.`
end

local function grantGroupRewardForTesting(target: Player)
	local rewardConfig = ProductConfigurations.Group and ProductConfigurations.Group.Reward
	if not rewardConfig then
		return false, "Group reward is not configured."
	end

	local profile = ensureProfileTables(target)
	if not profile then
		return false, "Profile not loaded."
	end

	profile.Data.ClaimedPacks["GroupReward"] = true
	profile.Data.ClaimedPacks["GroupItemReward"] = true
	target:SetAttribute("GroupRewardClaimed", true)

	local success, message = grantInventoryEntries(target, {
		{
			Name = rewardConfig.Name,
			Mutation = rewardConfig.Mutation or "Normal",
			Level = rewardConfig.Level or 1,
		},
	}, true)

	if not success then
		return false, message
	end

	return true, "Granted group reward item and marked it claimed."
end

local function setOnboardingStepDirect(target: Player, step: number)
	local profile = ensureProfileTables(target)
	if not profile then
		return false
	end

	profile.Data.OnboardingStep = math.clamp(step, 1, TutorialConfiguration.FinalStep)
	target:SetAttribute("OnboardingStep", profile.Data.OnboardingStep)
	return true
end

local function setPostTutorialStageDirect(target: Player, stage: number)
	local profile = ensureProfileTables(target)
	if not profile then
		return false
	end

	profile.Data.PostTutorialStage = PostTutorialConfiguration.ClampStage(stage)
	target:SetAttribute("PostTutorialStage", profile.Data.PostTutorialStage)
	return true
end

local function resolveTargetPartByTag(tagName: string, rootPosition: Vector3?): BasePart?
	local bestPart = nil
	local bestDistance = math.huge

	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
		if instance:IsA("BasePart") then
			if rootPosition then
				local distance = (instance.Position - rootPosition).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					bestPart = instance
				end
			elseif not bestPart then
				bestPart = instance
			end
		end
	end

	return bestPart
end

local function resolveTargetPartByKeyword(keyword: string): BasePart?
	local normalizedKeyword = string.lower(keyword)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("BasePart") and string.find(string.lower(descendant.Name), normalizedKeyword, 1, true) then
			return descendant
		end
	end
	return nil
end

local function teleportPlayerToCFrame(player: Player, targetCFrame: CFrame): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	character:PivotTo(targetCFrame)
	return true
end

local function getTeleportCFrame(player: Player, locationId: string): CFrame?
	if locationId == "plot_spawn" then
		local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
		return plot and SpawnUtils.GetPlotSpawnCFrame(plot, 4) or nil
	end

	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local rootPosition = rootPart and rootPart:IsA("BasePart") and rootPart.Position or nil

	if locationId == "shop" then
		local part = resolveTargetPartByTag("ShopPart", rootPosition) or resolveTargetPartByKeyword("shop")
		return part and (part.CFrame + Vector3.new(0, 5, 0)) or nil
	end

	if locationId == "upgrader" then
		local part = resolveTargetPartByTag("UpgradePart", rootPosition) or resolveTargetPartByKeyword("upgrade")
		return part and (part.CFrame + Vector3.new(0, 5, 0)) or nil
	end

	if locationId == "rebirth" then
		local part = resolveTargetPartByKeyword("rebirth")
		return part and (part.CFrame + Vector3.new(0, 5, 0)) or nil
	end

	if locationId == "mine_zone" then
		local zonesFolder = Workspace:FindFirstChild("Zones")
		if zonesFolder then
			for _, child in ipairs(zonesFolder:GetChildren()) do
				if child:IsA("BasePart") and child.Name == "ZonePart" then
					return child.CFrame + Vector3.new(0, 5, 0)
				end
			end
		end
	end

	return nil
end

registerAction({
	id = "add_money",
	label = "Add Money",
	description = "Adds money and also increases TotalMoneyEarned so quests and reward gates react naturally.",
	category = "Economy",
	order = 10,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Amount", 10000, { 1000, 10000, 100000, 1000000 }, 0, 10 ^ 12),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 10000, 0, 10 ^ 12)
		if addMoneyDirect(target, amount, true) then
			return true, `Added ${amount} to {target.Name}.`
		end
		return false, "Failed to add money."
	end,
})

registerAction({
	id = "set_money",
	label = "Set Money",
	description = "Sets the current money balance without changing TotalMoneyEarned.",
	category = "Economy",
	order = 20,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Amount", 50000, { 0, 10000, 50000, 1000000 }, 0, 10 ^ 12),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 50000, 0, 10 ^ 12)
		if setMoneyDirect(target, amount) then
			return true, `Set {target.Name}'s money to ${amount}.`
		end
		return false, "Failed to set money."
	end,
})

registerAction({
	id = "add_huge_money",
	label = "Add Huge Money",
	description = "Quickly grants a very large amount of money for late-game checks.",
	category = "Economy",
	order = 30,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput(
			"amount",
			"Amount",
			math.max(1, normalizeInteger(ManualTestAccessConfiguration.HugeMoneyAmount, 1000000000, 1, 10 ^ 12)),
			{ 1000000, 100000000, math.max(1, normalizeInteger(ManualTestAccessConfiguration.HugeMoneyAmount, 1000000000, 1, 10 ^ 12)) },
			1,
			10 ^ 12
		),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(
			params.amount,
			normalizeInteger(ManualTestAccessConfiguration.HugeMoneyAmount, 1000000000, 1, 10 ^ 12),
			1,
			10 ^ 12
		)
		if addMoneyDirect(target, amount, true) then
			return true, `Added huge money grant (${amount}) to {target.Name}.`
		end
		return false, "Failed to add huge money."
	end,
})

registerAction({
	id = "set_total_money_earned",
	label = "Set Total Money Earned",
	description = "Overrides TotalMoneyEarned for quests and progression checks.",
	category = "Economy",
	order = 40,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Amount", 100000, { 0, 5000, 50000, 500000 }, 0, 10 ^ 12),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 100000, 0, 10 ^ 12)
		if PlayerController and PlayerController.SetTotalMoneyEarnedForTesting and PlayerController:SetTotalMoneyEarnedForTesting(target, amount) then
			refreshTargetState(target)
			return true, `Set TotalMoneyEarned to ${amount}.`
		end
		return false, "Failed to set TotalMoneyEarned."
	end,
})

registerAction({
	id = "add_spins",
	label = "Add Spins",
	description = "Adds spins to the target player.",
	category = "Economy",
	order = 50,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Amount", 3, { 1, 3, 9, 25 }, 0, 100000),
	},
	handler = function(_executor, target, params)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local amount = normalizeInteger(params.amount, 3, 0, 100000)
		profile.Data.SpinNumber = math.max(0, math.floor((tonumber(profile.Data.SpinNumber) or 0) + amount))
		target:SetAttribute("SpinNumber", profile.Data.SpinNumber)
		return true, `Added {amount} spin(s).`
	end,
})

registerAction({
	id = "set_spins",
	label = "Set Spins",
	description = "Overrides the current spin count.",
	category = "Economy",
	order = 60,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Amount", 9, { 0, 1, 3, 9, 99 }, 0, 100000),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 9, 0, 100000)
		if PlayerController and PlayerController.SetSpinNumberForTesting and PlayerController:SetSpinNumberForTesting(target, amount) then
			return true, `Set spins to {amount}.`
		end
		return false, "Failed to set spins."
	end,
})

registerAction({
	id = "make_free_spin_ready",
	label = "Make Free Spin Ready",
	description = "Moves LastDailySpin back so the free spin is immediately available.",
	category = "Economy",
	order = 70,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		profile.Data.LastDailySpin = os.time() - FREE_SPIN_COOLDOWN_SECONDS
		target:SetAttribute("LastDailySpin", profile.Data.LastDailySpin)
		return true, "Free spin is now ready."
	end,
})

registerAction({
	id = "give_item",
	label = "Give Brainrot",
	description = "Grants any configured brainrot directly into the saved inventory.",
	category = "Inventory",
	order = 10,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("itemName", "Brainrot", "noobini_pizzanini", itemOptions, "Search a brainrot"),
		searchSelectInput("mutation", "Mutation", "Normal", mutationOptions, "Search a mutation"),
		numberInput("level", "Level", 1, { 1, 5, 10, 25 }, 1, 999),
		numberInput("quantity", "Quantity", 1, { 1, 5, 10, 25 }, 1, 100),
	},
	handler = function(_executor, target, params)
		local itemName = normalizeString(params.itemName, nil)
		if not itemName or not ItemConfigurations.GetItemData(itemName) then
			return false, "Pick a valid brainrot."
		end

		local mutation = normalizeString(params.mutation, "Normal") or "Normal"
		local level = normalizeInteger(params.level, 1, 1, 999)
		local quantity = normalizeInteger(params.quantity, 1, 1, 100)
		local entries = {}
		for _ = 1, quantity do
			table.insert(entries, {
				Name = itemName,
				Mutation = mutation,
				Level = level,
			})
		end

		return grantInventoryEntries(target, entries, true)
	end,
})

registerAction({
	id = "give_random_rarity_item",
	label = "Give Random By Rarity",
	description = "Grants random brainrots from the chosen rarity.",
	category = "Inventory",
	order = 20,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("rarity", "Rarity", "Rare", rarityOptions, "Search a rarity"),
		searchSelectInput("mutation", "Mutation", "Normal", mutationOptions, "Search a mutation"),
		numberInput("level", "Level", 1, { 1, 5, 10 }, 1, 999),
		numberInput("quantity", "Quantity", 1, { 1, 3, 5, 10 }, 1, 100),
	},
	handler = function(_executor, target, params)
		local rarity = normalizeString(params.rarity, nil)
		if not rarity then
			return false, "Pick a rarity."
		end

		local mutation = normalizeString(params.mutation, "Normal") or "Normal"
		local level = normalizeInteger(params.level, 1, 1, 999)
		local quantity = normalizeInteger(params.quantity, 1, 1, 100)
		return grantRandomItemsByRarity(target, rarity, mutation, level, quantity)
	end,
})

registerAction({
	id = "give_lucky_block",
	label = "Give Lucky Block",
	description = "Grants runtime lucky block tools into the backpack. These are not persisted in profile inventory.",
	category = "Inventory",
	order = 30,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("blockId", "Lucky Block", "luckyblock_common", luckyBlockOptions, "Search a lucky block"),
		numberInput("quantity", "Quantity", 1, { 1, 3, 5, 10 }, 1, 50),
	},
	handler = function(_executor, target, params)
		local blockId = normalizeString(params.blockId, nil)
		if not blockId then
			return false, "Pick a lucky block."
		end

		local quantity = normalizeInteger(params.quantity, 1, 1, 50)
		return grantLuckyBlocks(target, blockId, quantity)
	end,
})

registerAction({
	id = "add_item_to_carry",
	label = "Add Item To Carry",
	description = "Places a brainrot into the carry stack without touching saved inventory.",
	category = "Inventory",
	order = 40,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("itemName", "Brainrot", "noobini_pizzanini", itemOptions, "Search a brainrot"),
		searchSelectInput("mutation", "Mutation", "Normal", mutationOptions, "Search a mutation"),
		numberInput("quantity", "Quantity", 1, { 1, 2, 3 }, 1, 20),
	},
	handler = function(_executor, target, params)
		local itemName = normalizeString(params.itemName, nil)
		local itemData = itemName and ItemConfigurations.GetItemData(itemName) or nil
		if not itemData then
			return false, "Pick a valid brainrot."
		end

		local mutation = normalizeString(params.mutation, "Normal") or "Normal"
		local quantity = normalizeInteger(params.quantity, 1, 1, 20)
		local addedCount = 0
		for _ = 1, quantity do
			if CarrySystem.AddItemToCarry(target, itemName, mutation, itemData.Rarity or "Common") then
				addedCount += 1
			else
				break
			end
		end

		if addedCount <= 0 then
			return false, "Carry is full or the character is unavailable."
		end

		return true, `Added {addedCount} carried item(s).`
	end,
})

registerAction({
	id = "clear_carry",
	label = "Clear Carry",
	description = "Removes the current carry stack visuals and data.",
	category = "Inventory",
	order = 50,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		CarrySystem.ClearAllItems(target)
		return true, "Carry cleared."
	end,
})

registerAction({
	id = "clear_inventory",
	label = "Clear Inventory",
	description = "Removes all saved brainrots from the inventory and backpack.",
	category = "Inventory",
	order = 60,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		if PlayerController and PlayerController.ClearInventoryForTesting and PlayerController:ClearInventoryForTesting(target) then
			return true, "Inventory cleared."
		end
		return false, "Failed to clear inventory."
	end,
})

registerAction({
	id = "discover_all_index",
	label = "Discover All Index",
	description = "Marks every mutation/item pair as discovered in the index.",
	category = "Inventory",
	order = 70,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		return discoverAllIndexEntries(target)
	end,
})

registerAction({
	id = "clear_discovered_index",
	label = "Clear Discovered Index",
	description = "Clears the discovered index data for the current profile.",
	category = "Inventory",
	order = 80,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		return clearDiscoveredIndexEntries(target)
	end,
})

registerAction({
	id = "add_rebirths",
	label = "Add Rebirths",
	description = "Adds rebirth count without performing a full rebirth reset.",
	category = "Progression",
	order = 10,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Amount", 1, { 1, 5, 10, 25 }, 0, 10000),
	},
	handler = function(_executor, target, params)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local amount = normalizeInteger(params.amount, 1, 0, 10000)
		local nextRebirths = math.max(0, math.floor((tonumber(profile.Data.Rebirths) or 0) + amount))
		if RebirthSystem.SetRebirthsForTesting and RebirthSystem.SetRebirthsForTesting(target, nextRebirths) then
			refreshTargetState(target)
			return true, `Set rebirths to {nextRebirths}.`
		end
		return false, "Failed to add rebirths."
	end,
})

registerAction({
	id = "set_rebirths",
	label = "Set Rebirths",
	description = "Overrides the rebirth counter directly.",
	category = "Progression",
	order = 20,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Amount", 5, { 0, 1, 5, 25 }, 0, 10000),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 5, 0, 10000)
		if RebirthSystem.SetRebirthsForTesting and RebirthSystem.SetRebirthsForTesting(target, amount) then
			refreshTargetState(target)
			return true, `Set rebirths to {amount}.`
		end
		return false, "Failed to set rebirths."
	end,
})

registerAction({
	id = "force_rebirth",
	label = "Force Rebirth",
	description = "Performs the actual rebirth reset flow without the normal purchase path.",
	category = "Progression",
	order = 30,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		if RebirthSystem.ForceRebirthForTesting and RebirthSystem.ForceRebirthForTesting(target) then
			refreshTargetState(target, {
				reloadInventory = true,
				refreshIndex = true,
				refreshPlot = true,
			})
			return true, "Forced rebirth completed."
		end
		return false, "Failed to force rebirth."
	end,
})

registerAction({
	id = "set_bonus_speed",
	label = "Set Bonus Speed",
	description = "Overrides the visible character speed upgrade stat.",
	category = "Progression",
	order = 40,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "BonusSpeed", 1, { 0, 1, 3, 5, 10 }, 0, 1000),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 1, 0, 1000)
		if PlayerController and PlayerController.SetUpgradeStatForTesting and PlayerController:SetUpgradeStatForTesting(target, "BonusSpeed", amount) then
			refreshTargetState(target)
			return true, `Set BonusSpeed to {amount}.`
		end
		return false, "Failed to set BonusSpeed."
	end,
})

registerAction({
	id = "set_carry_capacity",
	label = "Set Carry Capacity",
	description = "Overrides the visible carry capacity upgrade stat.",
	category = "Progression",
	order = 50,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "CarryCapacity", 1, { 0, 1, 2, 3, 5 }, 0, 1000),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 1, 0, 1000)
		if PlayerController and PlayerController.SetUpgradeStatForTesting and PlayerController:SetUpgradeStatForTesting(target, "CarryCapacity", amount) then
			refreshTargetState(target)
			return true, `Set CarryCapacity to {amount}.`
		end
		return false, "Failed to set CarryCapacity."
	end,
})

registerAction({
	id = "set_bonus_range",
	label = "Set Bonus Range",
	description = "Overrides the hidden range upgrade stat.",
	category = "Progression",
	order = 60,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "BonusRange", 1, { 0, 1, 3, 5, 10 }, 0, 1000),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 1, 0, 1000)
		if PlayerController and PlayerController.SetUpgradeStatForTesting and PlayerController:SetUpgradeStatForTesting(target, "BonusRange", amount) then
			refreshTargetState(target)
			return true, `Set BonusRange to {amount}.`
		end
		return false, "Failed to set BonusRange."
	end,
})

registerAction({
	id = "set_slots",
	label = "Set Slots",
	description = "Overrides the unlocked slot count and refreshes the plot visuals.",
	category = "Progression",
	order = 70,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "UnlockedSlots", SlotUnlockConfigurations.StartSlots, { SlotUnlockConfigurations.StartSlots, 20, 30, SlotUnlockConfigurations.MaxSlots }, SlotUnlockConfigurations.StartSlots, SlotUnlockConfigurations.MaxSlots),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, SlotUnlockConfigurations.StartSlots, SlotUnlockConfigurations.StartSlots, SlotUnlockConfigurations.MaxSlots)
		if PlayerController and PlayerController.SetUnlockedSlotsForTesting and PlayerController:SetUnlockedSlotsForTesting(target, amount) then
			refreshTargetState(target, {
				refreshPlot = true,
			})
			return true, `Set unlocked slots to {amount}.`
		end
		return false, "Failed to set slots."
	end,
})

registerAction({
	id = "max_slots",
	label = "Max Slots",
	description = "Unlocks the maximum number of base slots.",
	category = "Progression",
	order = 80,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		if PlayerController and PlayerController.SetUnlockedSlotsForTesting and PlayerController:SetUnlockedSlotsForTesting(target, SlotUnlockConfigurations.MaxSlots) then
			refreshTargetState(target, {
				refreshPlot = true,
			})
			return true, "Unlocked max slots."
		end
		return false, "Failed to set max slots."
	end,
})

registerAction({
	id = "reset_slots",
	label = "Reset Slots",
	description = "Returns the unlocked slot count back to the default start value.",
	category = "Progression",
	order = 90,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		if PlayerController and PlayerController.SetUnlockedSlotsForTesting and PlayerController:SetUnlockedSlotsForTesting(target, SlotUnlockConfigurations.StartSlots) then
			refreshTargetState(target, {
				refreshPlot = true,
			})
			return true, "Slots reset to default."
		end
		return false, "Failed to reset slots."
	end,
})

registerAction({
	id = "unlock_pickaxe",
	label = "Unlock Pickaxe",
	description = "Unlocks a pickaxe directly and can auto-equip it.",
	category = "Progression",
	order = 100,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("pickaxeName", "Pickaxe", "Bomb 1", pickaxeOptions, "Search a pickaxe"),
		booleanInput("equipAfter", "Equip After Unlock", true),
	},
	handler = function(_executor, target, params)
		local pickaxeName = normalizeString(params.pickaxeName, nil)
		if not pickaxeName or not BombsConfigurations.Bombs[pickaxeName] then
			return false, "Pick a valid pickaxe."
		end

		if PickaxeController and PickaxeController.UnlockPickaxeForTesting and PickaxeController.UnlockPickaxeForTesting(target, pickaxeName, normalizeBoolean(params.equipAfter, true)) then
			refreshTargetState(target)
			return true, `Unlocked {pickaxeName}.`
		end
		return false, "Failed to unlock pickaxe."
	end,
})

registerAction({
	id = "unlock_all_pickaxes",
	label = "Unlock All Pickaxes",
	description = "Unlocks every configured pickaxe.",
	category = "Progression",
	order = 110,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		booleanInput("equipHighest", "Equip Highest", true),
	},
	handler = function(_executor, target, params)
		if PickaxeController and PickaxeController.UnlockAllPickaxesForTesting and PickaxeController.UnlockAllPickaxesForTesting(target, normalizeBoolean(params.equipHighest, true)) then
			refreshTargetState(target)
			return true, "Unlocked all pickaxes."
		end
		return false, "Failed to unlock all pickaxes."
	end,
})

registerAction({
	id = "equip_pickaxe",
	label = "Equip Pickaxe",
	description = "Equips an already owned pickaxe.",
	category = "Progression",
	order = 120,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("pickaxeName", "Pickaxe", "Bomb 1", pickaxeOptions, "Search a pickaxe"),
	},
	handler = function(_executor, target, params)
		local pickaxeName = normalizeString(params.pickaxeName, nil)
		local profile = ensureProfileTables(target)
		if not profile or not pickaxeName or profile.Data.OwnedPickaxes[pickaxeName] ~= true then
			return false, "Pickaxe is not owned."
		end

		profile.Data.EquippedPickaxe = pickaxeName
		if PickaxeController and PickaxeController.EquipPickaxe then
			PickaxeController.EquipPickaxe(target, pickaxeName)
		end
		refreshTargetState(target)
		return true, `Equipped {pickaxeName}.`
	end,
})

registerAction({
	id = "reset_pickaxe_to_bomb1",
	label = "Reset To Bomb 1",
	description = "Resets owned pickaxes back to the default starter bomb.",
	category = "Progression",
	order = 130,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		if PickaxeController and PickaxeController.ResetPickaxesForTesting and PickaxeController.ResetPickaxesForTesting(target) then
			refreshTargetState(target)
			return true, "Pickaxes reset to Bomb 1."
		end
		return false, "Failed to reset pickaxes."
	end,
})

registerAction({
	id = "set_time_played",
	label = "Set Time Played",
	description = "Overrides TimePlayed in seconds.",
	category = "Progression",
	order = 140,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("seconds", "Seconds", 600, { 60, 180, 600, 3600 }, 0, 10 ^ 9),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.seconds, 600, 0, 10 ^ 9)
		if PlayerController and PlayerController.SetTimePlayedForTesting and PlayerController:SetTimePlayedForTesting(target, amount) then
			refreshTargetState(target)
			return true, `Set TimePlayed to {amount} second(s).`
		end
		return false, "Failed to set TimePlayed."
	end,
})

registerAction({
	id = "set_total_brainrots_collected",
	label = "Set Total Brainrots Collected",
	description = "Overrides TotalBrainrotsCollected for quests and UI.",
	category = "Progression",
	order = 150,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Amount", 10, { 0, 3, 10, 50 }, 0, 10 ^ 9),
	},
	handler = function(_executor, target, params)
		local amount = normalizeInteger(params.amount, 10, 0, 10 ^ 9)
		if PlayerController and PlayerController.SetTotalBrainrotsCollectedForTesting and PlayerController:SetTotalBrainrotsCollectedForTesting(target, amount) then
			refreshTargetState(target)
			return true, `Set TotalBrainrotsCollected to {amount}.`
		end
		return false, "Failed to set TotalBrainrotsCollected."
	end,
})

registerAction({
	id = "set_max_depth_level",
	label = "Set Max Depth",
	description = "Overrides MaxDepthLevelReached for quest and progression checks.",
	category = "Progression",
	order = 160,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("amount", "Depth Level", 1, { 0, 1, 2, 3, 4, 5 }, 0, 999),
	},
	handler = function(_executor, target, params)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local amount = normalizeInteger(params.amount, 1, 0, 999)
		profile.Data.MaxDepthLevelReached = amount
		target:SetAttribute("MaxDepthLevelReached", amount)
		refreshTargetState(target)
		return true, `Set MaxDepthLevelReached to {amount}.`
	end,
})

registerAction({
	id = "set_onboarding_step",
	label = "Set Onboarding Step",
	description = "Overrides the current FTUE step without using the normal analytics flow.",
	category = "Progression",
	order = 170,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("step", "Step", TutorialConfiguration.FinalStep, { 1, 3, 6, TutorialConfiguration.FinalStep }, 1, TutorialConfiguration.FinalStep),
	},
	handler = function(_executor, target, params)
		local step = normalizeInteger(params.step, TutorialConfiguration.FinalStep, 1, TutorialConfiguration.FinalStep)
		if setOnboardingStepDirect(target, step) then
			if step < TutorialConfiguration.FinalStep then
				setPostTutorialStageDirect(target, PostTutorialConfiguration.Stages.WaitingForCharacterMoney)
			end
			refreshTargetState(target)
			return true, `Set onboarding step to {step}.`
		end
		return false, "Failed to set onboarding step."
	end,
})

registerAction({
	id = "complete_ftue",
	label = "Complete FTUE",
	description = "Marks the main tutorial as completed.",
	category = "Progression",
	order = 180,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		if setOnboardingStepDirect(target, TutorialConfiguration.FinalStep) then
			refreshTargetState(target)
			return true, "FTUE marked as completed."
		end
		return false, "Failed to complete FTUE."
	end,
})

registerAction({
	id = "reset_ftue",
	label = "Reset FTUE",
	description = "Returns the player to the first onboarding step and resets post-tutorial progression.",
	category = "Progression",
	order = 190,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		local success = setOnboardingStepDirect(target, 1) and setPostTutorialStageDirect(target, PostTutorialConfiguration.Stages.WaitingForCharacterMoney)
		if success then
			refreshTargetState(target)
			return true, "FTUE reset to step 1."
		end
		return false, "Failed to reset FTUE."
	end,
})

registerAction({
	id = "set_post_tutorial_stage",
	label = "Set Post Tutorial Stage",
	description = "Overrides the post-tutorial chain stage.",
	category = "Progression",
	order = 200,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("stage", "Stage", PostTutorialConfiguration.Stages.WaitingForCharacterMoney, { 0, 1, 2, 3, 4 }, 0, PostTutorialConfiguration.Stages.Completed),
	},
	handler = function(_executor, target, params)
		local stage = normalizeInteger(params.stage, PostTutorialConfiguration.Stages.WaitingForCharacterMoney, 0, PostTutorialConfiguration.Stages.Completed)
		if setPostTutorialStageDirect(target, stage) then
			refreshTargetState(target)
			return true, `Set post tutorial stage to {stage}.`
		end
		return false, "Failed to set post tutorial stage."
	end,
})

registerAction({
	id = "reset_post_tutorial",
	label = "Reset Post Tutorial",
	description = "Resets the post-tutorial chain back to the initial waiting stage.",
	category = "Progression",
	order = 210,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		if setPostTutorialStageDirect(target, PostTutorialConfiguration.Stages.WaitingForCharacterMoney) then
			refreshTargetState(target)
			return true, "Post tutorial reset."
		end
		return false, "Failed to reset post tutorial."
	end,
})

registerAction({
	id = "unlock_daily_day",
	label = "Unlock Daily Day",
	description = "Unlocks a specific daily reward day without claiming it.",
	category = "Rewards",
	order = 10,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("day", "Day", "1", dailyDayOptions, "Pick a day"),
	},
	handler = function(_executor, target, params)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local day = normalizeInteger(params.day, 1, 1, DailyRewardConfiguration.GetMaxDay())
		local success, err = DailyRewardManager.UnlockDay(profile.Data, day)
		if not success then
			return false, err or "Failed to unlock day."
		end

		refreshTargetState(target)
		return true, `Unlocked daily reward day {day}.`
	end,
})

registerAction({
	id = "claim_daily_day",
	label = "Claim Daily Day",
	description = "Claims a daily reward day using a testing-safe reward path.",
	category = "Rewards",
	order = 20,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("day", "Day", "1", dailyDayOptions, "Pick a day"),
	},
	handler = function(_executor, target, params)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local day = normalizeInteger(params.day, 1, 1, DailyRewardConfiguration.GetMaxDay())
		local canClaim, err, _, reward = DailyRewardManager.GetClaimableReward(profile.Data, day)
		if not canClaim then
			return false, err or "Reward is not claimable."
		end

		local applied, applyMessage = grantDailyRewardForTesting(target, reward)
		if not applied then
			return false, applyMessage
		end

		local marked, markError = DailyRewardManager.MarkRewardClaimed(profile.Data, day)
		if not marked then
			return false, markError or "Reward could not be marked claimed."
		end

		refreshTargetState(target)
		return true, `Claimed daily reward day {day}.`
	end,
})

registerAction({
	id = "reset_daily_rewards",
	label = "Reset Daily Rewards",
	description = "Resets the daily reward cycle back to a fresh state for today.",
	category = "Rewards",
	order = 30,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		profile.Data.DailyRewards = nil
		refreshTargetState(target)
		return true, "Daily rewards reset."
	end,
})

registerAction({
	id = "add_playtime_minutes",
	label = "Add Playtime Minutes",
	description = "Adds playtime progress for the current playtime reward day.",
	category = "Rewards",
	order = 40,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		numberInput("minutes", "Minutes", 5, { 1, 5, 10, 30 }, 0, 1440),
	},
	handler = function(_executor, target, params)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local minutes = normalizeInteger(params.minutes, 5, 0, 1440)
		local playtimeData = PlaytimeRewardManager.EnsureData(profile.Data)
		playtimeData.PlaytimeSeconds = math.max(0, math.floor(playtimeData.PlaytimeSeconds + (minutes * 60)))
		refreshTargetState(target)
		return true, `Added {minutes} playtime minute(s).`
	end,
})

registerAction({
	id = "skip_all_playtime_rewards",
	label = "Skip All Playtime Rewards",
	description = "Unlocks all playtime rewards for the current day.",
	category = "Rewards",
	order = 50,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		PlaytimeRewardManager.SkipAll(profile.Data)
		refreshTargetState(target)
		return true, "All playtime rewards unlocked."
	end,
})

registerAction({
	id = "grant_playtime_x2",
	label = "Grant Playtime x2",
	description = "Enables the x2 playtime reward multiplier.",
	category = "Rewards",
	order = 60,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local success, err = PlaytimeRewardManager.GrantSpeedProduct(profile.Data, "PlaytimeRewardsSpeedX2")
		if not success then
			return false, err or "Failed to grant x2."
		end

		refreshTargetState(target)
		return true, "Granted playtime x2."
	end,
})

registerAction({
	id = "grant_playtime_x5",
	label = "Grant Playtime x5",
	description = "Enables the x5 playtime reward multiplier.",
	category = "Rewards",
	order = 70,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local success, err = PlaytimeRewardManager.GrantSpeedProduct(profile.Data, "PlaytimeRewardsSpeedX5")
		if not success then
			return false, err or "Failed to grant x5."
		end

		refreshTargetState(target)
		return true, "Granted playtime x5."
	end,
})

registerAction({
	id = "claim_playtime_reward",
	label = "Claim Playtime Reward",
	description = "Claims a playtime reward using a testing-safe reward path.",
	category = "Rewards",
	order = 80,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("rewardId", "Reward", "1", playtimeRewardOptions, "Pick a reward"),
	},
	handler = function(_executor, target, params)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local rewardId = normalizeInteger(params.rewardId, 1, 1, PlaytimeRewardConfiguration.GetMaxRewardId())
		local success, err, _, reward = PlaytimeRewardManager.Claim(profile.Data, rewardId)
		if not success then
			return false, err or "Reward is not claimable."
		end

		local granted, grantMessage = grantPlaytimeRewardForTesting(target, reward)
		if not granted then
			return false, grantMessage
		end

		refreshTargetState(target)
		return true, `Claimed playtime reward #{rewardId}.`
	end,
})

registerAction({
	id = "reset_playtime_rewards",
	label = "Reset Playtime Rewards",
	description = "Resets playtime rewards for the current profile.",
	category = "Rewards",
	order = 90,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		profile.Data.PlaytimeRewards = nil
		refreshTargetState(target)
		return true, "Playtime rewards reset."
	end,
})

registerAction({
	id = "grant_pack_rewards",
	label = "Grant Pack Rewards",
	description = "Directly grants a configured gamepass pack reward bundle.",
	category = "Rewards",
	order = 100,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("packName", "Pack", "StarterPack", packOptions, "Pick a pack"),
	},
	handler = function(_executor, target, params)
		local packName = normalizeString(params.packName, nil)
		if not packName then
			return false, "Pick a pack."
		end
		return grantPackRewardsForTesting(target, packName)
	end,
})

registerAction({
	id = "grant_item_product_reward",
	label = "Grant Item Product Reward",
	description = "Directly grants a configured dev-product item reward.",
	category = "Rewards",
	order = 110,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("productName", "Item Product", "ItemProduct1", itemProductOptions, "Pick a product"),
	},
	handler = function(_executor, target, params)
		local productName = normalizeString(params.productName, nil)
		local reward = productName and ProductConfigurations.ItemProductRewards[productName] or nil
		if not reward then
			return false, "Pick a valid item product."
		end

		return grantInventoryEntries(target, {
			{
				Name = reward.Name,
				Mutation = reward.Mutation or "Normal",
				Level = reward.Level or 1,
			},
		}, true)
	end,
})

registerAction({
	id = "grant_cash_product_reward",
	label = "Grant Cash Product Reward",
	description = "Directly grants a configured dev-product cash reward.",
	category = "Rewards",
	order = 120,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("productName", "Cash Product", "CashProduct1", cashProductOptions, "Pick a product"),
	},
	handler = function(_executor, target, params)
		local productName = normalizeString(params.productName, nil)
		local amount = productName and ProductConfigurations.CashProductRewards[productName] or nil
		if type(amount) ~= "number" then
			return false, "Pick a valid cash product."
		end

		if addMoneyDirect(target, amount, true) then
			return true, `Granted cash product reward ${amount}.`
		end
		return false, "Failed to grant cash product reward."
	end,
})

registerAction({
	id = "grant_spin_pack_reward",
	label = "Grant Spin Pack",
	description = "Directly grants configured spin pack rewards.",
	category = "Rewards",
	order = 130,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("productName", "Spin Pack", "SpinsX3", spinProductOptions, "Pick a spin pack"),
	},
	handler = function(_executor, target, params)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		local productName = normalizeString(params.productName, nil)
		local amount = if productName == "SpinsX9" then 9 elseif productName == "SpinsX3" then 3 else nil
		if not amount then
			return false, "Pick a valid spin pack."
		end

		profile.Data.SpinNumber = math.max(0, math.floor((tonumber(profile.Data.SpinNumber) or 0) + amount))
		target:SetAttribute("SpinNumber", profile.Data.SpinNumber)
		return true, `Granted {amount} spins from {productName}.`
	end,
})

registerAction({
	id = "grant_group_reward",
	label = "Grant Group Reward",
	description = "Directly grants the configured group reward and marks it as claimed.",
	category = "Rewards",
	order = 140,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		return grantGroupRewardForTesting(target)
	end,
})

registerAction({
	id = "refresh_quests",
	label = "Refresh Quests",
	description = "Refreshes the quest chain state for the target player.",
	category = "Rewards",
	order = 150,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		if QuestChainService and QuestChainService.RefreshPlayer then
			QuestChainService:RefreshPlayer(target)
			return true, "Quest chain refreshed."
		end
		return false, "Quest chain service is unavailable."
	end,
})

registerAction({
	id = "claim_quest",
	label = "Claim Quest",
	description = "Claims a completed quest without the normal analytics path.",
	category = "Rewards",
	order = 160,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("questId", "Quest", "rebirth_1", questOptions, "Search a quest"),
	},
	handler = function(_executor, target, params)
		local questId = normalizeString(params.questId, nil)
		if not questId then
			return false, "Pick a quest."
		end

		local state = QuestChainService and QuestChainService.GetPlayerState and QuestChainService:GetPlayerState(target)
		if not state then
			return false, "Quest state is unavailable."
		end

		local questState = nil
		for _, entry in ipairs(state.all or {}) do
			if entry.id == questId then
				questState = entry
				break
			end
		end

		if not questState then
			return false, "Quest not found."
		end

		if questState.isClaimed then
			return false, "Quest is already claimed."
		end

		if not questState.isCompleted then
			return false, "Quest is not completed yet."
		end

		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		profile.Data.QuestChain.Claimed[questId] = true
		if not addMoneyDirect(target, tonumber(questState.rewardValue) or 0, true) then
			return false, "Failed to grant quest money reward."
		end

		if QuestChainService and QuestChainService.RefreshPlayer then
			QuestChainService:RefreshPlayer(target)
		end

		return true, `Claimed quest {questId}.`
	end,
})

registerAction({
	id = "reset_claimed_quests",
	label = "Reset Claimed Quests",
	description = "Clears quest claim data so the quest chain can be tested again.",
	category = "Rewards",
	order = 170,
	minAccess = "tester",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		local profile = ensureProfileTables(target)
		if not profile then
			return false, "Profile not loaded."
		end

		profile.Data.QuestChain = {
			Claimed = {},
		}
		if QuestChainService and QuestChainService.RefreshPlayer then
			QuestChainService:RefreshPlayer(target)
		end
		return true, "Claimed quests reset."
	end,
})

registerAction({
	id = "teleport_self",
	label = "Teleport Self",
	description = "Teleports the executor to a useful test location.",
	category = "World / QA",
	order = 10,
	minAccess = "tester",
	allowOtherTarget = false,
	inputs = {
		searchSelectInput("locationId", "Location", "plot_spawn", teleportOptions, "Pick a location"),
	},
	handler = function(executor, _target, params)
		local locationId = normalizeString(params.locationId, "plot_spawn") or "plot_spawn"
		local targetCFrame = getTeleportCFrame(executor, locationId)
		if not targetCFrame then
			return false, `Could not resolve location "{locationId}".`
		end

		if teleportPlayerToCFrame(executor, targetCFrame) then
			return true, `Teleported to {locationId}.`
		end
		return false, "Executor character is not ready."
	end,
})

registerAction({
	id = "respawn_character",
	label = "Respawn Character",
	description = "Respawns the selected online player.",
	category = "World / QA",
	order = 20,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		target:LoadCharacter()
		task.delay(1, function()
			if target.Parent then
				refreshTargetState(target, {
					reloadInventory = true,
					refreshIndex = true,
				})
			end
		end)
		return true, "Respawn requested."
	end,
})

registerAction({
	id = "fire_test_notification",
	label = "Fire Test Notification",
	description = "Sends a notification to the selected player.",
	category = "World / QA",
	order = 30,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		textInput("message", "Message", "Manual test notification", "Type a notification"),
		searchSelectInput("messageType", "Type", "Success", notificationTypeOptions, "Pick a type"),
	},
	handler = function(_executor, target, params)
		local message = normalizeString(params.message, "Manual test notification") or "Manual test notification"
		local messageType = normalizeString(params.messageType, "Success") or "Success"
		showNotification(target, message, messageType)
		return true, "Notification sent."
	end,
})

registerAction({
	id = "fire_ui_effect",
	label = "Fire UI Effect",
	description = "Triggers a client UI effect for the selected player.",
	category = "World / QA",
	order = 40,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {
		searchSelectInput("effectName", "Effect", "FOVPop", uiEffectOptions, "Pick an effect"),
	},
	handler = function(_executor, target, params)
		local effectName = normalizeString(params.effectName, "FOVPop") or "FOVPop"
		local remote = getUIEffectRemote()
		if not remote then
			return false, "TriggerUIEffect remote is unavailable."
		end

		remote:FireClient(target, effectName)
		return true, `Triggered UI effect "{effectName}".`
	end,
})

registerAction({
	id = "force_save_profile",
	label = "Force Save Profile",
	description = "Immediately saves the selected player's profile.",
	category = "World / QA",
	order = 50,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		if PlayerController and PlayerController.ForceSaveProfile and PlayerController:ForceSaveProfile(target) then
			return true, "Profile saved."
		end
		return false, "Failed to save profile."
	end,
})

registerAction({
	id = "full_refresh_state",
	label = "Full Refresh State",
	description = "Pushes a full client/server refresh from current profile data.",
	category = "World / QA",
	order = 60,
	minAccess = "tester",
	allowOtherTarget = true,
	inputs = {},
	handler = function(_executor, target)
		refreshTargetState(target, {
			reloadInventory = true,
			refreshIndex = true,
			refreshPlot = true,
		})
		return true, "Full refresh completed."
	end,
})

registerAction({
	id = "reset_profile_to_default",
	label = "Reset Profile To Default",
	description = "Deep-resets the selected profile back to the template defaults, clears carry, and saves immediately.",
	category = "Danger",
	order = 10,
	minAccess = "admin",
	allowOtherTarget = true,
	isDestructive = true,
	confirmationText = "RESET",
	inputs = {},
	handler = function(_executor, target)
		if not PlayerController or not PlayerController.ResetProfileToDefaultForTesting or not PlayerController:ResetProfileToDefaultForTesting(target) then
			return false, "Failed to reset profile."
		end

		CarrySystem.ClearAllItems(target)
		if PickaxeController and PickaxeController.ResetPickaxesForTesting then
			PickaxeController.ResetPickaxesForTesting(target)
		end

		refreshTargetState(target, {
			reloadInventory = true,
			refreshIndex = true,
			refreshPlot = true,
		})

		if PlayerController.ForceSaveProfile then
			PlayerController:ForceSaveProfile(target)
		end

		return true, "Profile reset to defaults."
	end,
})

table.sort(orderedActions, function(a, b)
	local categoryOrderA = CATEGORY_ORDER[a.category] or math.huge
	local categoryOrderB = CATEGORY_ORDER[b.category] or math.huge
	if categoryOrderA ~= categoryOrderB then
		return categoryOrderA < categoryOrderB
	end

	local orderA = tonumber(a.order) or math.huge
	local orderB = tonumber(b.order) or math.huge
	if orderA ~= orderB then
		return orderA < orderB
	end

	return string.lower(a.label) < string.lower(b.label)
end)

local function buildVisibleActionList(accessLevel: string)
	local actions = {}

	for _, action in ipairs(orderedActions) do
		local hasRequiredAccess = isAccessAtLeast(accessLevel, action.minAccess or "tester")
		local canUseDestructive = action.isDestructive ~= true or isAccessAtLeast(accessLevel, "admin")
		if hasRequiredAccess and canUseDestructive then
			table.insert(actions, {
				id = action.id,
				label = action.label,
				description = action.description,
				category = action.category,
				order = action.order,
				minAccess = action.minAccess,
				allowOtherTarget = action.allowOtherTarget == true,
				isDestructive = action.isDestructive == true,
				confirmationText = action.confirmationText,
				inputs = action.inputs or {},
			})
		end
	end

	return actions
end

local function resolveActionTarget(executor: Player, accessLevel: string, action, requestedTargetUserId): (Player?, string?)
	if requestedTargetUserId == nil or requestedTargetUserId == executor.UserId then
		return executor, nil
	end

	if action.allowOtherTarget ~= true then
		return nil, "This action is self-only."
	end

	if not isAccessAtLeast(accessLevel, "admin") then
		return nil, "Your access level cannot target other players."
	end

	local target = getTargetPlayer(requestedTargetUserId)
	if not target then
		return nil, "Target player is offline."
	end

	return target, nil
end

local function buildBootstrapPayload(executor: Player, accessLevel: string)
	return {
		Success = true,
		Allowed = accessLevel ~= "none",
		AccessLevel = accessLevel,
		AccessColor = buildAccessBadgeColor(accessLevel),
		Targets = getAvailableTargets(executor, accessLevel),
		Actions = buildVisibleActionList(accessLevel),
		Snapshot = buildTargetSnapshot(executor, executor, accessLevel),
		AuditLog = getVisibleAuditEntries(executor, accessLevel),
	}
end

local function ensureRemotes()
	local events = getEventsFolder()

	local testFolder = events:FindFirstChild("TestManager")
	if not testFolder or not testFolder:IsA("Folder") then
		testFolder = Instance.new("Folder")
		testFolder.Name = "TestManager"
		testFolder.Parent = events
	end
	remotesFolder = testFolder

	local function ensureRemoteFunction(name: string)
		local remote = testFolder:FindFirstChild(name)
		if remote and remote:IsA("RemoteFunction") then
			return remote
		end

		local created = Instance.new("RemoteFunction")
		created.Name = name
		created.Parent = testFolder
		return created
	end

	getBootstrapRemote = ensureRemoteFunction("GetBootstrap")
	getTargetSnapshotRemote = ensureRemoteFunction("GetTargetSnapshot")
	executeActionRemote = ensureRemoteFunction("ExecuteAction")
end

function ManualTestController:Init(controllers)
	PlayerController = controllers.PlayerController
	PickaxeController = controllers.PickaxeController
	DailyRewardController = controllers.DailyRewardController
	PlaytimeRewardController = controllers.PlaytimeRewardController

	ensureRemotes()

	if getBootstrapRemote then
		getBootstrapRemote.OnServerInvoke = function(player)
			local accessLevel = getAccessLevel(player)
			if accessLevel == "none" then
				return {
					Success = false,
					Allowed = false,
					AccessLevel = accessLevel,
				}
			end

			return buildBootstrapPayload(player, accessLevel)
		end
	end

	if getTargetSnapshotRemote then
		getTargetSnapshotRemote.OnServerInvoke = function(player, targetUserId)
			local accessLevel = getAccessLevel(player)
			if accessLevel == "none" then
				return {
					Success = false,
					Error = "Not authorized.",
				}
			end

			local requestedTargetId = normalizeInteger(targetUserId, player.UserId, 0, MAX_TEST_USER_ID)
			local target = getTargetPlayer(requestedTargetId)
			if not target then
				return {
					Success = false,
					Error = "Target player is offline.",
				}
			end

			if target ~= player and not isAccessAtLeast(accessLevel, "admin") then
				return {
					Success = false,
					Error = "Your access level cannot inspect other players.",
				}
			end

			local snapshot = buildTargetSnapshot(target, player, accessLevel)
			if not snapshot then
				return {
					Success = false,
					Error = "Target profile is not loaded.",
				}
			end

			return {
				Success = true,
				Snapshot = snapshot,
				AuditLog = getVisibleAuditEntries(player, accessLevel),
			}
		end
	end

	if executeActionRemote then
		executeActionRemote.OnServerInvoke = function(player, payload)
			local accessLevel = getAccessLevel(player)
			if accessLevel == "none" then
				return {
					Success = false,
					Error = "Not authorized.",
				}
			end

			local request = if type(payload) == "table" then payload else {}
			local actionId = normalizeString(request.actionId, nil)
			if not actionId then
				return {
					Success = false,
					Error = "Missing actionId.",
				}
			end

			local action = actionsById[actionId]
			if not action then
				return {
					Success = false,
					Error = `Unknown action "{actionId}".`,
				}
			end

			if not isAccessAtLeast(accessLevel, action.minAccess or "tester") then
				return {
					Success = false,
					Error = "Access denied for this action.",
				}
			end

			if action.isDestructive == true then
				if not isAccessAtLeast(accessLevel, "admin") then
					return {
						Success = false,
						Error = "Destructive actions require admin access.",
					}
				end

				local requiredConfirmation = action.confirmationText or "RESET"
				if normalizeString(request.confirmationText, "") ~= requiredConfirmation then
					return {
						Success = false,
						Error = `Type "{requiredConfirmation}" to confirm this action.`,
					}
				end
			end

			local targetUserId = normalizeInteger(request.targetUserId, player.UserId, 0, MAX_TEST_USER_ID)
			local target, targetError = resolveActionTarget(player, accessLevel, action, targetUserId)
			if not target then
				return {
					Success = false,
					Error = targetError or "Target resolution failed.",
				}
			end

			local params = if type(request.params) == "table" then request.params else {}
			local success, resultMessage
			local ok, handlerSuccess, handlerMessage = pcall(function()
				return action.handler(player, target, params)
			end)

			if ok then
				success = handlerSuccess == true
				resultMessage = tostring(handlerMessage or (success and "Action completed." or "Action failed."))
			else
				success = false
				resultMessage = tostring(handlerSuccess)
			end

			addAuditEntry(player, target, actionId, success, resultMessage)

			local snapshot = buildTargetSnapshot(target, player, accessLevel)
			return {
				Success = success,
				Message = resultMessage,
				Snapshot = snapshot,
				AuditLog = getVisibleAuditEntries(player, accessLevel),
				Targets = getAvailableTargets(player, accessLevel),
				AccessLevel = accessLevel,
			}
		end
	end
end

function ManualTestController:Start()
	local function notifyPlayer(player: Player)
		local accessLevel = getAccessLevel(player)
		if accessLevel ~= "none" then
			showNotification(player, `Manual test tools ready ({accessLevel}).`, "Success")
		end
	end

	Players.PlayerAdded:Connect(function(player)
		task.delay(2, function()
			if player.Parent then
				notifyPlayer(player)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		notifyPlayer(player)
	end
end

return ManualTestController
