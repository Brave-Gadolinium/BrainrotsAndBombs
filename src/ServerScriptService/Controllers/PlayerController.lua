--!strict
-- LOCATION: ServerScriptService/Controllers/PlayerController

-- Services
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris") 

-- Modules
local ProfileStoreModule = require(ServerScriptService.Modules.ProfileStore)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local LimitedTimeOfferConfiguration = require(ReplicatedStorage.Modules.LimitedTimeOfferConfiguration)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfigurations)
local SlotUnlockConfigurations = require(ReplicatedStorage.Modules.SlotUnlockConfigurations)
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)
local BadgeManager = require(ServerScriptService.Modules.BadgeManager)
local ItemManager 
local SlotManager 
local PickaxeController
local TutorialService
local AnalyticsFunnelsService
local AnalyticsEconomyService
local OfflineIncomeController

-- [ CONFIGURATION ]
local DATA_VERSION = "ProjectData_v90" 

local VIP_TAG = "V.I.P"
local COLLECT_ALL_GAMEPASS = ProductConfigurations.GamePasses.CollectAll or 1783037385
local LIMITED_TIME_COLLECT_ALL_DURATION = math.max(0, math.floor(tonumber(LimitedTimeOfferConfiguration.OfferDurationSeconds) or 0))

local GROUP_ID = 0 

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
	TutorialVersion: number,
	TutorialFreeCharacterUpgradeConsumed: boolean,
	TutorialFreeBaseUpgradeConsumed: boolean,
	OnboardingFunnelStep: number,
	AnalyticsFunnels: {[string]: any},
	LastSaveTime: number,
	SpinNumber: number,
	LastDailySpin: number,
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
	TutorialVersion = 2,
	TutorialFreeCharacterUpgradeConsumed = false,
	TutorialFreeBaseUpgradeConsumed = false,
	OnboardingFunnelStep = 0,
	AnalyticsFunnels = {
		OneTime = {},
	},
	LastSaveTime = 0,
	SpinNumber = 0,     
	LastDailySpin = 0,   
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
local deadPlayers: {[Player]: boolean} = {} 
local loadingInventory: {[Player]: boolean} = {}

PlayerController.isShuttingDown = false

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
	return vipCache[player] == true
end

local function checkVIP(player: Player)
	local passId = ProductConfigurations.GamePasses.VIP
	if not passId or passId <= 0 then
		player:SetAttribute("IsVIP", false)
		return
	end

	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)

	if success and hasPass then
		vipCache[player] = true
		player:SetAttribute("IsVIP", true) -- Set attribute for client HUD
	end
end

local function syncEntitlementAttribute(player: Player, attributeName: string, passId: number?)
	if type(passId) ~= "number" or passId <= 0 then
		player:SetAttribute(attributeName, false)
		return
	end

	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)

	player:SetAttribute(attributeName, success and hasPass or false)
end

local function setupVIPTouch(part: BasePart)
	if part:GetAttribute("TouchConnected") then return end
	part:SetAttribute("TouchConnected", true)

	part.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and not vipCache[player] then
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
	return profile.Data.TotalBrainrotsCollected
end

function PlayerController:SetupSharedInstances()
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then 
		eventsFolder = Instance.new("Folder"); eventsFolder.Name = "Events"; eventsFolder.Parent = ReplicatedStorage
	end
	local function createRemote(type: "RemoteEvent", name: string)
		if not eventsFolder:FindFirstChild(name) then
			local r = Instance.new(type); r.Name = name; r.Parent = eventsFolder
		end
	end
	createRemote("RemoteEvent", "ShowNotification") 
	createRemote("RemoteEvent", "RequestSlotPurchase")
	createRemote("RemoteEvent", "RequestRebirth")
	createRemote("RemoteEvent", "UpdateRebirthUI")
	createRemote("RemoteEvent", "RefreshIndex")
	createRemote("RemoteEvent", "ReportTutorialAction") 
	createRemote("RemoteEvent", "ReportAnalyticsIntent")
	createRemote("RemoteEvent", "TriggerUIEffect") 
	createRemote("RemoteEvent", "ShowPostTutorialCompletion")
	createRemote("RemoteEvent", "RequestRewardedAd")
	createRemote("RemoteEvent", "RewardedAdResult")
	createRemote("RemoteEvent", "RequestAutoBombState")
	createRemote("RemoteEvent", "ShowContextualOffer")
end

local function toolToData(tool: Tool): ItemData?
	local name = tool:GetAttribute("OriginalName")
	if name then
		return { Name = name, Mutation = tool:GetAttribute("Mutation") or "Normal", Rarity = tool:GetAttribute("Rarity") or "Common", Level = tool:GetAttribute("Level") or 1 }
	end
	return nil
end

local function syncInventoryData(player: Player)
	local profile = profiles[player]
	if not profile then return end
	if deadPlayers[player] then return end

	local isSyncingFromSave = loadingInventory[player]
	local inventoryData = {}
	local newDiscovery = false

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

	if not isSyncingFromSave then profile.Data.Inventory = inventoryData end

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

	local backpack = player:FindFirstChild("Backpack")
	if backpack then backpack:ClearAllChildren() end

	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear then starterGear:ClearAllChildren() end

	local savedInv = profile.Data.Inventory or {}
	for _, itemData in ipairs(savedInv) do
		ItemManager.GiveItemToPlayer(player, itemData.Name, itemData.Mutation, itemData.Rarity, itemData.Level)
		local key = itemData.Mutation .. "_" .. itemData.Name
		if not profile.Data.DiscoveredItems[key] then profile.Data.DiscoveredItems[key] = true end
	end

	task.wait() 
	loadingInventory[player] = false
	syncInventoryData(player)

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
	player:SetAttribute("SpinNumber", data.SpinNumber or 0)
	player:SetAttribute("LastDailySpin", data.LastDailySpin or 0)
	player:SetAttribute("UnlockedSlots", SlotUnlockConfigurations.ClampSlots(tonumber(data.unlocked_slots) or SlotUnlockConfigurations.StartSlots))

	-- Note: TimePlayed gets set continuously in the Start loop, but we can initialize it here:
	player:SetAttribute("TimePlayed", data.TimePlayed or 0)
	player:SetAttribute("TotalMoneyEarned", data.TotalMoneyEarned or 0)
	player:SetAttribute("TotalBrainrotsCollected", data.TotalBrainrotsCollected or 0)
	local boosters = if type(data.Boosters) == "table" then data.Boosters else {}
	player:SetAttribute("MegaExplosionEndsAt", math.max(0, tonumber(boosters.MegaExplosionEndsAt) or 0))
	player:SetAttribute("ShieldEndsAt", math.max(0, tonumber(boosters.ShieldEndsAt) or 0))
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
	player:SetAttribute("SpinNumber", profile.Data.SpinNumber or 0)
	player:SetAttribute("LastDailySpin", profile.Data.LastDailySpin or 0)
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

	if type(profile.Data.TutorialVersion) ~= "number" then
		profile.Data.TutorialVersion = 1
	end
	if type(profile.Data.TutorialFreeCharacterUpgradeConsumed) ~= "boolean" then
		profile.Data.TutorialFreeCharacterUpgradeConsumed = false
	end
	if type(profile.Data.TutorialFreeBaseUpgradeConsumed) ~= "boolean" then
		profile.Data.TutorialFreeBaseUpgradeConsumed = false
	end

	profile.Data.OnboardingFunnelStep = math.clamp(tonumber(profile.Data.OnboardingFunnelStep) or 0, 0, 14)
	profile.Data.AnalyticsFunnels.OneTime.TutorialFTUE = math.max(
		tonumber(profile.Data.AnalyticsFunnels.OneTime.TutorialFTUE) or 0,
		profile.Data.OnboardingFunnelStep
	)
	if profile.Data.DiscoveredItems == nil then profile.Data.DiscoveredItems = {} end
	if profile.Data.ClaimedPacks == nil then profile.Data.ClaimedPacks = {} end
	if type(profile.Data.RedeemedCodes) ~= "table" then profile.Data.RedeemedCodes = {} end
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

	profile.OnSessionEnd:Connect(function() 
		profiles[player] = nil
		player:Kick("Session released") 
	end)

	if player.Parent == Players then
		profiles[player] = profile
		createLeaderstats(player, profile.Data)
		calculateOfflineEarnings(player, profile)
		evaluateExistingBadgeProgress(player, profile)
		local tutorialService = getTutorialService()
		if tutorialService then
			tutorialService:SyncPlayer(player)
			tutorialService:EvaluateCurrentStep(player)
		end

		local analyticsFunnelsService = getAnalyticsFunnelsService()
		if analyticsFunnelsService then
			analyticsFunnelsService:HandleMoneyBalanceChanged(player)
		end

		local function setupBackpackTracking(backpack: Backpack)
			backpack.ChildAdded:Connect(function() syncInventoryData(player) end)
			backpack.ChildRemoved:Connect(function() syncInventoryData(player) end)
		end
		local bp = player:WaitForChild("Backpack")
		setupBackpackTracking(bp)
		syncEntitlementAttribute(player, "HasCollectAll", ProductConfigurations.GamePasses.CollectAll)
		syncEntitlementAttribute(player, "HasAutoBomb", ProductConfigurations.GamePasses.AutoBomb)
		player:SetAttribute(LimitedTimeOfferConfiguration.ReadyAttribute, true)

		player.CharacterAdded:Connect(function(char)
			deadPlayers[player] = false
			task.wait(0.2)
			loadInventory(player, profile)

			local hum = char:WaitForChild("Humanoid", 10)
			if hum then hum.Died:Connect(function() deadPlayers[player] = true end) end

			char.ChildAdded:Connect(function(child) if child:IsA("Tool") then syncInventoryData(player) end end)
			char.ChildRemoved:Connect(function(child) if child:IsA("Tool") then syncInventoryData(player) end end)
		end)

		if player.Character then
			deadPlayers[player] = false
			loadInventory(player, profile)

			local hum = player.Character:FindFirstChild("Humanoid")
			if hum then hum.Died:Connect(function() deadPlayers[player] = true end) end

			player.Character.ChildAdded:Connect(function(child) if child:IsA("Tool") then syncInventoryData(player) end end)
			player.Character.ChildRemoved:Connect(function(child) if child:IsA("Tool") then syncInventoryData(player) end end)
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

		checkAndGrantGroupReward(player, profile)
	else
		profile:EndSession()
	end
end

local function onPlayerRemoving(player: Player)
	vipCache[player] = nil
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

	loadInventory(player, profile)
	return true
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
	syncInventoryData(player)

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
		local character = player.Character
		local hum = character and character:FindFirstChild("Humanoid")
		if hum and hum:IsA("Humanoid") then
			hum.WalkSpeed = 20 + profile.Data[statId]
		end
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
