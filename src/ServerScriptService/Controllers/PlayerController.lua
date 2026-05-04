--!strict
-- LOCATION: ServerScriptService/Controllers/PlayerController

-- Services
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris") 
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Modules
local ProfileStoreModule = require(ServerScriptService.Modules.ProfileStore)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local LimitedTimeOfferConfiguration = require(ReplicatedStorage.Modules.LimitedTimeOfferConfiguration)
local ProfileReadyUtils = require(ReplicatedStorage.Modules.ProfileReadyUtils)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfigurations)
local SlotUnlockConfigurations = require(ReplicatedStorage.Modules.SlotUnlockConfigurations)
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)
local SharedInstancesBootstrap = require(ServerScriptService.Modules.SharedInstancesBootstrap)
local BadgeManager = require(ServerScriptService.Modules.BadgeManager)
local ItemManager 
local SlotManager 
local PickaxeController
local TutorialService
local AnalyticsFunnelsService
local AnalyticsEconomyService
local OfflineIncomeController
local BoosterService

-- [ CONFIGURATION ]
local DATA_VERSION = "ProjectData_v90" 

local VIP_TAG = "V.I.P"
local COLLECT_ALL_GAMEPASS = ProductConfigurations.GamePasses.CollectAll or 1783037385
local VIP_SUBSCRIPTION_NAME = "VipSubscription"
local VIP_SUBSCRIPTION_ID = ProductConfigurations.Subscriptions and ProductConfigurations.Subscriptions[VIP_SUBSCRIPTION_NAME] or ""
local LIMITED_TIME_COLLECT_ALL_DURATION = math.max(0, math.floor(tonumber(LimitedTimeOfferConfiguration.OfferDurationSeconds) or 0))

local GROUP_ID = 0 
local CURRENT_TUTORIAL_VERSION = 6
local CURRENT_TUTORIAL_FUNNEL_KEY = "Tutor_30_04"
local RECENT_TUTORIAL_FUNNEL_KEY = "Tutor_29_04"
local PREVIOUS_RECENT_TUTORIAL_FUNNEL_KEY = "Tutor_28_04"
local PREVIOUS_TUTORIAL_FUNNEL_KEY = "Tutor_27_04"
local LEGACY_TUTORIAL_FUNNEL_KEY = "Tutor_24_04"
local OLDEST_TUTORIAL_FUNNEL_KEY = "Tutor_23_04"
local OLDEST_LEGACY_TUTORIAL_FUNNEL_KEY = "Tutor_22_04"
local ORIGINAL_TUTORIAL_FUNNEL_KEY = "TutorialFTUE"
local CURRENT_TUTORIAL_FUNNEL_MAX_STEP = TutorialConfiguration.FinalStep

local function remapLegacyTutorialFunnelStep(step: any): number
	local legacyStep = math.max(0, math.floor(tonumber(step) or 0))

	if legacyStep <= 6 then
		return math.clamp(legacyStep, 0, CURRENT_TUTORIAL_FUNNEL_MAX_STEP)
	end

	if legacyStep <= 11 then
		return math.clamp(legacyStep - 1, 0, CURRENT_TUTORIAL_FUNNEL_MAX_STEP)
	end

	return math.clamp(legacyStep - 2, 0, CURRENT_TUTORIAL_FUNNEL_MAX_STEP)
end

local function remapVersionThreeTutorialFunnelStep(step: any): number
	local legacyStep = math.max(0, math.floor(tonumber(step) or 0))

	if legacyStep <= 6 then
		return math.clamp(legacyStep, 0, CURRENT_TUTORIAL_FUNNEL_MAX_STEP)
	end
	if legacyStep == 7 then
		return 8
	end
	if legacyStep == 8 then
		return 9
	end

	return math.clamp(TutorialConfiguration.FinalStep, 0, CURRENT_TUTORIAL_FUNNEL_MAX_STEP)
end

local function remapPreviousTutorialFunnelStep(step: any): number
	local legacyStep = math.max(0, math.floor(tonumber(step) or 0))
	if legacyStep <= 10 then
		return math.clamp(legacyStep, 0, CURRENT_TUTORIAL_FUNNEL_MAX_STEP)
	end
	if legacyStep >= 11 then
		return CURRENT_TUTORIAL_FUNNEL_MAX_STEP
	end
	return legacyStep
end

local function remapStoredTutorialFunnelStep(step: any, tutorialVersion: number): number
	if tutorialVersion < 3 then
		return remapVersionThreeTutorialFunnelStep(remapLegacyTutorialFunnelStep(step))
	end

	if tutorialVersion < 4 then
		return remapVersionThreeTutorialFunnelStep(step)
	end

	if tutorialVersion < CURRENT_TUTORIAL_VERSION then
		return remapPreviousTutorialFunnelStep(step)
	end

	return math.clamp(math.max(0, math.floor(tonumber(step) or 0)), 0, CURRENT_TUTORIAL_FUNNEL_MAX_STEP)
end

-- Data Types
type ItemData = { Name: string, Mutation: string, Rarity: string, Level: number }
type SlotData = { Item: ItemData?, Level: number, Stored: number }
type FloorData = { [string]: SlotData }

type PlayerData = {
	Money: number,
	TotalMoneyEarned: number,
	Rebirths: number,
	TimePlayed: number, -- ## ADDED ##
	BaseLevel: number,
	unlocked_slots: number,
	OnboardingStep: number,
	PostTutorialStage: number,
	TutorialSkipped: boolean,
	TutorialVersion: number,
	TutorialFreeCharacterUpgradeConsumed: boolean,
	TutorialFreeBaseUpgradeConsumed: boolean,
	TutorialSpecialBrainrotGranted: boolean,
	OnboardingFunnelStep: number,
	AnalyticsFunnels: {[string]: any},
	LastSaveTime: number,
	SpinNumber: number,
	LastDailySpin: number,
	CandyCount: number,
	CandyPaidSpinCount: number,
	TotalBrainrotsCollected: number,
	Inventory: {ItemData},
	Plots: { [string]: FloorData },
	DiscoveredItems: {[string]: boolean},
	ClaimedPacks: {[string]: boolean},
	RedeemedCodes: {[string]: boolean},
	LimitedTimeOffers: {[string]: any},
	Boosters: {
		MegaExplosionEndsAt: number,
		ShieldEndsAt: number,
	},
	BoosterCharges: {[string]: number},
	Subscriptions: {[string]: any},
	OfflineIncome: {
		PendingBaseAmount: number,
		PendingSeconds: number,
		PendingGeneratedAt: number,
	},
	[string]: any 
}

-- [ DATA TEMPLATE ]
local Template: PlayerData = {
	Money = 0,
	TotalMoneyEarned = 0,
	Rebirths = 0,
	TimePlayed = 0, -- ## ADDED ##
	BaseLevel = 0,
	unlocked_slots = SlotUnlockConfigurations.StartSlots,
	OnboardingStep = 1,
	PostTutorialStage = 0,
	TutorialSkipped = false,
	TutorialVersion = CURRENT_TUTORIAL_VERSION,
	TutorialFreeCharacterUpgradeConsumed = false,
	TutorialFreeBaseUpgradeConsumed = false,
	TutorialSpecialBrainrotGranted = false,
	OnboardingFunnelStep = 0,
	AnalyticsFunnels = {
		OneTime = {},
		Markers = {},
	},
	LastSaveTime = 0,
	SpinNumber = 0,     
	LastDailySpin = 0,   
	CandyCount = 0,
	CandyPaidSpinCount = 0,
	TotalBrainrotsCollected = 0,
	Inventory = {},
	Plots = { Floor1 = {}, Floor2 = {}, Floor3 = {} },
	DiscoveredItems = {},
	ClaimedPacks = {},
	RedeemedCodes = {},
	LimitedTimeOffers = {
		CollectAllStartTime = 0,
	},
	Boosters = {
		MegaExplosionEndsAt = 0,
		ShieldEndsAt = 0,
	},
	BoosterCharges = {
		MegaExplosion = 0,
		Shield = 0,
		NukeBooster = 0,
	},
	Subscriptions = {
		VipSubscription = {
			BrainrotGranted = false,
			ClaimedPaidCycles = {},
		},
	},
	OfflineIncome = {
		PendingBaseAmount = 0,
		PendingSeconds = 0,
		PendingGeneratedAt = 0,
	},
	OwnedPickaxes = { ["Bomb 1"] = true },
	EquippedPickaxe = "Bomb 1",
}

for _, config in ipairs(UpgradesConfiguration.Upgrades) do
	local statId = config.StatId
	if type(statId) == "string" and statId ~= "" then
		Template[statId] = math.max(0, tonumber(config.DefaultValue) or 0)
	end
end

local GameProfileStore = ProfileStoreModule.New(DATA_VERSION, Template)

local PlayerController = {}
local profiles: {[Player]: any} = {}
local vipCache: {[Player]: boolean} = {}
local vipSubscriptionSyncQueued: {[Player]: boolean} = {}
local deadPlayers: {[Player]: boolean} = {} 
local loadingInventory: {[Player]: boolean} = {}
local DEBUG_BRAINROT_TRACE = false
local BASE_WALK_SPEED = 20
local timedWalkSpeedOverride: number? = nil

PlayerController.isShuttingDown = false

local function getProfileWalkSpeed(profile): number
	local data = profile and profile.Data
	local bonusSpeed = data and math.max(0, tonumber(data.BonusSpeed) or 0) or 0
	return BASE_WALK_SPEED + bonusSpeed
end

local function applyWalkSpeed(player: Player): number
	local profile = profiles[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local walkSpeed = if timedWalkSpeedOverride then timedWalkSpeedOverride else getProfileWalkSpeed(profile)

	if humanoid then
		humanoid.WalkSpeed = walkSpeed
	end

	return walkSpeed
end

local function isTrackedTool(tool: Tool): boolean
	local originalName = tool:GetAttribute("OriginalName")
	return tool:GetAttribute("OriginalName") ~= nil
		or tool:GetAttribute("IsLuckyBlock") == true
		or BombsConfigurations.Bombs[tool.Name] ~= nil
		or (type(originalName) == "string" and BombsConfigurations.Bombs[originalName] ~= nil)
end

local function isCriticalTraceTool(tool: Tool): boolean
	return tool:GetAttribute("Mutation") ~= nil or tool:GetAttribute("IsLuckyBlock") == true
end

local function summarizeTool(tool: Tool): string
	local originalName = tool:GetAttribute("OriginalName")
	local mutation = tool:GetAttribute("Mutation")
	local rarity = tool:GetAttribute("Rarity")
	local level = tool:GetAttribute("Level")
	local isLuckyBlock = tool:GetAttribute("IsLuckyBlock") == true
	local isBomb = BombsConfigurations.Bombs[tool.Name] ~= nil
		or (type(originalName) == "string" and BombsConfigurations.Bombs[originalName] ~= nil)
	local toolKind = if isLuckyBlock then "LuckyBlock" elseif isBomb then "Bomb" elseif mutation ~= nil then "Brainrot" else "Tool"
	return ("%s{name=%s,orig=%s,mut=%s,rar=%s,lvl=%s,parent=%s}"):format(
		toolKind,
		tostring(tool.Name),
		tostring(originalName),
		tostring(mutation),
		tostring(rarity),
		tostring(level),
		tostring(tool.Parent and tool.Parent.Name or "nil")
	)
end

local function summarizeToolContainer(container: Instance?): string
	if not container then
		return "[]"
	end

	local entries = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and isTrackedTool(child) then
			table.insert(entries, summarizeTool(child))
		end
	end

	table.sort(entries)
	return "[" .. table.concat(entries, ", ") .. "]"
end

local function summarizeInventoryEntries(entries): string
	if type(entries) ~= "table" or #entries == 0 then
		return "[]"
	end

	local summary = {}
	for index, itemData in ipairs(entries) do
		table.insert(summary, ("#%d{name=%s,mut=%s,rar=%s,lvl=%s}"):format(
			index,
			tostring(itemData.Name),
			tostring(itemData.Mutation),
			tostring(itemData.Rarity),
			tostring(itemData.Level)
		))
	end

	return "[" .. table.concat(summary, ", ") .. "]"
end

local function logBrainrotTrace(player: Player?, message: string, profileInventoryOverride)
	if not DEBUG_BRAINROT_TRACE then
		return
	end

	local playerName = player and player.Name or "nil"
	local profile = if player then profiles[player] else nil
	local profileInventory = profileInventoryOverride
	if profileInventory == nil and profile and profile.Data then
		profileInventory = profile.Data.Inventory
	end

	local backpack = if player then player:FindFirstChild("Backpack") else nil
	local starterGear = if player then player:FindFirstChild("StarterGear") else nil
	print(("[BrainrotTrace][PlayerController][%s][step=%s][loading=%s][ready=%s][server=%.3f] %s | char=%s | backpack=%s | starter=%s | profileInv=%s"):format(
		playerName,
		tostring(player and player:GetAttribute("OnboardingStep") or nil),
		tostring(player and loadingInventory[player] == true or false),
		tostring(player and ProfileReadyUtils.IsReady(player) or false),
		Workspace:GetServerTimeNow(),
		message,
		summarizeToolContainer(player and player.Character or nil),
		summarizeToolContainer(backpack),
		summarizeToolContainer(starterGear),
		summarizeInventoryEntries(profileInventory)
	))
end

local function shouldTraceCriticalTutorialWindow(player: Player?): boolean
	if not player then
		return false
	end

	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep == 4 or onboardingStep == 5
end

local function logCriticalInventoryTrace(player: Player?, message: string)
	if not DEBUG_BRAINROT_TRACE or not shouldTraceCriticalTutorialWindow(player) then
		return
	end

	print(("[BrainrotTrace][PlayerController][%s][step=%s][server=%.3f] %s"):format(
		tostring(player and player.Name or "nil"),
		tostring(player and player:GetAttribute("OnboardingStep") or nil),
		Workspace:GetServerTimeNow(),
		message
	))
end

local function logHardToolRemovalTrace(player: Player, scope: string, tool: Tool)
	if not DEBUG_BRAINROT_TRACE or not isCriticalTraceTool(tool) then
		return
	end

	print(("[%s][%s] %s parent=%s"):format(
		scope,
		player.Name,
		summarizeTool(tool),
		tostring(tool.Parent and tool.Parent:GetFullName() or "nil")
	))
	warn(debug.traceback())
end

local function logHumanoidDeathTrace(player: Player)
	if not DEBUG_BRAINROT_TRACE then
		return
	end

	warn(("[HUMANOID DIED - TOOL CLEANUP TRIGGER][%s]"):format(player.Name))
	warn(debug.traceback())
end

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

local function getUpgradeDefaultValue(config): number
	return math.max(0, tonumber(config.DefaultValue) or 0)
end

local function normalizeUpgradeValue(config, value): number
	local defaultValue = getUpgradeDefaultValue(config)
	return math.max(defaultValue, tonumber(value) or defaultValue)
end

local function ensureUpgradeDefaults(data)
	if type(data) ~= "table" then
		return
	end

	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		local statId = config.StatId
		if type(statId) == "string" and statId ~= "" then
			data[statId] = normalizeUpgradeValue(config, data[statId])
		end
	end
end

local function ensureLimitedTimeOfferDefaults(data)
	if type(data) ~= "table" then
		return
	end

	if type(data.LimitedTimeOffers) ~= "table" then
		data.LimitedTimeOffers = {}
	end

	local offers = data.LimitedTimeOffers
	local collectAllStartTime = math.max(0, math.floor(tonumber(offers.CollectAllStartTime) or 0))
	if collectAllStartTime <= 0 then
		collectAllStartTime = os.time()
		offers.CollectAllStartTime = collectAllStartTime
	end
end

local function syncLimitedTimeOfferAttributes(player: Player, data)
	if type(data) ~= "table" then
		return
	end

	ensureLimitedTimeOfferDefaults(data)

	local offers = data.LimitedTimeOffers
	local collectAllStartTime = math.max(0, math.floor(tonumber(offers.CollectAllStartTime) or 0))
	local collectAllEndTime = collectAllStartTime + LIMITED_TIME_COLLECT_ALL_DURATION

	player:SetAttribute(LimitedTimeOfferConfiguration.StartAttribute, collectAllStartTime)
	player:SetAttribute(LimitedTimeOfferConfiguration.EndAttribute, collectAllEndTime)
end

local function syncCandyAttributes(player: Player, data)
	if type(data) ~= "table" then
		return
	end

	player:SetAttribute("CandyCount", math.max(0, math.floor(tonumber(data.CandyCount) or 0)))
	player:SetAttribute("CandyPaidSpinCount", math.max(0, math.floor(tonumber(data.CandyPaidSpinCount) or 0)))
end

local function playPurchaseEffects(player: Player)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local effectEvent = Events and Events:FindFirstChild("TriggerUIEffect")
	if effectEvent then effectEvent:FireClient(player, "HighlightLight") end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local Templates = ReplicatedStorage:FindFirstChild("Templates")
	local confettiTemplate = Templates and Templates:FindFirstChild("Confetti")

	if root and confettiTemplate then
		local confetti = confettiTemplate:Clone()
		confetti.Parent = root
		for _, child in ipairs(confetti:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child:Emit(child:GetAttribute("EmitCount") or 50)
			end
		end
		Debris:AddItem(confetti, 3)
	end
end

local function getTutorialService()
	if not TutorialService then
		local tutorialModule = ServerScriptService.Modules:FindFirstChild("TutorialService")
		if tutorialModule and tutorialModule:IsA("ModuleScript") then
			TutorialService = require(tutorialModule)
		end
	end

	return TutorialService
end

local function getPickaxeController()
	if not PickaxeController then
		local pickaxeModule = ServerScriptService.Controllers:FindFirstChild("PickaxeController")
		if pickaxeModule and pickaxeModule:IsA("ModuleScript") then
			PickaxeController = require(pickaxeModule)
		end
	end

	return PickaxeController
end

local function getAnalyticsFunnelsService()
	if not AnalyticsFunnelsService then
		local analyticsModule = ServerScriptService.Modules:FindFirstChild("AnalyticsFunnelsService")
		if analyticsModule and analyticsModule:IsA("ModuleScript") then
			AnalyticsFunnelsService = require(analyticsModule)
		end
	end

	return AnalyticsFunnelsService
end

local function getAnalyticsEconomyService()
	if not AnalyticsEconomyService then
		local analyticsModule = ServerScriptService.Modules:FindFirstChild("AnalyticsEconomyService")
		if analyticsModule and analyticsModule:IsA("ModuleScript") then
			AnalyticsEconomyService = require(analyticsModule)
		end
	end

	return AnalyticsEconomyService
end

local function getBoosterService()
	if not BoosterService then
		local boosterModule = ServerScriptService.Modules:FindFirstChild("BoosterService")
		if boosterModule and boosterModule:IsA("ModuleScript") then
			BoosterService = require(boosterModule)
		end
	end

	return BoosterService
end

local function ensureBoosterChargesData(data: {[string]: any}): {[string]: number}
	if type(data.BoosterCharges) ~= "table" then
		data.BoosterCharges = {
			MegaExplosion = 0,
			Shield = 0,
			NukeBooster = 0,
		}
	end

	for _, boosterName in ipairs({"MegaExplosion", "Shield", "NukeBooster"}) do
		data.BoosterCharges[boosterName] = math.max(0, math.floor(tonumber(data.BoosterCharges[boosterName]) or 0))
	end

	return data.BoosterCharges
end

local function ensureVipSubscriptionData(data: {[string]: any}): {[string]: any}
	if type(data.Subscriptions) ~= "table" then
		data.Subscriptions = {}
	end

	if type(data.Subscriptions[VIP_SUBSCRIPTION_NAME]) ~= "table" then
		data.Subscriptions[VIP_SUBSCRIPTION_NAME] = {}
	end

	local subscriptionData = data.Subscriptions[VIP_SUBSCRIPTION_NAME]
	subscriptionData.BrainrotGranted = subscriptionData.BrainrotGranted == true
	if type(subscriptionData.ClaimedPaidCycles) ~= "table" then
		subscriptionData.ClaimedPaidCycles = {}
	end

	return subscriptionData
end

local function getHighestOwnedPickaxe(data): string?
	local ownedPickaxes = data.OwnedPickaxes
	if type(ownedPickaxes) ~= "table" then
		return nil
	end

	local highestPickaxeName = nil
	local highestPrice = -1

	for pickaxeName, isOwned in pairs(ownedPickaxes) do
		if isOwned then
			local pickaxeData = BombsConfigurations.Bombs[pickaxeName]
			local price = pickaxeData and pickaxeData.Price or -1
			if price > highestPrice then
				highestPrice = price
				highestPickaxeName = pickaxeName
			end
		end
	end

	return highestPickaxeName
end

local function evaluateExistingBadgeProgress(player: Player, profile: any)
	BadgeManager:AwardWelcome(player)
	BadgeManager:EvaluateMoneyMilestones(player, profile.Data.Money or 0)
	BadgeManager:EvaluateOnboardingStep(player, profile.Data.OnboardingStep or 1)

	local highestOwnedPickaxe = getHighestOwnedPickaxe(profile.Data)
	if highestOwnedPickaxe then
		BadgeManager:EvaluatePickaxeMilestones(player, highestOwnedPickaxe)
	end

	local inventory = profile.Data.Inventory
	local totalCollected = profile.Data.TotalBrainrotsCollected or 0
	local sawAnyBrainrot = false
	local sawLegendary = false
	local sawMythic = false

	if type(inventory) == "table" then
		for _, itemData in ipairs(inventory) do
			if type(itemData) == "table" and type(itemData.Rarity) == "string" then
				sawAnyBrainrot = true
				if itemData.Rarity == "Legendary" then
					sawLegendary = true
				elseif itemData.Rarity == "Mythic" then
					sawMythic = true
				end
			end
		end
	end

	if totalCollected > 0 or sawAnyBrainrot then
		BadgeManager:EvaluateBrainrotMilestones(player, nil, math.max(totalCollected, sawAnyBrainrot and 1 or 0))
	end

	if sawLegendary then
		BadgeManager:EvaluateBrainrotMilestones(player, "Legendary", totalCollected)
	end

	if sawMythic then
		BadgeManager:EvaluateBrainrotMilestones(player, "Mythic", totalCollected)
	end
end

local function grantPackRewards(player: Player, packName: string)
	local profile = profiles[player]
	if not profile then return end
	if profile.Data.ClaimedPacks[packName] then
		player:SetAttribute(packName, true)
		return
	end

	local rewards = ProductConfigurations.PackRewards[packName]
	if not rewards then return end
	local analyticsEconomyService = getAnalyticsEconomyService()
	local transactionTypes = analyticsEconomyService and analyticsEconomyService:GetTransactionTypes() or nil

	profile.Data.ClaimedPacks[packName] = true
	player:SetAttribute(packName, true)
	if analyticsEconomyService and rewards.Money > 0 then
		analyticsEconomyService:FlushBombIncome(player)
	end
	PlayerController:AddMoney(player, rewards.Money)
	if analyticsEconomyService and transactionTypes and rewards.Money > 0 then
		analyticsEconomyService:LogCashSource(player, rewards.Money, transactionTypes.IAP, `Pack:{packName}`, {
			feature = "pack",
			content_id = packName,
			context = "shop",
		})
		analyticsEconomyService:LogEntitlementGranted(player, "Pack", packName, rewards.Money, {
			feature = "pack",
			content_id = packName,
			context = "shop",
		})
	end

	if ItemManager then
		for _, item in ipairs(rewards.Items) do
			local itemConf = ItemConfigurations.GetItemData(item.Name)
			local rarity = itemConf and itemConf.Rarity or "Common"
			local tool = ItemManager.GiveItemToPlayer(player, item.Name, item.Mutation, rarity, item.Level)
			if tool and analyticsEconomyService and transactionTypes then
				analyticsEconomyService:LogItemValueSourceForItem(
					player,
					item.Name,
					item.Mutation,
					item.Level,
					transactionTypes.IAP,
					`ItemIAP:{packName}_{item.Name}`,
					{
						feature = "pack_item",
						content_id = item.Name,
						context = "shop",
						rarity = rarity,
						mutation = item.Mutation,
					}
				)
			end
		end
	end

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")
	if notif then notif:FireClient(player, "Gamepass bought!", "Success") end
	playPurchaseEffects(player) 
end

function PlayerController:IsVIP(player: Player)
	return player:GetAttribute("IsVIP") == true or vipCache[player] == true
end

local function checkVIP(player: Player)
	local passId = ProductConfigurations.GamePasses.VIP
	if not passId or passId <= 0 then
		vipCache[player] = false
		player:SetAttribute("IsVIP", player:GetAttribute("HasVipSubscription") == true)
		return
	end

	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)

	if success then
		vipCache[player] = hasPass == true
	end

	player:SetAttribute("IsVIP", vipCache[player] == true or player:GetAttribute("HasVipSubscription") == true)
end

local function syncEntitlementAttribute(player: Player, attributeName: string, passId: number?)
	local subscriptionGrantsAttribute = player:GetAttribute("HasVipSubscription") == true
		and (attributeName == "HasAutoBomb" or attributeName == "HasCollectAll")

	if type(passId) ~= "number" or passId <= 0 then
		player:SetAttribute(attributeName, subscriptionGrantsAttribute)
		return
	end

	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)

	player:SetAttribute(attributeName, (success and hasPass) == true or subscriptionGrantsAttribute)
end

local function getDateTimeCycleToken(value: any): string?
	if typeof(value) == "DateTime" then
		return tostring(value.UnixTimestamp)
	end

	local numericValue = tonumber(value)
	if numericValue then
		return tostring(math.floor(numericValue))
	end

	if value ~= nil then
		return tostring(value)
	end

	return nil
end

local function getPaidCycleKey(entry: any): string?
	if type(entry) ~= "table" then
		return nil
	end

	local paymentStatus = tostring(entry.PaymentStatus)
	if string.find(paymentStatus, "Paid", 1, true) == nil or string.find(paymentStatus, "Refunded", 1, true) ~= nil then
		return nil
	end

	local startToken = getDateTimeCycleToken(entry.CycleStartTime)
	local endToken = getDateTimeCycleToken(entry.CycleEndTime)
	if not startToken and not endToken then
		return nil
	end

	return tostring(startToken or "unknown") .. ":" .. tostring(endToken or "unknown")
end

local function getLatestPaidVipSubscriptionCycleKey(player: Player): string?
	if type(VIP_SUBSCRIPTION_ID) ~= "string" or VIP_SUBSCRIPTION_ID == "" then
		return nil
	end

	local success, history = pcall(function()
		return MarketplaceService:GetUserSubscriptionPaymentHistoryAsync(player, VIP_SUBSCRIPTION_ID)
	end)

	if not success then
		warn("[PlayerController] Failed to fetch VipSubscription payment history:", player.Name, history)
		return nil
	end

	if type(history) ~= "table" then
		return nil
	end

	return getPaidCycleKey(history[1])
end

local function grantVipSubscriptionBrainrot(player: Player, profile: any, subscriptionData: {[string]: any}, rewardConfig: {[string]: any}): boolean
	if subscriptionData.BrainrotGranted == true then
		return false
	end

	local brainrotReward = rewardConfig.Brainrot
	if type(brainrotReward) ~= "table" then
		return false
	end

	if not ItemManager then
		ItemManager = require(ServerScriptService.Modules.ItemManager)
	end

	local itemName = brainrotReward.Name
	if type(itemName) ~= "string" or itemName == "" then
		return false
	end

	local mutation = if type(brainrotReward.Mutation) == "string" and brainrotReward.Mutation ~= "" then brainrotReward.Mutation else "Neon"
	local level = math.max(1, math.floor(tonumber(brainrotReward.Level) or 1))
	local itemConfig = ItemConfigurations.GetItemData(itemName)
	local rarity = itemConfig and itemConfig.Rarity or "Legendary"
	local displayName = itemConfig and itemConfig.DisplayName or itemName
	local tool = ItemManager.GiveItemToPlayer(player, itemName, mutation, rarity, level)
	if not tool then
		warn("[PlayerController] Failed to grant VipSubscription brainrot:", player.Name, itemName)
		return false
	end

	subscriptionData.BrainrotGranted = true
	local totalCollected = PlayerController:IncrementBrainrotsCollected(player, 1)
	BadgeManager:EvaluateBrainrotMilestones(player, rarity, totalCollected)

	local analyticsEconomyService = getAnalyticsEconomyService()
	local transactionTypes = analyticsEconomyService and analyticsEconomyService:GetTransactionTypes() or nil
	if analyticsEconomyService and transactionTypes then
		analyticsEconomyService:LogItemValueSourceForItem(
			player,
			itemName,
			mutation,
			level,
			transactionTypes.IAP,
			"Subscription:VipSubscriptionBrainrot",
			{
				feature = "subscription_item",
				content_id = itemName,
				context = "vip_subscription",
				rarity = rarity,
				mutation = mutation,
			}
		)
	end

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")
	if notif and notif:IsA("RemoteEvent") then
		notif:FireClient(player, displayName .. " claimed from VIP Subscription!", "Success")
	end

	return true
end

local function grantVipSubscriptionPaidCycleRewards(player: Player, profile: any, paidCycleKeyOverride: string?): boolean
	if not profile or type(profile.Data) ~= "table" then
		return false
	end

	local rewardConfig = ProductConfigurations.SubscriptionRewards and ProductConfigurations.SubscriptionRewards[VIP_SUBSCRIPTION_NAME]
	if type(rewardConfig) ~= "table" then
		return false
	end

	local paidCycleKey = paidCycleKeyOverride or getLatestPaidVipSubscriptionCycleKey(player)
	if not paidCycleKey then
		return false
	end

	local subscriptionData = ensureVipSubscriptionData(profile.Data)
	local grantedAnything = grantVipSubscriptionBrainrot(player, profile, subscriptionData, rewardConfig)

	if subscriptionData.ClaimedPaidCycles[paidCycleKey] ~= true then
		local boosterService = getBoosterService()
		local monthlyBoosters = rewardConfig.MonthlyBoosters
		if boosterService and boosterService.AddBoosterCharges and type(monthlyBoosters) == "table" then
			if boosterService:AddBoosterCharges(player, monthlyBoosters, VIP_SUBSCRIPTION_NAME) then
				subscriptionData.ClaimedPaidCycles[paidCycleKey] = true
				grantedAnything = true

				local analyticsEconomyService = getAnalyticsEconomyService()
				if analyticsEconomyService then
					analyticsEconomyService:LogEntitlementGranted(player, "VipSubscriptionMonthlyBoostPack", paidCycleKey, nil, {
						feature = "vip_subscription",
						content_id = VIP_SUBSCRIPTION_NAME,
						context = "subscription_cycle",
					})
				end

				local analyticsFunnelsService = getAnalyticsFunnelsService()
				if analyticsFunnelsService then
					analyticsFunnelsService:HandleStorePurchaseSuccess(player, {
						purchaseKind = "subscription",
						id = VIP_SUBSCRIPTION_ID,
						productName = VIP_SUBSCRIPTION_NAME,
						paymentType = "subscription",
						surface = "shop_frame",
					})
				end

				local Events = ReplicatedStorage:FindFirstChild("Events")
				local notif = Events and Events:FindFirstChild("ShowNotification")
				if notif and notif:IsA("RemoteEvent") then
					notif:FireClient(player, "VIP monthly boost pack claimed!", "Success")
				end
			end
		end
	end

	if grantedAnything then
		playPurchaseEffects(player)
	end

	return grantedAnything
end

local function applyVipSubscriptionEntitlements(player: Player, isActive: boolean)
	player:SetAttribute("HasVipSubscription", isActive)

	if isActive then
		player:SetAttribute("IsVIP", true)
		player:SetAttribute("HasCollectAll", true)
		player:SetAttribute("HasAutoBomb", true)
	else
		checkVIP(player)
		syncEntitlementAttribute(player, "HasCollectAll", ProductConfigurations.GamePasses.CollectAll)
		syncEntitlementAttribute(player, "HasAutoBomb", ProductConfigurations.GamePasses.AutoBomb)
		if player:GetAttribute("HasAutoBomb") ~= true then
			player:SetAttribute("AutoBombEnabled", false)
		end
	end

	if SlotManager and SlotManager.RefreshAllSlots then
		SlotManager.RefreshAllSlots(player)
	end
end

local function syncVipSubscriptionStatus(player: Player, reason: string?)
	if player.Parent ~= Players or type(VIP_SUBSCRIPTION_ID) ~= "string" or VIP_SUBSCRIPTION_ID == "" then
		return
	end

	local success, status = pcall(function()
		return MarketplaceService:GetUserSubscriptionStatusAsync(player, VIP_SUBSCRIPTION_ID)
	end)

	if not success then
		warn("[PlayerController] Failed to fetch VipSubscription status:", player.Name, reason, status)
		return
	end

	local isActive = type(status) == "table" and status.IsSubscribed == true
	applyVipSubscriptionEntitlements(player, isActive)

	if isActive then
		local profile = profiles[player]
		if profile then
			grantVipSubscriptionPaidCycleRewards(player, profile)
		end
	end
end

local function queueVipSubscriptionSync(player: Player, reason: string?)
	if vipSubscriptionSyncQueued[player] == true then
		return
	end

	vipSubscriptionSyncQueued[player] = true
	task.spawn(function()
		vipSubscriptionSyncQueued[player] = nil
		syncVipSubscriptionStatus(player, reason)
	end)
end

local function grantVipSubscriptionStudioButtonRewards(player: Player)
	if not RunService:IsStudio() then
		return
	end

	local profile = profiles[player]
	if not profile then
		return
	end

	applyVipSubscriptionEntitlements(player, true)
	grantVipSubscriptionPaidCycleRewards(player, profile, "StudioButton:" .. tostring(os.time()))
end

local function setupVIPTouch(part: BasePart)
	if part:GetAttribute("TouchConnected") then return end
	part:SetAttribute("TouchConnected", true)

	part.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and not PlayerController:IsVIP(player) then
			if not player.Character:GetAttribute("PromptDebounce") then
				player.Character:SetAttribute("PromptDebounce", true)
				local passId = ProductConfigurations.GamePasses.VIP
				if passId then MarketplaceService:PromptGamePassPurchase(player, passId) end
				task.wait(2)
				if player.Character then player.Character:SetAttribute("PromptDebounce", nil) end
			end
		end
	end)
end

local function calculateOfflineEarnings(player: Player, profile: any)
	if OfflineIncomeController and OfflineIncomeController.QueueOfflineIncomeForJoin then
		OfflineIncomeController:QueueOfflineIncomeForJoin(player, profile)
		OfflineIncomeController:PushStatus(player)
	end
end

local function clearStoredSlotIncomeForJoin(profile: any)
	if not profile or not profile.Data or type(profile.Data.Plots) ~= "table" then
		return
	end

	for _, floorData in pairs(profile.Data.Plots) do
		if type(floorData) == "table" then
			for _, slotData in pairs(floorData) do
				if type(slotData) == "table" then
					slotData.Stored = 0
				end
			end
		end
	end
end

local function checkAndGrantGroupReward(player: Player, profile: any)
	if profile.Data.ClaimedPacks["GroupReward"] then return end
	local currentStep = profile.Data.OnboardingStep or 1
	if currentStep < TutorialConfiguration.FinalStep then return end

	local targetGroupId = GROUP_ID
	if targetGroupId <= 0 then return end 

	task.spawn(function()
		local success, isInGroup = pcall(function() return player:IsInGroup(targetGroupId) end)
		if success and isInGroup then
			profile.Data.ClaimedPacks["GroupReward"] = true
			local analyticsEconomyService = getAnalyticsEconomyService()
			local transactionTypes = analyticsEconomyService and analyticsEconomyService:GetTransactionTypes() or nil
			if analyticsEconomyService then
				analyticsEconomyService:FlushBombIncome(player)
			end
			PlayerController:AddMoney(player, 1000)
			if analyticsEconomyService and transactionTypes then
				analyticsEconomyService:LogCashSource(player, 1000, transactionTypes.Onboarding, "GroupRewardCash", {
					feature = "group_reward",
					content_id = "GroupRewardCash",
					context = "onboarding",
				})
			end
			local analyticsFunnelsService = getAnalyticsFunnelsService()
			if analyticsFunnelsService then
				analyticsFunnelsService:HandleAutoGroupRewardGranted(player)
			end
			local Events = ReplicatedStorage:FindFirstChild("Events")
			local notif = Events and Events:FindFirstChild("ShowNotification")
			if notif then notif:FireClient(player, "Thanks for joining the group! +$1,000", "Success") end
		end
	end)
end

function PlayerController:GetProfile(player: Player) return profiles[player] end

function PlayerController:DeductMoney(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile then return false end
	if profile.Data.Money >= amount then
		profile.Data.Money -= amount
		player.leaderstats.Money.Value = profile.Data.Money
		return true
	end
	return false
end

function PlayerController:AddMoney(player: Player, amount: number)
	local profile = profiles[player]
	if profile then
		profile.Data.Money += amount
		if amount > 0 then
			profile.Data.TotalMoneyEarned = (tonumber(profile.Data.TotalMoneyEarned) or 0) + amount
			player:SetAttribute("TotalMoneyEarned", profile.Data.TotalMoneyEarned)
		end
		player.leaderstats.Money.Value = profile.Data.Money
		BadgeManager:EvaluateMoneyMilestones(player, profile.Data.Money)

		local tutorialService = getTutorialService()
		if tutorialService then
			tutorialService:HandleMoneyChanged(player)
		end

		local analyticsFunnelsService = getAnalyticsFunnelsService()
		if analyticsFunnelsService then
			analyticsFunnelsService:HandleMoneyBalanceChanged(player)
		end
	end
end

function PlayerController:IncrementBaseLevel(player: Player)
	local profile = profiles[player]
	if profile then profile.Data.BaseLevel += 1; return profile.Data.BaseLevel end
	return 0
end

function PlayerController:GetUnlockedSlots(player: Player): number
	local profile = profiles[player]
	if not profile then
		return SlotUnlockConfigurations.StartSlots
	end

	local unlockedSlots = profile.Data.unlocked_slots
	if type(unlockedSlots) ~= "number" then
		local legacyBaseLevel = tonumber(profile.Data.BaseLevel) or 0
		unlockedSlots = SlotUnlockConfigurations.StartSlots + (legacyBaseLevel * 10)
		profile.Data.unlocked_slots = SlotUnlockConfigurations.ClampSlots(unlockedSlots)
	end

	return SlotUnlockConfigurations.ClampSlots(profile.Data.unlocked_slots)
end

function PlayerController:AddUnlockedSlots(player: Player, amount: number): number
	local profile = profiles[player]
	if not profile then
		return SlotUnlockConfigurations.StartSlots
	end

	local currentSlots = self:GetUnlockedSlots(player)
	local updatedSlots = SlotUnlockConfigurations.ClampSlots(currentSlots + amount)
	profile.Data.unlocked_slots = updatedSlots
	player:SetAttribute("UnlockedSlots", updatedSlots)
	return updatedSlots
end

function PlayerController:IncrementBrainrotsCollected(player: Player, amount: number?): number
	local profile = profiles[player]
	if not profile then
		return 0
	end

	local increment = math.max(0, math.floor(tonumber(amount) or 1))
	profile.Data.TotalBrainrotsCollected = math.max(0, tonumber(profile.Data.TotalBrainrotsCollected) or 0) + increment
	player:SetAttribute("TotalBrainrotsCollected", profile.Data.TotalBrainrotsCollected)
	local analyticsFunnelsService = getAnalyticsFunnelsService()
	if analyticsFunnelsService and analyticsFunnelsService.HandleBrainrotsCollectedChanged then
		analyticsFunnelsService:HandleBrainrotsCollectedChanged(player, profile.Data.TotalBrainrotsCollected)
	end
	return profile.Data.TotalBrainrotsCollected
end

function PlayerController:GetCandyCount(player: Player): number
	local profile = profiles[player]
	if not profile or not profile.Data then
		return 0
	end

	return math.max(0, math.floor(tonumber(profile.Data.CandyCount) or 0))
end

function PlayerController:AddCandies(player: Player, amount: number?): number
	local profile = profiles[player]
	if not profile or not profile.Data then
		return 0
	end

	local increment = math.max(0, math.floor(tonumber(amount) or 0))
	profile.Data.CandyCount = math.max(0, math.floor(tonumber(profile.Data.CandyCount) or 0) + increment)
	player:SetAttribute("CandyCount", profile.Data.CandyCount)
	return profile.Data.CandyCount
end

function PlayerController:AddPaidCandySpins(player: Player, amount: number?): number
	local profile = profiles[player]
	if not profile or not profile.Data then
		return 0
	end

	local increment = math.max(0, math.floor(tonumber(amount) or 0))
	profile.Data.CandyPaidSpinCount = math.max(0, math.floor(tonumber(profile.Data.CandyPaidSpinCount) or 0) + increment)
	player:SetAttribute("CandyPaidSpinCount", profile.Data.CandyPaidSpinCount)
	return profile.Data.CandyPaidSpinCount
end

function PlayerController:ConsumeCandySpinCost(player: Player, candyCost: number): (boolean, boolean)
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false, false
	end

	local resolvedCost = math.max(0, math.floor(tonumber(candyCost) or 0))
	local currentCandyCount = math.max(0, math.floor(tonumber(profile.Data.CandyCount) or 0))
	local currentPaidSpins = math.max(0, math.floor(tonumber(profile.Data.CandyPaidSpinCount) or 0))

	if resolvedCost > 0 and currentCandyCount >= resolvedCost then
		profile.Data.CandyCount = currentCandyCount - resolvedCost
		player:SetAttribute("CandyCount", profile.Data.CandyCount)
		return true, false
	end

	if currentPaidSpins > 0 then
		profile.Data.CandyPaidSpinCount = currentPaidSpins - 1
		player:SetAttribute("CandyPaidSpinCount", profile.Data.CandyPaidSpinCount)
		return true, true
	end

	return false, false
end

function PlayerController:AddUpgradeStat(player: Player, statId: string, amount: number?): number
	local profile = profiles[player]
	if not profile or not profile.Data or type(statId) ~= "string" or statId == "" then
		return 0
	end

	ensureUpgradeDefaults(profile.Data)

	local increment = math.max(0, math.floor(tonumber(amount) or 0))
	profile.Data[statId] = math.max(0, math.floor(tonumber(profile.Data[statId]) or 0) + increment)
	player:SetAttribute(statId, profile.Data[statId])

	if statId == "BonusSpeed" then
		applyWalkSpeed(player)
	end

	return profile.Data[statId]
end

function PlayerController:SetupSharedInstances()
	SharedInstancesBootstrap:Ensure()
end

local function toolToData(tool: Tool): ItemData?
	local name = tool:GetAttribute("OriginalName")
	if name then
		return { Name = name, Mutation = tool:GetAttribute("Mutation") or "Normal", Rarity = tool:GetAttribute("Rarity") or "Common", Level = tool:GetAttribute("Level") or 1 }
	end
	return nil
end

local function getInventoryItemKey(itemData: ItemData): string
	return `{itemData.Name}::{itemData.Mutation}::{itemData.Rarity}::{itemData.Level}`
end

local function isFtueBrainrotTool(tool: Tool): boolean
	if tool:GetAttribute("IsTemporary") == true then
		return false
	end

	local mutation = tool:GetAttribute("Mutation")
	if type(mutation) ~= "string" or mutation == "" then
		return false
	end

	local originalName = tool:GetAttribute("OriginalName")
	if type(originalName) ~= "string" or originalName == "" then
		return false
	end

	return BombsConfigurations.Bombs[tool.Name] == nil and BombsConfigurations.Bombs[originalName] == nil
end

local function shouldPreserveFtueBrainrotsBeforeHydrate(player: Player, profile: any): boolean
	if ProfileReadyUtils.IsReady(player) then
		return false
	end

	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep"))
	if onboardingStep == nil and profile and profile.Data then
		onboardingStep = tonumber(profile.Data.OnboardingStep)
	end

	return onboardingStep == 4 or onboardingStep == 5
end

local function collectFtueBrainrotInventoryFromContainer(container: Instance?): {ItemData}
	local inventoryEntries = {}

	if not container then
		return inventoryEntries
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and isFtueBrainrotTool(child) then
			local data = toolToData(child)
			if data then
				table.insert(inventoryEntries, data)
			end
		end
	end

	return inventoryEntries
end

local function collectLiveFtueBrainrotInventory(player: Player): {ItemData}
	local inventoryEntries = collectFtueBrainrotInventoryFromContainer(player.Character)

	for _, itemData in ipairs(collectFtueBrainrotInventoryFromContainer(player:FindFirstChild("Backpack"))) do
		table.insert(inventoryEntries, itemData)
	end

	return inventoryEntries
end

local function buildInventoryItemCounts(entries: {ItemData}): {[string]: number}
	local counts: {[string]: number} = {}
	for _, itemData in ipairs(entries) do
		local key = getInventoryItemKey(itemData)
		counts[key] = (counts[key] or 0) + 1
	end

	return counts
end

local function consumeInventoryItemCount(counts: {[string]: number}?, itemData: ItemData): boolean
	if not counts then
		return false
	end

	local key = getInventoryItemKey(itemData)
	local availableCount = counts[key] or 0
	if availableCount <= 0 then
		return false
	end

	counts[key] = availableCount - 1
	return true
end

function PlayerController:EnsureInventoryContainsItems(player: Player, items: {ItemData}, reason: string?): number
	local profile = profiles[player]
	if not profile or type(items) ~= "table" then
		return 0
	end

	if type(profile.Data.Inventory) ~= "table" then
		profile.Data.Inventory = {}
	end
	if type(profile.Data.DiscoveredItems) ~= "table" then
		profile.Data.DiscoveredItems = {}
	end

	local normalizedItems: {ItemData} = {}
	local requestedCounts: {[string]: number} = {}
	local liveCounts: {[string]: number} = {}
	local profileCounts = buildInventoryItemCounts(profile.Data.Inventory)
	local addedCount = 0
	local discoveredChanged = false

	for _, itemData in ipairs(items) do
		if type(itemData) ~= "table" then
			continue
		end

		local name = if type(itemData.Name) == "string" and itemData.Name ~= "" then itemData.Name else nil
		if not name then
			continue
		end

		local mutation = if type(itemData.Mutation) == "string" and itemData.Mutation ~= "" then itemData.Mutation else "Normal"
		local rarity = if type(itemData.Rarity) == "string" and itemData.Rarity ~= "" then itemData.Rarity else "Common"
		local level = math.max(1, math.floor(tonumber(itemData.Level) or 1))
		local normalizedItemData: ItemData = {
			Name = name,
			Mutation = mutation,
			Rarity = rarity,
			Level = level,
		}

		table.insert(normalizedItems, normalizedItemData)
		local itemKey = getInventoryItemKey(normalizedItemData)
		requestedCounts[itemKey] = (requestedCounts[itemKey] or 0) + 1

		local discoveryKey = mutation .. "_" .. name
		if not profile.Data.DiscoveredItems[discoveryKey] then
			profile.Data.DiscoveredItems[discoveryKey] = true
			discoveredChanged = true
		end
	end

	local function scanLiveContainer(container: Instance?)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsTemporary") ~= true then
				local data = toolToData(child)
				if data then
					local itemKey = getInventoryItemKey(data)
					liveCounts[itemKey] = (liveCounts[itemKey] or 0) + 1
				end
			end
		end
	end

	scanLiveContainer(player:FindFirstChild("Backpack"))
	scanLiveContainer(player.Character)

	local processedKeys: {[string]: boolean} = {}
	for _, itemData in ipairs(normalizedItems) do
		local itemKey = getInventoryItemKey(itemData)
		if processedKeys[itemKey] then
			continue
		end
		processedKeys[itemKey] = true

		local requiredCount = math.max(requestedCounts[itemKey] or 0, liveCounts[itemKey] or 0)
		while (profileCounts[itemKey] or 0) < requiredCount do
			table.insert(profile.Data.Inventory, {
				Name = itemData.Name,
				Mutation = itemData.Mutation,
				Rarity = itemData.Rarity,
				Level = itemData.Level,
			})
			profileCounts[itemKey] = (profileCounts[itemKey] or 0) + 1
			addedCount += 1
		end
	end

	logBrainrotTrace(player, ("EnsureInventoryContainsItems reason=%s added=%d"):format(
		tostring(reason or "unspecified"),
		addedCount
	), profile.Data.Inventory)

	if discoveredChanged then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local refresh = Events and Events:FindFirstChild("RefreshIndex")
		if refresh then refresh:FireClient(player) end
	end

	return addedCount
end

local function preserveLiveFtueBrainrotsBeforeHydrate(player: Player, profile: any)
	if not shouldPreserveFtueBrainrotsBeforeHydrate(player, profile) then
		return
	end

	if type(profile.Data.Inventory) ~= "table" then
		profile.Data.Inventory = {}
	end
	if type(profile.Data.DiscoveredItems) ~= "table" then
		profile.Data.DiscoveredItems = {}
	end

	local liveEntries = collectLiveFtueBrainrotInventory(player)
	logBrainrotTrace(player, ("preserveLiveFtueBrainrotsBeforeHydrate liveEntries=%s"):format(
		summarizeInventoryEntries(liveEntries)
	), profile.Data.Inventory)
	if #liveEntries == 0 then
		return
	end

	local availableSavedCounts = buildInventoryItemCounts(profile.Data.Inventory)

	for _, itemData in ipairs(liveEntries) do
		if not consumeInventoryItemCount(availableSavedCounts, itemData) then
			table.insert(profile.Data.Inventory, {
				Name = itemData.Name,
				Mutation = itemData.Mutation,
				Rarity = itemData.Rarity,
				Level = itemData.Level,
			})
		end

		profile.Data.DiscoveredItems[itemData.Mutation .. "_" .. itemData.Name] = true
	end

	logBrainrotTrace(player, "preserveLiveFtueBrainrotsBeforeHydrate merged", profile.Data.Inventory)
end

local function syncInventoryData(player: Player, reason: string?)
	local profile = profiles[player]
	if not profile then return end
	if deadPlayers[player] then return end

	local isSyncingFromSave = loadingInventory[player]
	local inventoryData = {}
	local newDiscovery = false
	local previousInventoryCount = if type(profile.Data.Inventory) == "table" then #profile.Data.Inventory else 0

	local function scanContainer(container: Instance)
		for _, item in ipairs(container:GetChildren()) do
			if item:IsA("Tool") then
				if item:GetAttribute("IsTemporary") == true then continue end
				local data = toolToData(item)
				if data then 
					if not isSyncingFromSave then table.insert(inventoryData, data) end
					local key = data.Mutation .. "_" .. data.Name
					if not profile.Data.DiscoveredItems[key] then
						profile.Data.DiscoveredItems[key] = true
						newDiscovery = true
					end
				end
			end
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then scanContainer(backpack) end
	if player.Character then scanContainer(player.Character) end

	if not isSyncingFromSave and #inventoryData < previousInventoryCount then
		logCriticalInventoryTrace(player, ("syncInventoryData shrank reason=%s inventory=%d->%d"):format(
			tostring(reason or "unspecified"),
			previousInventoryCount,
			#inventoryData
		))
	end

	if not isSyncingFromSave then profile.Data.Inventory = inventoryData end
	logBrainrotTrace(player, ("syncInventoryData reason=%s isSyncingFromSave=%s discoveredChanged=%s"):format(
		tostring(reason or "unspecified"),
		tostring(isSyncingFromSave),
		tostring(newDiscovery)
	), if not isSyncingFromSave then inventoryData else profile.Data.Inventory)

	if newDiscovery then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local refresh = Events and Events:FindFirstChild("RefreshIndex")
		if refresh then refresh:FireClient(player) end
	end
end

local function loadInventory(player: Player, profile: any)
	if not ItemManager then return end

	loadingInventory[player] = true
	deadPlayers[player] = false
	local preservedCharacterItemCounts: {[string]: number}? = nil
	local preservedCharacterEntries = {}
	if shouldPreserveFtueBrainrotsBeforeHydrate(player, profile) then
		preservedCharacterEntries = collectFtueBrainrotInventoryFromContainer(player.Character)
		preservedCharacterItemCounts = buildInventoryItemCounts(preservedCharacterEntries)
	end
	logBrainrotTrace(player, ("loadInventory begin preserveCharacter=%s"):format(
		summarizeInventoryEntries(preservedCharacterEntries)
	), profile.Data.Inventory)
	preserveLiveFtueBrainrotsBeforeHydrate(player, profile)

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		logBrainrotTrace(player, "loadInventory clearing Backpack", profile.Data.Inventory)
		backpack:ClearAllChildren()
		logBrainrotTrace(player, "loadInventory Backpack cleared", profile.Data.Inventory)
	end

	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear then
		logBrainrotTrace(player, "loadInventory clearing StarterGear", profile.Data.Inventory)
		starterGear:ClearAllChildren()
		logBrainrotTrace(player, "loadInventory StarterGear cleared", profile.Data.Inventory)
	end

	local savedInv = profile.Data.Inventory or {}
	for _, itemData in ipairs(savedInv) do
		local key = itemData.Mutation .. "_" .. itemData.Name
		local preservedOnCharacter = consumeInventoryItemCount(preservedCharacterItemCounts, itemData)
		if not preservedOnCharacter then
			ItemManager.GiveItemToPlayer(player, itemData.Name, itemData.Mutation, itemData.Rarity, itemData.Level)
		end
		logBrainrotTrace(player, ("loadInventory item name=%s mut=%s rar=%s lvl=%s preservedOnCharacter=%s"):format(
			tostring(itemData.Name),
			tostring(itemData.Mutation),
			tostring(itemData.Rarity),
			tostring(itemData.Level),
			tostring(preservedOnCharacter)
		), profile.Data.Inventory)
		if not profile.Data.DiscoveredItems[key] then profile.Data.DiscoveredItems[key] = true end
	end

	task.wait() 
	loadingInventory[player] = false
	syncInventoryData(player, "loadInventory:end")
	logBrainrotTrace(player, "loadInventory end", profile.Data.Inventory)
	if player.Parent and not ProfileReadyUtils.IsReady(player) then
		player:SetAttribute(ProfileReadyUtils.AttributeName, true)
	end

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local refresh = Events and Events:FindFirstChild("RefreshIndex")
	if refresh then refresh:FireClient(player) end

	local pickaxeController = getPickaxeController()
	if pickaxeController and pickaxeController.EnsureBombFirstSlot then
		task.defer(function()
			if player.Parent then
				pickaxeController.EnsureBombFirstSlot(player)
			end
		end)
	end
end

-- =========================================================
-- ## UPDATED: LEADERSTATS (ONLY MONEY)
-- =========================================================
local function createLeaderstats(player: Player, data: PlayerData)
	local ls = player:FindFirstChild("leaderstats")
	if not ls or not ls:IsA("Folder") then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end

	local moneyVal = ls:FindFirstChild("Money")
	if not moneyVal or not moneyVal:IsA("NumberValue") then
		moneyVal = Instance.new("NumberValue")
		moneyVal.Name = "Money"
		moneyVal.Parent = ls
	end
	moneyVal.Value = tonumber(data.Money) or 0

	if moneyVal:GetAttribute("ProfileBound") ~= true then
		moneyVal:SetAttribute("ProfileBound", true)
		moneyVal.Changed:Connect(function(newVal)
			local profile = profiles[player]
			if profile and profile.Data then
				profile.Data.Money = newVal
			end
		end)
	end

	-- Save everything else as Player Attributes!
	player:SetAttribute("Rebirths", data.Rebirths or 0)
	player:SetAttribute("OnboardingStep", data.OnboardingStep or 1)
	player:SetAttribute("PostTutorialStage", data.PostTutorialStage or 0)
	player:SetAttribute("TutorialSkipped", data.TutorialSkipped == true)
	player:SetAttribute("TutorialSpecialBrainrotGranted", data.TutorialSpecialBrainrotGranted == true)
	player:SetAttribute("SpinNumber", data.SpinNumber or 0)
	player:SetAttribute("LastDailySpin", data.LastDailySpin or 0)
	syncCandyAttributes(player, data)
	player:SetAttribute("UnlockedSlots", SlotUnlockConfigurations.ClampSlots(tonumber(data.unlocked_slots) or SlotUnlockConfigurations.StartSlots))

	-- Note: TimePlayed gets set continuously in the Start loop, but we can initialize it here:
	player:SetAttribute("TimePlayed", data.TimePlayed or 0)
	player:SetAttribute("TotalMoneyEarned", data.TotalMoneyEarned or 0)
	player:SetAttribute("TotalBrainrotsCollected", data.TotalBrainrotsCollected or 0)
	local boosters = if type(data.Boosters) == "table" then data.Boosters else {}
	player:SetAttribute("MegaExplosionEndsAt", math.max(0, tonumber(boosters.MegaExplosionEndsAt) or 0))
	player:SetAttribute("ShieldEndsAt", math.max(0, tonumber(boosters.ShieldEndsAt) or 0))
	local boosterCharges = ensureBoosterChargesData(data)
	player:SetAttribute("MegaExplosionCharges", math.max(0, tonumber(boosterCharges.MegaExplosion) or 0))
	player:SetAttribute("ShieldCharges", math.max(0, tonumber(boosterCharges.Shield) or 0))
	player:SetAttribute("NukeBoosterCharges", math.max(0, tonumber(boosterCharges.NukeBooster) or 0))
	player:SetAttribute("HasVipSubscription", player:GetAttribute("HasVipSubscription") == true)
	player:SetAttribute("HasAutoBomb", player:GetAttribute("HasAutoBomb") == true)
	player:SetAttribute("HasCollectAll", player:GetAttribute("HasCollectAll") == true)
	player:SetAttribute("AutoBombEnabled", false)
	player:SetAttribute("FriendBoostCount", tonumber(player:GetAttribute("FriendBoostCount")) or 0)
	player:SetAttribute("FriendBoostMultiplier", tonumber(player:GetAttribute("FriendBoostMultiplier")) or 1)
	local offlineIncome = if type(data.OfflineIncome) == "table" then data.OfflineIncome else {}
	player:SetAttribute("OfflineIncomePendingAmount", math.max(0, tonumber(offlineIncome.PendingBaseAmount) or 0))
	player:SetAttribute("OfflineIncomePlay15Active", false)
	player:SetAttribute("OfflineIncomePlay15EndsAt", 0)
	syncLimitedTimeOfferAttributes(player, data)

	ensureUpgradeDefaults(data)
	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		local statId = config.StatId
		if type(statId) == "string" and statId ~= "" then
			player:SetAttribute(statId, normalizeUpgradeValue(config, data[statId]))
		end
	end

	local claimedPacks = if type(data.ClaimedPacks) == "table" then data.ClaimedPacks else {}
	player:SetAttribute("StarterPack", claimedPacks["StarterPack"] == true)
	player:SetAttribute("ProPack", claimedPacks["ProPack"] == true)
	player:SetAttribute("GroupRewardClaimed", claimedPacks["GroupItemReward"] == true)
end

local function onPlayerAdded(player: Player)
	checkVIP(player)

	deadPlayers[player] = false
	loadingInventory[player] = false
	player:SetAttribute(ProfileReadyUtils.AttributeName, false)

	local profile = GameProfileStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function() return player.Parent ~= Players end
	})

	if not profile then 
		warn("[PlayerController] FAILED to load profile for:", player.Name)
		player:Kick("Data load failed. Please rejoin.") 
		return 
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile() 
	ensureUpgradeDefaults(profile.Data)
	ensureLimitedTimeOfferDefaults(profile.Data)

	-- Wipe legacy data
	if profile.Data.Speed then profile.Data.Speed = nil end
	if profile.Data.Jump then profile.Data.Jump = nil end
	if profile.Data.MaxCarry then profile.Data.MaxCarry = nil end
	if profile.Data.BoatSpeed then profile.Data.BoatSpeed = nil end
	if profile.Data.HelicopterSpeed then profile.Data.HelicopterSpeed = nil end

	if type(profile.Data.unlocked_slots) ~= "number" then
		local legacyBaseLevel = tonumber(profile.Data.BaseLevel) or 0
		profile.Data.unlocked_slots = SlotUnlockConfigurations.ClampSlots(
			SlotUnlockConfigurations.StartSlots + (legacyBaseLevel * 10)
		)
	end

	player:SetAttribute("OnboardingStep", profile.Data.OnboardingStep or 1)
	player:SetAttribute("PostTutorialStage", profile.Data.PostTutorialStage or 0)
	player:SetAttribute("TutorialSkipped", profile.Data.TutorialSkipped == true)
	player:SetAttribute("TutorialSpecialBrainrotGranted", profile.Data.TutorialSpecialBrainrotGranted == true)
	player:SetAttribute("SpinNumber", profile.Data.SpinNumber or 0)
	player:SetAttribute("LastDailySpin", profile.Data.LastDailySpin or 0)
	syncCandyAttributes(player, profile.Data)
	player:SetAttribute("UnlockedSlots", SlotUnlockConfigurations.ClampSlots(profile.Data.unlocked_slots))
	player:SetAttribute(LimitedTimeOfferConfiguration.ReadyAttribute, false)

	if type(profile.Data.AnalyticsFunnels) ~= "table" then
		profile.Data.AnalyticsFunnels = {
			OneTime = {},
		}
	end
	if type(profile.Data.AnalyticsFunnels.OneTime) ~= "table" then
		profile.Data.AnalyticsFunnels.OneTime = {}
	end
	if type(profile.Data.AnalyticsFunnels.Markers) ~= "table" then
		profile.Data.AnalyticsFunnels.Markers = {}
	end

	if type(profile.Data.TutorialSkipped) ~= "boolean" then
		profile.Data.TutorialSkipped = false
	end
	if type(profile.Data.TutorialVersion) ~= "number" then
		profile.Data.TutorialVersion = 1
	end
	if type(profile.Data.TutorialFreeCharacterUpgradeConsumed) ~= "boolean" then
		profile.Data.TutorialFreeCharacterUpgradeConsumed = false
	end
	if type(profile.Data.TutorialFreeBaseUpgradeConsumed) ~= "boolean" then
		profile.Data.TutorialFreeBaseUpgradeConsumed = false
	end
	if type(profile.Data.TutorialSpecialBrainrotGranted) ~= "boolean" then
		profile.Data.TutorialSpecialBrainrotGranted = false
	end

	local tutorialVersion = tonumber(profile.Data.TutorialVersion) or 1
	local currentTutorialFunnelStep = math.clamp(
		tonumber(profile.Data.AnalyticsFunnels.OneTime[CURRENT_TUTORIAL_FUNNEL_KEY]) or 0,
		0,
		CURRENT_TUTORIAL_FUNNEL_MAX_STEP
	)
	local recentTutorialFunnelStep = math.clamp(
		tonumber(profile.Data.AnalyticsFunnels.OneTime[RECENT_TUTORIAL_FUNNEL_KEY]) or 0,
		0,
		CURRENT_TUTORIAL_FUNNEL_MAX_STEP
	)
	local previousRecentTutorialFunnelStep = math.clamp(
		tonumber(profile.Data.AnalyticsFunnels.OneTime[PREVIOUS_RECENT_TUTORIAL_FUNNEL_KEY]) or 0,
		0,
		CURRENT_TUTORIAL_FUNNEL_MAX_STEP
	)
	local previousTutorialFunnelStep = remapPreviousTutorialFunnelStep(
		profile.Data.AnalyticsFunnels.OneTime[PREVIOUS_TUTORIAL_FUNNEL_KEY]
	)
	local legacyTutorialFunnelStep = remapVersionThreeTutorialFunnelStep(
		profile.Data.AnalyticsFunnels.OneTime[LEGACY_TUTORIAL_FUNNEL_KEY]
	)
	local oldestTutorialFunnelStep = remapStoredTutorialFunnelStep(
		profile.Data.AnalyticsFunnels.OneTime[OLDEST_TUTORIAL_FUNNEL_KEY],
		2
	)
	local oldestLegacyTutorialFunnelStep = remapStoredTutorialFunnelStep(
		profile.Data.AnalyticsFunnels.OneTime[OLDEST_LEGACY_TUTORIAL_FUNNEL_KEY],
		2
	)
	local originalTutorialFunnelStep = remapStoredTutorialFunnelStep(
		profile.Data.AnalyticsFunnels.OneTime[ORIGINAL_TUTORIAL_FUNNEL_KEY],
		1
	)
	local onboardingTutorialFunnelStep = remapStoredTutorialFunnelStep(profile.Data.OnboardingFunnelStep, tutorialVersion)
	local normalizedTutorialFunnelStep = math.max(
		currentTutorialFunnelStep,
		recentTutorialFunnelStep,
		previousRecentTutorialFunnelStep,
		previousTutorialFunnelStep,
		legacyTutorialFunnelStep,
		oldestTutorialFunnelStep,
		oldestLegacyTutorialFunnelStep,
		originalTutorialFunnelStep,
		onboardingTutorialFunnelStep
	)

	profile.Data.OnboardingFunnelStep = normalizedTutorialFunnelStep
	profile.Data.AnalyticsFunnels.OneTime[CURRENT_TUTORIAL_FUNNEL_KEY] = normalizedTutorialFunnelStep
	profile.Data.AnalyticsFunnels.OneTime[RECENT_TUTORIAL_FUNNEL_KEY] = nil
	profile.Data.AnalyticsFunnels.OneTime[PREVIOUS_RECENT_TUTORIAL_FUNNEL_KEY] = nil
	profile.Data.AnalyticsFunnels.OneTime[PREVIOUS_TUTORIAL_FUNNEL_KEY] = nil
	profile.Data.AnalyticsFunnels.OneTime[LEGACY_TUTORIAL_FUNNEL_KEY] = nil
	profile.Data.AnalyticsFunnels.OneTime[OLDEST_TUTORIAL_FUNNEL_KEY] = nil
	profile.Data.AnalyticsFunnels.OneTime[OLDEST_LEGACY_TUTORIAL_FUNNEL_KEY] = nil
	profile.Data.AnalyticsFunnels.OneTime[ORIGINAL_TUTORIAL_FUNNEL_KEY] = nil
	if profile.Data.DiscoveredItems == nil then profile.Data.DiscoveredItems = {} end
	if profile.Data.ClaimedPacks == nil then profile.Data.ClaimedPacks = {} end
	if type(profile.Data.RedeemedCodes) ~= "table" then profile.Data.RedeemedCodes = {} end
	if type(profile.Data.CandyCount) ~= "number" then profile.Data.CandyCount = 0 end
	if type(profile.Data.CandyPaidSpinCount) ~= "number" then profile.Data.CandyPaidSpinCount = 0 end
	if type(profile.Data.TotalBrainrotsCollected) ~= "number" then profile.Data.TotalBrainrotsCollected = 0 end
	if type(profile.Data.PostTutorialStage) ~= "number" then profile.Data.PostTutorialStage = 0 end
	if type(profile.Data.TotalMoneyEarned) ~= "number" then
		profile.Data.TotalMoneyEarned = math.max(0, tonumber(profile.Data.Money) or 0)
	end
	if type(profile.Data.Boosters) ~= "table" then
		profile.Data.Boosters = {
			MegaExplosionEndsAt = 0,
			ShieldEndsAt = 0,
		}
	end
	if type(profile.Data.Boosters.MegaExplosionEndsAt) ~= "number" then
		profile.Data.Boosters.MegaExplosionEndsAt = 0
	end
	if type(profile.Data.Boosters.ShieldEndsAt) ~= "number" then
		profile.Data.Boosters.ShieldEndsAt = 0
	end
	ensureBoosterChargesData(profile.Data)
	ensureVipSubscriptionData(profile.Data)

	profile.OnSessionEnd:Connect(function() 
		profiles[player] = nil
		player:Kick("Session released") 
	end)

	if player.Parent == Players then
		profiles[player] = profile
		createLeaderstats(player, profile.Data)
		calculateOfflineEarnings(player, profile)
		clearStoredSlotIncomeForJoin(profile)
		evaluateExistingBadgeProgress(player, profile)
		local tutorialService = getTutorialService()
		if tutorialService then
			tutorialService:SyncPlayer(player)
			tutorialService:EvaluateCurrentStep(player)
		end

		local analyticsFunnelsService = getAnalyticsFunnelsService()
		if analyticsFunnelsService then
			if analyticsFunnelsService.HandleBrainrotsCollectedChanged then
				analyticsFunnelsService:HandleBrainrotsCollectedChanged(player, profile.Data.TotalBrainrotsCollected or 0)
			end
			analyticsFunnelsService:HandleMoneyBalanceChanged(player)
		end

		local function setupBackpackTracking(backpack: Backpack)
			logBrainrotTrace(player, ("setupBackpackTracking backpack=%s"):format(backpack:GetFullName()))
			backpack.ChildAdded:Connect(function(child)
				if child:IsA("Tool") and isTrackedTool(child) then
					logBrainrotTrace(player, ("Backpack.ChildAdded %s"):format(summarizeTool(child)))
				end
				syncInventoryData(player, ("Backpack.ChildAdded:%s"):format(child.Name))
			end)
			backpack.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then
					logHardToolRemovalTrace(player, "BACKPACK REMOVE", child)
					if isCriticalTraceTool(child) and child.Parent == nil then
						logCriticalInventoryTrace(player, ("Backpack.ChildRemoved destroyedTool=%s"):format(summarizeTool(child)))
					end
				end
				if child:IsA("Tool") and isTrackedTool(child) then
					logBrainrotTrace(player, ("Backpack.ChildRemoved %s"):format(summarizeTool(child)))
				end
				syncInventoryData(player, ("Backpack.ChildRemoved:%s"):format(child.Name))
			end)
		end
		local bp = player:WaitForChild("Backpack")
		setupBackpackTracking(bp)
		syncEntitlementAttribute(player, "HasCollectAll", ProductConfigurations.GamePasses.CollectAll)
		syncEntitlementAttribute(player, "HasAutoBomb", ProductConfigurations.GamePasses.AutoBomb)
		player:SetAttribute(LimitedTimeOfferConfiguration.ReadyAttribute, true)

		player.CharacterAdded:Connect(function(char)
			deadPlayers[player] = false
			logBrainrotTrace(player, ("CharacterAdded %s"):format(char:GetFullName()))
			task.wait(0.2)
			logBrainrotTrace(player, "CharacterAdded invoking loadInventory")
			loadInventory(player, profile)

			local hum = char:WaitForChild("Humanoid", 10)
			if hum then
				applyWalkSpeed(player)
				hum.Died:Connect(function()
					logHumanoidDeathTrace(player)
					deadPlayers[player] = true
				end)
			end

			char.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					if isTrackedTool(child) then
						logBrainrotTrace(player, ("Character.ChildAdded %s"):format(summarizeTool(child)))
					end
					syncInventoryData(player, ("Character.ChildAdded:%s"):format(child.Name))
				end
			end)
			char.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then
					logHardToolRemovalTrace(player, "CHAR REMOVE HARD", child)
					if isCriticalTraceTool(child) and child.Parent == nil then
						logCriticalInventoryTrace(player, ("Character.ChildRemoved destroyedTool=%s"):format(summarizeTool(child)))
					end
					if isTrackedTool(child) then
						logBrainrotTrace(player, ("Character.ChildRemoved %s"):format(summarizeTool(child)))
					end
					syncInventoryData(player, ("Character.ChildRemoved:%s"):format(child.Name))
				end
			end)
		end)

		if player.Character then
			deadPlayers[player] = false
			logBrainrotTrace(player, ("ExistingCharacter loadInventory %s"):format(player.Character:GetFullName()))
			loadInventory(player, profile)

			local hum = player.Character:FindFirstChild("Humanoid")
			if hum then
				applyWalkSpeed(player)
				hum.Died:Connect(function()
					logHumanoidDeathTrace(player)
					deadPlayers[player] = true
				end)
			end

			player.Character.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					if isTrackedTool(child) then
						logBrainrotTrace(player, ("ExistingCharacter.ChildAdded %s"):format(summarizeTool(child)))
					end
					syncInventoryData(player, ("ExistingCharacter.ChildAdded:%s"):format(child.Name))
				end
			end)
			player.Character.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then
					logHardToolRemovalTrace(player, "CHAR REMOVE HARD", child)
					if isCriticalTraceTool(child) and child.Parent == nil then
						logCriticalInventoryTrace(player, ("ExistingCharacter.ChildRemoved destroyedTool=%s"):format(summarizeTool(child)))
					end
					if isTrackedTool(child) then
						logBrainrotTrace(player, ("ExistingCharacter.ChildRemoved %s"):format(summarizeTool(child)))
					end
					syncInventoryData(player, ("ExistingCharacter.ChildRemoved:%s"):format(child.Name))
				end
			end)
		end

		task.spawn(function()
			for packName, passId in pairs(ProductConfigurations.GamePasses) do
				if packName == "StarterPack" or packName == "ProPack" then
					if not profile.Data.ClaimedPacks[packName] then
						local success, hasPass = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId) end)
						if success and hasPass then
							player:SetAttribute(packName, true)
							grantPackRewards(player, packName)
						end
					end
				end
			end
		end)

		queueVipSubscriptionSync(player, "player_join")
		checkAndGrantGroupReward(player, profile)
	else
		profile:EndSession()
	end
end

local function onPlayerRemoving(player: Player)
	vipCache[player] = nil
	vipSubscriptionSyncQueued[player] = nil
	deadPlayers[player] = nil 
	loadingInventory[player] = nil 

	local profile = profiles[player]
	if profile then 
		profile.Data.LastSaveTime = os.time()
		if OfflineIncomeController and OfflineIncomeController.CancelPlay15 then
			OfflineIncomeController:CancelPlay15(player)
		end
		profile:EndSession()
		profiles[player] = nil 
	end
end

function PlayerController:SyncSpinData(player: Player)
	local profile = self:GetProfile(player)
	if profile then
		player:SetAttribute("SpinNumber", profile.Data.SpinNumber)
		player:SetAttribute("LastDailySpin", profile.Data.LastDailySpin)
	end
end

function PlayerController:SyncCandyData(player: Player)
	local profile = self:GetProfile(player)
	if profile and profile.Data then
		syncCandyAttributes(player, profile.Data)
	end
end

function PlayerController:CreateDefaultData()
	local data = deepCopy(Template)
	ensureUpgradeDefaults(data)
	return data
end

function PlayerController:SyncPublicState(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	ensureUpgradeDefaults(profile.Data)
	createLeaderstats(player, profile.Data)
	return true
end

function PlayerController:ReloadInventoryFromProfile(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	logBrainrotTrace(player, "ReloadInventoryFromProfile")
	loadInventory(player, profile)
	return true
end

function PlayerController:ApplyWalkSpeed(player: Player): number
	return applyWalkSpeed(player)
end

function PlayerController:SetTimedWalkSpeedOverride(walkSpeed: number?)
	local resolvedWalkSpeed = tonumber(walkSpeed)
	if resolvedWalkSpeed and resolvedWalkSpeed > 0 then
		timedWalkSpeedOverride = resolvedWalkSpeed
	else
		timedWalkSpeedOverride = nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		applyWalkSpeed(player)
	end
end

function PlayerController:ClearInventoryForTesting(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.Inventory = {}

	local function clearContainer(container: Instance?)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and (child:GetAttribute("OriginalName") ~= nil or child:GetAttribute("IsLuckyBlock") == true) then
				child:Destroy()
			end
		end
	end

	clearContainer(player:FindFirstChild("Backpack"))
	clearContainer(player.Character)
	clearContainer(player:FindFirstChild("StarterGear"))
	logBrainrotTrace(player, "ClearInventoryForTesting applied empty profile inventory")
	syncInventoryData(player, "ClearInventoryForTesting")

	local pickaxeController = getPickaxeController()
	if pickaxeController and pickaxeController.EnsureBombFirstSlot then
		task.defer(function()
			if player.Parent then
				pickaxeController.EnsureBombFirstSlot(player)
			end
		end)
	end

	local events = ReplicatedStorage:FindFirstChild("Events")
	local refresh = events and events:FindFirstChild("RefreshIndex")
	if refresh then
		refresh:FireClient(player)
	end

	return true
end

function PlayerController:SetMoneyForTesting(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.Money = math.max(0, math.floor(tonumber(amount) or 0))
	self:SyncPublicState(player)

	return true
end

function PlayerController:SetTotalMoneyEarnedForTesting(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.TotalMoneyEarned = math.max(0, math.floor(tonumber(amount) or 0))
	player:SetAttribute("TotalMoneyEarned", profile.Data.TotalMoneyEarned)
	return true
end

function PlayerController:SetSpinNumberForTesting(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.SpinNumber = math.max(0, math.floor(tonumber(amount) or 0))
	player:SetAttribute("SpinNumber", profile.Data.SpinNumber)
	return true
end

function PlayerController:SetCandyCountForTesting(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.CandyCount = math.max(0, math.floor(tonumber(amount) or 0))
	player:SetAttribute("CandyCount", profile.Data.CandyCount)
	return true
end

function PlayerController:SetCandyPaidSpinCountForTesting(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.CandyPaidSpinCount = math.max(0, math.floor(tonumber(amount) or 0))
	player:SetAttribute("CandyPaidSpinCount", profile.Data.CandyPaidSpinCount)
	return true
end

function PlayerController:SetTimePlayedForTesting(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.TimePlayed = math.max(0, math.floor(tonumber(amount) or 0))
	player:SetAttribute("TimePlayed", profile.Data.TimePlayed)
	return true
end

function PlayerController:SetTotalBrainrotsCollectedForTesting(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.TotalBrainrotsCollected = math.max(0, math.floor(tonumber(amount) or 0))
	player:SetAttribute("TotalBrainrotsCollected", profile.Data.TotalBrainrotsCollected)
	return true
end

function PlayerController:SetUnlockedSlotsForTesting(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data then
		return false
	end

	profile.Data.unlocked_slots = SlotUnlockConfigurations.ClampSlots(math.floor(tonumber(amount) or SlotUnlockConfigurations.StartSlots))
	player:SetAttribute("UnlockedSlots", profile.Data.unlocked_slots)
	return true
end

function PlayerController:SetUpgradeStatForTesting(player: Player, statId: string, value: number): boolean
	local profile = profiles[player]
	if not profile or not profile.Data or type(statId) ~= "string" or statId == "" then
		return false
	end

	ensureUpgradeDefaults(profile.Data)
	profile.Data[statId] = math.max(0, math.floor(tonumber(value) or 0))
	player:SetAttribute(statId, profile.Data[statId])

	if statId == "BonusSpeed" then
		applyWalkSpeed(player)
	end

	return true
end

function PlayerController:ForceSaveProfile(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	profile.Data.LastSaveTime = os.time()
	profile:Save()
	return true
end

function PlayerController:ResetProfileToDefaultForTesting(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	profile.Data = self:CreateDefaultData()
	self:SyncPublicState(player)
	self:ReloadInventoryFromProfile(player)
	return true
end

function PlayerController:OnTutorialStepChanged(player: Player, step: number)
	local profile = profiles[player]
	if not profile then
		return
	end

	BadgeManager:EvaluateOnboardingStep(player, step)
	if step >= TutorialConfiguration.FinalStep then
		checkAndGrantGroupReward(player, profile)
	end
end

function PlayerController:Init(controllers)
	local analyticsFunnelsService = getAnalyticsFunnelsService()
	if analyticsFunnelsService and analyticsFunnelsService.Init then
		analyticsFunnelsService:Init(controllers)
	end

	local analyticsEconomyService = getAnalyticsEconomyService()
	if analyticsEconomyService and analyticsEconomyService.Init then
		analyticsEconomyService:Init(controllers)
	end

	local Modules = ServerScriptService:WaitForChild("Modules")
	ItemManager = require(Modules:WaitForChild("ItemManager"))
	SlotManager = require(Modules:WaitForChild("SlotManager"))
	OfflineIncomeController = controllers.OfflineIncomeController
	if SlotManager.Init then SlotManager:Init(controllers) end

	local Events = ReplicatedStorage:WaitForChild("Events")
	local getIndexFunc = Events:FindFirstChild("GetIndexData") or Instance.new("RemoteFunction", Events)
	getIndexFunc.Name = "GetIndexData"
	getIndexFunc.OnServerInvoke = function(player)
		local start = os.time()
		while loadingInventory[player] do
			if os.time() - start > 5 then break end
			task.wait(0.1)
		end
		local profile = PlayerController:GetProfile(player)
		return profile and profile.Data.DiscoveredItems or {}
	end

	local studioGrantEvent = Events:FindFirstChild("RequestVipSubscriptionStudioGrant") or Instance.new("RemoteEvent", Events)
	studioGrantEvent.Name = "RequestVipSubscriptionStudioGrant"
	studioGrantEvent.OnServerEvent:Connect(function(player)
		grantVipSubscriptionStudioButtonRewards(player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if wasPurchased then
			local analyticsEconomyService = getAnalyticsEconomyService()
			local analyticsFunnelsService = getAnalyticsFunnelsService()
			local purchasedPassName = ProductConfigurations.GetGamePassById(passId)
			if passId == ProductConfigurations.GamePasses.VIP then
				vipCache[player] = true
				player:SetAttribute("IsVIP", true)
				local notif = Events:FindFirstChild("ShowNotification")
				if notif then notif:FireClient(player, "Gamepass bought!", "Success") end
				if SlotManager and SlotManager.RefreshAllSlots then SlotManager.RefreshAllSlots(player) end
				if analyticsEconomyService then
					analyticsEconomyService:LogEntitlementGranted(player, "VIP", "VIP", nil, {
						feature = "vip",
						content_id = "VIP",
						context = "shop",
					})
				end
			end
			if passId == COLLECT_ALL_GAMEPASS then
				player:SetAttribute("HasCollectAll", true)
				if analyticsEconomyService then
					analyticsEconomyService:LogEntitlementGranted(player, "CollectAll", "CollectAll", nil, {
						feature = "collect_all",
						content_id = "CollectAll",
						context = "shop",
					})
				end
			end
			if passId == ProductConfigurations.GamePasses.AutoBomb then
				player:SetAttribute("HasAutoBomb", true)
				if analyticsEconomyService then
					analyticsEconomyService:LogEntitlementGranted(player, "AutoBomb", "AutoBomb", nil, {
						feature = "auto_bomb",
						content_id = "AutoBomb",
						context = "shop",
					})
				end
			end

			local packName = purchasedPassName
			if packName and (packName == "StarterPack" or packName == "ProPack") then
				player:SetAttribute(packName, true)
				grantPackRewards(player, packName)
			end
			if analyticsFunnelsService then
				analyticsFunnelsService:HandleStorePurchaseSuccess(player, {
					purchaseKind = "gamepass",
					id = passId,
					productName = purchasedPassName,
					paymentType = "robux",
				})
			end
			playPurchaseEffects(player) 
		end
	end)

	MarketplaceService.PromptSubscriptionPurchaseFinished:Connect(function(player, subscriptionId, _didTryPurchasing)
		if tostring(subscriptionId) == VIP_SUBSCRIPTION_ID then
			queueVipSubscriptionSync(player, "subscription_prompt_finished")
		end
	end)

	Players.UserSubscriptionStatusChanged:Connect(function(player, subscriptionId)
		if tostring(subscriptionId) == VIP_SUBSCRIPTION_ID then
			queueVipSubscriptionSync(player, "subscription_status_changed")
		end
	end)

	for _, part in ipairs(CollectionService:GetTagged(VIP_TAG)) do if part:IsA("BasePart") then setupVIPTouch(part) end end
	CollectionService:GetInstanceAddedSignal(VIP_TAG):Connect(function(part) if part:IsA("BasePart") then setupVIPTouch(part) end end)
end

function PlayerController:Start()
	if SlotManager.Start then task.spawn(function() SlotManager:Start() end) end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end

	-- ## ADDED: TIME PLAYED TRACKER ##
	task.spawn(function()
		while true do
			task.wait(1) -- Run every 1 second
			for player, profile in pairs(profiles) do
				if profile and profile.Data then
					-- Increment the saved data
					profile.Data.TimePlayed = (profile.Data.TimePlayed or 0) + 1

					-- Optional: Set as an attribute in case you ever want a UI timer!
					player:SetAttribute("TimePlayed", profile.Data.TimePlayed)
				end
			end
		end
	end)

	game:BindToClose(function()
		PlayerController.isShuttingDown = true
		for _, p in ipairs(Players:GetPlayers()) do
			if profiles[p] then profiles[p].Data.LastSaveTime = os.time() end
		end
	end)
end

return PlayerController
