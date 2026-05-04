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
local BoosterService
local PlaytimeRewardController
local DailyRewardController
local OfflineIncomeController
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

local function logStorePurchaseSuccess(player: Player, purchaseKind: string, purchaseId: number, productName: string?, paymentType: string?, surface: string?)
	AnalyticsFunnelsService:HandleStorePurchaseSuccess(player, {
		purchaseKind = purchaseKind,
		id = purchaseId,
		productName = productName,
		paymentType = paymentType or "robux",
		surface = surface,
	})
end

local function isRewardedAdReceipt(receiptInfo): boolean
	return receiptInfo.ProductPurchaseChannel == Enum.ProductPurchaseChannel.AdReward
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

local function grantLuckyBlockProductReward(player: Player, productName: string, blockId: string, quantity: number?, notif: RemoteEvent?): boolean
	if not ItemManager then
		ItemManager = require(ServerScriptService.Modules.ItemManager)
	end

	local grantCount = math.max(1, math.floor(tonumber(quantity) or 1))
	local successCount = 0
	local firstTool: Tool? = nil

	for _ = 1, grantCount do
		local tool = ItemManager.GiveLuckyBlockToPlayer(player, blockId)
		if tool then
			successCount += 1
			firstTool = firstTool or tool
			AnalyticsEconomyService:LogItemValueSourceForLuckyBlock(
				player,
				blockId,
				TRANSACTION_TYPES.IAP,
				`LuckyBlockIAP:{productName}`,
				{
					feature = "iap_lucky_block",
					content_id = blockId,
					context = "shop",
					quantity = grantCount,
				}
			)
		end
	end

	if successCount <= 0 then
		warn("[MonetizationController] Failed to grant lucky block reward for product:", productName, blockId)
		return false
	end

	if notif then
		local blockDisplayName = firstTool and firstTool.Name or blockId
		if successCount == 1 then
			notif:FireClient(player, "You got " .. blockDisplayName .. "!", "Success")
		else
			notif:FireClient(player, string.format("You got %dx %s!", successCount, blockDisplayName), "Success")
		end
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
				if PlayerController.ApplyWalkSpeed then
					PlayerController:ApplyWalkSpeed(player)
				end
			end

			if targetUpgradeConfig.HiddenInUI ~= true then
				local tutorialService = getTutorialService()
				if tutorialService then
					tutorialService:HandlePostTutorialCharacterUpgradePurchased(player, targetUpgradeConfig.Id)
				end
			end

			local UpgradesSystem = require(ServerScriptService.Modules.UpgradesSystem)
			UpgradesSystem.UpdateClientUI(player)
			AnalyticsFunnelsService:HandleStatUpgradePurchased(player, targetUpgradeConfig.Id, "robux", "upgrades")
			logStorePurchaseSuccess(player, "product", productId, targetUpgradeConfig.Id, "robux", "upgrades")

			if notif then
				notif:FireClient(player, targetUpgradeConfig.DisplayName .. " Purchased!", "Success")
			end
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
			AnalyticsFunnelsService:HandleBombPurchased(player, targetBombName, "robux", "pickaxes")
			logStorePurchaseSuccess(player, "product", productId, targetBombName, "robux", "pickaxes")
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
		logStorePurchaseSuccess(player, "product", productId, productName, "robux", "rebirth")
		playPurchaseEffects(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if productName == "MegaExplosion" or productName == "Shield" then
		if not BoosterService then
			BoosterService = require(ServerScriptService.Modules.BoosterService)
		end

		local endsAt = BoosterService:ActivateTimedBooster(player, productName)
		if endsAt > 0 then
			local fromRewardedAd = isRewardedAdReceipt(receiptInfo)
			local paymentType = if fromRewardedAd then "rewarded_ad" else "robux"
			local boosterConfig = ProductConfigurations.Boosters[productName]
			local displayName = if type(boosterConfig) == "table" and type(boosterConfig.DisplayName) == "string"
				then boosterConfig.DisplayName
				else productName

			logStorePurchaseSuccess(player, "product", productId, productName, paymentType, if fromRewardedAd then "rewarded_ad" else nil)
			if notif then
				local sourceText = if fromRewardedAd then " from ad" else ""
				notif:FireClient(player, displayName .. " activated" .. sourceText .. " for 10 minutes!", "Success")
			end
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if productName == "NukeBooster" then
		if not BoosterService then
			BoosterService = require(ServerScriptService.Modules.BoosterService)
		end

		local success = BoosterService:TriggerNukeBooster(player)
		if notif then
			notif:FireClient(player, if success then "Nuke incoming!" else "Nuke failed: enter mining zone", if success then "Success" else "Error")
		end
		logStorePurchaseSuccess(player, "product", productId, productName, "robux")
		if success then
			playPurchaseEffects(player)
		end
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
			logStorePurchaseSuccess(player, "product", productId, productName, "robux", "playtime_rewards")
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
			logStorePurchaseSuccess(player, "product", productId, productName, "robux", "playtime_rewards")
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if productName == "OfflineIncomeX5" then
		if not OfflineIncomeController then
			OfflineIncomeController = require(ServerScriptService.Controllers.OfflineIncomeController)
		end

		local success = false
		local rewardGranted = false
		if OfflineIncomeController and OfflineIncomeController.HandleRobuxClaim then
			success, rewardGranted = OfflineIncomeController:HandleRobuxClaim(player)
		end

		if success then
			if rewardGranted then
				AnalyticsEconomyService:LogEntitlementGranted(player, "OfflineIncomeX5", productName, nil, {
					feature = "offline_income",
					content_id = productName,
					context = "shop",
				})
				logStorePurchaseSuccess(player, "product", productId, productName, "robux", "offline_income")
				playPurchaseEffects(player)
			end
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
			logStorePurchaseSuccess(player, "product", productId, productName, "robux", "daily_rewards")
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local luckyBlockReward = ProductConfigurations.LuckyBlockProductRewards[productName]
	if luckyBlockReward then
		local rewardBlockId: string? = nil
		local rewardQuantity: number = 1
		if type(luckyBlockReward) == "string" then
			rewardBlockId = luckyBlockReward
		elseif type(luckyBlockReward) == "table" then
			rewardBlockId = luckyBlockReward.BlockId
			rewardQuantity = luckyBlockReward.Quantity
		end

		if type(rewardBlockId) == "string" and rewardBlockId ~= "" and grantLuckyBlockProductReward(player, productName, rewardBlockId, rewardQuantity, notif) then
			logStorePurchaseSuccess(player, "product", productId, productName, "robux")
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

			logStorePurchaseSuccess(player, "product", productId, productName, "robux")

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
		logStorePurchaseSuccess(player, "product", productId, productName, "robux")
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
			logStorePurchaseSuccess(player, "product", productId, productName, "robux")
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
			logStorePurchaseSuccess(player, "product", productId, productName, "robux", "daily_spin")

			if notif then notif:FireClient(player, "+" .. spinAmount .. " Spins Purchased!", "Success") end
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	if productName == "CandySpinsX3" or productName == "CandySpinsX9" then
		if not PlayerController then PlayerController = require(ServerScriptService.Controllers.PlayerController) end
		local profile = PlayerController:GetProfile(player)
		if profile then
			local spinAmount = (productName == "CandySpinsX3") and 3 or 9
			PlayerController:AddPaidCandySpins(player, spinAmount)
			AnalyticsEconomyService:LogEntitlementGranted(player, "CandySpinPack", productName, nil, {
				feature = "candy_spin",
				content_id = productName,
				context = "shop",
			})
			logStorePurchaseSuccess(player, "product", productId, productName, "robux", "candy_wheel")

			if notif then notif:FireClient(player, "+" .. spinAmount .. " Candy Spins Purchased!", "Success") end
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationController:Init(controllers)
	PlaytimeRewardController = controllers.PlaytimeRewardController
	DailyRewardController = controllers.DailyRewardController
	OfflineIncomeController = controllers.OfflineIncomeController
	print("[MonetizationController] Initialized")
end

function MonetizationController:Start()
	MarketplaceService.ProcessReceipt = MonetizationController.ProcessReceipt
end

return MonetizationController
