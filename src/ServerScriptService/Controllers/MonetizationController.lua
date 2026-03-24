--!strict
-- LOCATION: ServerScriptService/Controllers/MonetizationController

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris") 

local MonetizationController = {}

-- [ MODULES ]
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfigurations)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local RebirthSystem 
local ItemManager 
local PlayerController 

-- [[ HELPER: PLAY EFFECTS ]] --
local function playPurchaseEffects(player: Player)
	-- 1. Screen Effect
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local effectEvent = Events and Events:FindFirstChild("TriggerUIEffect")
	if effectEvent then
		effectEvent:FireClient(player, "HighlightLight")
	end

	-- 2. Confetti Effect
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

	-- 1. DYNAMIC UPGRADES (Robux DevProducts)
	-- [FIXED]: Loop through the array to find the matching RobuxProductId
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
			-- [FIXED]: Apply the stats using our new StatId and Amount logic
			local statId = targetUpgradeConfig.StatId
			local upgradeAmount = targetUpgradeConfig.Amount or 1
			local currentVal = profile.Data[statId] or 0

			profile.Data[statId] = currentVal + upgradeAmount

			-- Set Attribute instead of leaderstats
			player:SetAttribute(statId, profile.Data[statId])

			-- Apply Physical Stat changes immediately (e.g., Speed)
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

	-- Safety check for legacy products
	if not productName then return Enum.ProductPurchaseDecision.NotProcessedYet end

	-- 2. REBIRTH SKIP
	if productName == "SkipRebirth" then
		if not RebirthSystem then RebirthSystem = require(ServerScriptService.Modules.RebirthSystem) end
		RebirthSystem.ForceRebirth(player)
		playPurchaseEffects(player) 
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- 3. ITEM PRODUCTS
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

	-- 4. CASH PRODUCTS
	local cashAmount = ProductConfigurations.CashProductRewards[productName]
	if cashAmount then
		if not PlayerController then PlayerController = require(ServerScriptService.Controllers.PlayerController) end
		PlayerController:AddMoney(player, cashAmount)
		local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
		if notif then notif:FireClient(player, "$" .. NumberFormatter.Format(cashAmount) .. " Purchased!", "Success") end
		playPurchaseEffects(player) 
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- 5. RANDOM ITEM PRODUCT
	if productName == "RandomItem" then
		if not ItemManager then ItemManager = require(ServerScriptService.Modules.ItemManager) end

		local validItems = {}
		for itemName, data in pairs(ItemConfigurations.Items) do
			if data.Rarity ~= "Common" and data.Rarity ~= "Uncommon" then
				table.insert(validItems, {Name = itemName, Rarity = data.Rarity})
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

	-- 6. EXTRA SPINS PRODUCTS
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
	print("[MonetizationController] Initialized")
end

function MonetizationController:Start()
	MarketplaceService.ProcessReceipt = MonetizationController.ProcessReceipt
end

return MonetizationController