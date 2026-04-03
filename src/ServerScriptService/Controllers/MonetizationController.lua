--!strict
-- LOCATION: ServerScriptService/Controllers/MonetizationController

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local MonetizationController = {}

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfigurations)
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local BadgeManager = require(ServerScriptService.Modules.BadgeManager)
local LimitedProductStockService = require(ServerScriptService.Modules.LimitedProductStockService)
local RebirthSystem
local ItemManager
local PlayerController
local PlaytimeRewardController
local DailyRewardController
local TutorialService
local PickaxeController
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

local function getUpgradeCashEquivalent(config: any, currentValue: number): number
	local baseCost = config.BaseCost or 5000
	local priceMultiplier = config.PriceMultiplier or 1.5
	local amount = config.Amount or 1
	local totalPrice = 0
	local tempValue = currentValue

	for _ = 1, amount do
		totalPrice += baseCost * (priceMultiplier ^ tempValue)
		tempValue += 1
	end

	return math.floor(totalPrice)
end

local function playPurchaseEffects(player: Player)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local effectEvent = Events and Events:FindFirstChild("TriggerUIEffect")
	if effectEvent then
		effectEvent:FireClient(player, "HighlightLight")
	end

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

local function grantItemProductReward(player: Player, productName: string, itemReward: {[string]: any}, notif: RemoteEvent?): boolean
	if not ItemManager then
		ItemManager = require(ServerScriptService.Modules.ItemManager)
	end

	if not PlayerController then
		PlayerController = require(ServerScriptService.Controllers.PlayerController)
	end

	local itemName = itemReward.Name
	if type(itemName) ~= "string" or itemName == "" then
		warn("[MonetizationController] Missing item reward name for product:", productName)
		return false
	end

	local mutation = if type(itemReward.Mutation) == "string" and itemReward.Mutation ~= "" then itemReward.Mutation else "Normal"
	local level = math.max(1, math.floor(tonumber(itemReward.Level) or 1))
	local itemConf = ItemConfigurations.GetItemData(itemName)
	local rarity = itemConf and itemConf.Rarity or "Common"
	local displayName = itemConf and itemConf.DisplayName or itemName

	local tool = ItemManager.GiveItemToPlayer(player, itemName, mutation, rarity, level)
	if not tool then
		warn("[MonetizationController] Failed to grant item reward for product:", productName, itemName)
		return false
	end

	local totalCollected = PlayerController:IncrementBrainrotsCollected(player, 1)
	BadgeManager:EvaluateBrainrotMilestones(player, rarity, totalCollected)
	AnalyticsEconomyService:LogItemValueSourceForItem(
		player,
		itemName,
		mutation,
		level,
		TRANSACTION_TYPES.IAP,
		`ItemIAP:{productName}`,
		{
			feature = "iap_item",
			content_id = itemName,
			context = "shop",
			rarity = rarity,
			mutation = mutation,
		}
	)

	if notif then
		notif:FireClient(player, displayName .. " Purchased!", "Success")
	end

	playPurchaseEffects(player)
	return true
end

local function grantLuckyBlockProductReward(player: Player, productName: string, blockId: string, notif: RemoteEvent?): boolean
	if not ItemManager then
		ItemManager = require(ServerScriptService.Modules.ItemManager)
	end

	local tool = ItemManager.GiveLuckyBlockToPlayer(player, blockId)
	if not tool then
		warn("[MonetizationController] Failed to grant lucky block reward for product:", productName, blockId)
		return false
	end

	AnalyticsEconomyService:LogItemValueSourceForLuckyBlock(
		player,
		blockId,
		TRANSACTION_TYPES.IAP,
		`LuckyBlockIAP:{productName}`,
		{
			feature = "iap_lucky_block",
			content_id = blockId,
			context = "shop",
		}
	)

	if notif then
		notif:FireClient(player, "You got " .. tool.Name .. "!", "Success")
	end

	playPurchaseEffects(player)
	return true
end

function MonetizationController.ProcessReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local productId = receiptInfo.ProductId
	local productName = ProductConfigurations.GetProductById(productId)
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")

	local targetUpgradeConfig = nil
	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		if config.RobuxProductId == productId then
			targetUpgradeConfig = config
			break
		end
	end

	if targetUpgradeConfig then
		if not PlayerController then PlayerController = require(ServerScriptService.Controllers.PlayerController) end
		local profile = PlayerController:GetProfile(player)

		if profile then
			local statId = targetUpgradeConfig.StatId
			local upgradeAmount = targetUpgradeConfig.Amount or 1
			local currentVal = profile.Data[statId] or 0

			profile.Data[statId] = currentVal + upgradeAmount
			player:SetAttribute(statId, profile.Data[statId])
			AnalyticsEconomyService:LogEntitlementGranted(player, "RobuxUpgrade", targetUpgradeConfig.Id, getUpgradeCashEquivalent(targetUpgradeConfig, currentVal), {
				feature = "robux_upgrade",
				content_id = targetUpgradeConfig.Id,
				context = "shop",
			})

			if statId == "BonusSpeed" then
				local char = player.Character
				local hum = char and char:FindFirstChild("Humanoid") :: Humanoid
				if hum then hum.WalkSpeed = 16 + profile.Data[statId] end
			end

			if targetUpgradeConfig.HiddenInUI ~= true then
				local tutorialService = getTutorialService()
				if tutorialService then
					tutorialService:HandlePostTutorialCharacterUpgradePurchased(player, targetUpgradeConfig.Id)
				end
			end

			local UpgradesSystem = require(ServerScriptService.Modules.UpgradesSystem)
			UpgradesSystem.UpdateClientUI(player)

			if notif then notif:FireClient(player, "+" .. upgradeAmount .. " " .. targetUpgradeConfig.DisplayName .. " Purchased!", "Success") end
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local targetBombName = nil
	local targetBombConfig = nil
	for bombName, config in pairs(BombsConfigurations.Bombs) do
		if config.RobuxProductId == productId then
			targetBombName = bombName
			targetBombConfig = config
			break
		end
	end

	if targetBombName and targetBombConfig then
		if not PickaxeController then PickaxeController = require(ServerScriptService.Controllers.PickaxeController) end

		local success = PickaxeController.GrantPickaxeByRobux(player, targetBombName)
		if success then
			AnalyticsEconomyService:LogEntitlementGranted(player, "RobuxBomb", targetBombName, targetBombConfig.Price or 0, {
				feature = "bomb_shop",
				content_id = targetBombName,
				context = "robux_shop",
				bomb_tier = tonumber(targetBombName:match("(%d+)")) or 0,
			})
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not productName then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local rewardedAdReward = ProductConfigurations.RewardedAdRewards[productName]
	if rewardedAdReward then
		if not PlayerController then PlayerController = require(ServerScriptService.Controllers.PlayerController) end

		local cashAmount = math.max(0, math.floor(tonumber(rewardedAdReward.CashAmount) or 0))
		if cashAmount > 0 then
			AnalyticsEconomyService:FlushBombIncome(player)
			PlayerController:AddMoney(player, cashAmount)
			AnalyticsEconomyService:LogCashSource(player, cashAmount, TRANSACTION_TYPES.Gameplay, `RewardedAd:{productName}`, {
				feature = "rewarded_ad",
				content_id = productName,
				context = "rewarded_video",
			})
		end

		if notif then
			notif:FireClient(player, "+" .. NumberFormatter.Format(cashAmount) .. " soft from ad!", "Success")
		end
		playPurchaseEffects(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if productName == "SkipRebirth" then
		if not RebirthSystem then RebirthSystem = require(ServerScriptService.Modules.RebirthSystem) end
		local rebirthCost = 0
		if RebirthSystem.GetInfo then
			rebirthCost = select(1, RebirthSystem.GetInfo(player))
		end
		RebirthSystem.ForceRebirth(player)
		AnalyticsEconomyService:LogEntitlementGranted(player, "SkipRebirth", "SkipRebirth", rebirthCost, {
			feature = "skip_rebirth",
			content_id = "SkipRebirth",
			context = "shop",
		})
		playPurchaseEffects(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if productName == "PlaytimeRewardsSkipAll" then
		if not PlaytimeRewardController then
			PlaytimeRewardController = require(ServerScriptService.Controllers.PlaytimeRewardController)
		end

		local success = PlaytimeRewardController:HandleSkipAll(player)
		if success then
			AnalyticsEconomyService:LogEntitlementGranted(player, "PlaytimeRewardsSkipAll", productName, nil, {
				feature = "playtime_rewards",
				content_id = productName,
				context = "shop",
			})
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if productName == "PlaytimeRewardsSpeedX2" or productName == "PlaytimeRewardsSpeedX5" then
		if not PlaytimeRewardController then
			PlaytimeRewardController = require(ServerScriptService.Controllers.PlaytimeRewardController)
		end

		local success = PlaytimeRewardController:HandleSpeedProduct(player, productName)
		if success then
			AnalyticsEconomyService:LogEntitlementGranted(player, "PlaytimeRewardSpeed", productName, nil, {
				feature = "playtime_rewards",
				content_id = productName,
				context = "shop",
			})
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if productName == "DailyRewardsSkipAll" or productName == "DailyRewardsSkip1" then
		if not DailyRewardController then
			DailyRewardController = require(ServerScriptService.Controllers.DailyRewardController)
		end

		local success
		if productName == "DailyRewardsSkipAll" then
			success = DailyRewardController:HandleSkipAll(player)
		else
			success = DailyRewardController:HandleSkip1(player)
		end

		if success then
			AnalyticsEconomyService:LogEntitlementGranted(player, "DailyRewardSkip", productName, nil, {
				feature = "daily_reward",
				content_id = productName,
				context = "shop",
			})
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local luckyBlockReward = ProductConfigurations.LuckyBlockProductRewards[productName]
	if type(luckyBlockReward) == "string" and luckyBlockReward ~= "" then
		if grantLuckyBlockProductReward(player, productName, luckyBlockReward, notif) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local itemReward = ProductConfigurations.ItemProductRewards[productName]
	if itemReward then
		local limitedReceiptState = LimitedProductStockService:BeginReceiptGrant(receiptInfo)
		if limitedReceiptState.IsLimited then
			if not limitedReceiptState.Success then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			if limitedReceiptState.AlreadyDelivered then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end

		if grantItemProductReward(player, productName, itemReward, notif) then
			if limitedReceiptState.IsLimited then
				local purchaseId = limitedReceiptState.PurchaseId
				if type(purchaseId) == "string" and purchaseId ~= "" then
					local didMarkDelivered = LimitedProductStockService:MarkReceiptDelivered(productId, purchaseId)
					if not didMarkDelivered then
						warn("[MonetizationController] Failed to mark limited product receipt as delivered:", productName, purchaseId)
					end
				end
			end

			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local cashAmount = ProductConfigurations.CashProductRewards[productName]
	if cashAmount then
		if not PlayerController then PlayerController = require(ServerScriptService.Controllers.PlayerController) end
		AnalyticsEconomyService:FlushBombIncome(player)
		PlayerController:AddMoney(player, cashAmount)
		AnalyticsEconomyService:LogCashSource(player, cashAmount, TRANSACTION_TYPES.IAP, `CashProduct:{productName}`, {
			feature = "iap_cash",
			content_id = productName,
			context = "shop",
		})
		if notif then notif:FireClient(player, "$" .. NumberFormatter.Format(cashAmount) .. " Purchased!", "Success") end
		playPurchaseEffects(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if productName == "RandomItem" then
		if not ItemManager then ItemManager = require(ServerScriptService.Modules.ItemManager) end

		local validItems = {}
		for itemName, data in pairs(ItemConfigurations.Items) do
			if data.Rarity ~= "Common" and data.Rarity ~= "Uncommon" then
				table.insert(validItems, { Name = itemName, Rarity = data.Rarity })
			end
		end

		if #validItems > 0 then
			local chosenItem = validItems[math.random(1, #validItems)]
			local tool = ItemManager.GiveItemToPlayer(player, chosenItem.Name, "Normal", chosenItem.Rarity, 1)
			if tool then
				AnalyticsEconomyService:LogItemValueSourceForItem(
					player,
					chosenItem.Name,
					"Normal",
					1,
					TRANSACTION_TYPES.IAP,
					`ItemIAP:{productName}`,
					{
						feature = "iap_random_item",
						content_id = chosenItem.Name,
						context = "shop",
						rarity = chosenItem.Rarity,
						mutation = "Normal",
					}
				)
			end

			if notif then
				notif:FireClient(player, "You unboxed a " .. chosenItem.Rarity .. " " .. chosenItem.Name .. "!", "Success")
			end
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			warn("[MonetizationController] No valid items found for RandomItem product!")
		end
	end

	if productName == "SpinsX3" or productName == "SpinsX9" then
		if not PlayerController then PlayerController = require(ServerScriptService.Controllers.PlayerController) end
		local profile = PlayerController:GetProfile(player)
		if profile then
			local spinAmount = (productName == "SpinsX3") and 3 or 9
			profile.Data.SpinNumber = (profile.Data.SpinNumber or 0) + spinAmount
			player:SetAttribute("SpinNumber", profile.Data.SpinNumber)
			AnalyticsEconomyService:LogSpinSource(player, spinAmount, TRANSACTION_TYPES.IAP, `SpinPack:{productName}`, {
				feature = "iap_spins",
				content_id = productName,
				context = "shop",
			})
			AnalyticsFunnelsService:HandleDailySpinAvailable(player)

			if notif then notif:FireClient(player, "+" .. spinAmount .. " Spins Purchased!", "Success") end
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationController:Init(controllers)
	PlaytimeRewardController = controllers.PlaytimeRewardController
	DailyRewardController = controllers.DailyRewardController
	print("[MonetizationController] Initialized")
end

function MonetizationController:Start()
	MarketplaceService.ProcessReceipt = MonetizationController.ProcessReceipt
end

return MonetizationController
