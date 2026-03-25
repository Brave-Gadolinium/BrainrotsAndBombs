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
local RebirthSystem
local ItemManager
local PlayerController
local PlaytimeRewardController
local DailyRewardController

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

			if statId == "BonusSpeed" then
				local char = player.Character
				local hum = char and char:FindFirstChild("Humanoid") :: Humanoid
				if hum then hum.WalkSpeed = 16 + profile.Data[statId] end
			end

			local UpgradesSystem = require(ServerScriptService.Modules.UpgradesSystem)
			UpgradesSystem.UpdateClientUI(player)

			if notif then notif:FireClient(player, "+" .. upgradeAmount .. " " .. targetUpgradeConfig.DisplayName .. " Purchased!", "Success") end
			playPurchaseEffects(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not productName then return Enum.ProductPurchaseDecision.NotProcessedYet end

	if productName == "SkipRebirth" then
		if not RebirthSystem then RebirthSystem = require(ServerScriptService.Modules.RebirthSystem) end
		RebirthSystem.ForceRebirth(player)
		playPurchaseEffects(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if productName == "PlaytimeRewardsSkipAll" then
		if not PlaytimeRewardController then
			PlaytimeRewardController = require(ServerScriptService.Controllers.PlaytimeRewardController)
		end

		local success = PlaytimeRewardController:HandleSkipAll(player)
		if success then
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

		ItemManager.GiveItemToPlayer(player, itemReward.Name, itemReward.Mutation, rarity, itemReward.Level)

		if notif then notif:FireClient(player, itemReward.Name .. " Purchased!", "Success") end
		playPurchaseEffects(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local cashAmount = ProductConfigurations.CashProductRewards[productName]
	if cashAmount then
		if not PlayerController then PlayerController = require(ServerScriptService.Controllers.PlayerController) end
		PlayerController:AddMoney(player, cashAmount)
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
			ItemManager.GiveItemToPlayer(player, chosenItem.Name, "Normal", chosenItem.Rarity, 1)

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
