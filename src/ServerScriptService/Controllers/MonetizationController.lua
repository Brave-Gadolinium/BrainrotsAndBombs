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
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local RebirthSystem
local ItemManager
local PlayerController
local PlaytimeRewardController
local DailyRewardController
local TutorialService
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

			local UpgradesSystem = require(ServerScriptService.Modules.UpgradesSystem)
			UpgradesSystem.UpdateClientUI(player)

			if targetUpgradeConfig.HiddenInUI ~= true then
				local tutorialService = getTutorialService()
				if tutorialService then
					tutorialService:HandlePostTutorialCharacterUpgradePurchased(player, targetUpgradeConfig.Id)
				end
			end

			if notif then notif:FireClient(player, "+" .. upgradeAmount .. " " .. targetUpgradeConfig.DisplayName .. " Purchased!", "Success") end
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not productName then return Enum.ProductPurchaseDecision.NotProcessedYet end

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

	local itemReward = ProductConfigurations.ItemProductRewards[productName]
	if itemReward then
		if not ItemManager then ItemManager = require(ServerScriptService.Modules.ItemManager) end

		local itemConf = ItemConfigurations.GetItemData(itemReward.Name)
		local rarity = itemConf and itemConf.Rarity or "Common"

		local tool = ItemManager.GiveItemToPlayer(player, itemReward.Name, itemReward.Mutation, rarity, itemReward.Level)
		if tool then
			AnalyticsEconomyService:LogItemValueSourceForItem(
				player,
				itemReward.Name,
				itemReward.Mutation,
				itemReward.Level,
				TRANSACTION_TYPES.IAP,
				`ItemIAP:{productName}`,
				{
					feature = "iap_item",
					content_id = itemReward.Name,
					context = "shop",
					rarity = rarity,
					mutation = itemReward.Mutation,
				}
			)
		end

		if notif then notif:FireClient(player, itemReward.Name .. " Purchased!", "Success") end
		playPurchaseEffects(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
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
		local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
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
