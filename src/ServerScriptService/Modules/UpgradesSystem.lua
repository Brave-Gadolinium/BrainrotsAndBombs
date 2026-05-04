--!strict
-- LOCATION: ServerScriptService/Modules/UpgradesSystem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local UpgradesSystem = {}

local PlayerController 
local TutorialService
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfigurations)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()
local MAX_CARRY_UPGRADES = UpgradesConfiguration.MaxCarryUpgrades or 3

local function getUpgradeConfig(upgradeId: string)
	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		if config.Id == upgradeId then return config end
	end
	return nil
end

local function getUpgradeDefaultValue(config): number
	return math.max(0, tonumber(config.DefaultValue) or 0)
end

-- Calculates the compound price based on the amount being bought
local function getCompoundPrice(config: any, currentValue: number): number
	local baseCost = config.BaseCost or 5000
	local priceMultiplier = config.PriceMultiplier or 1.5
	local amount = config.Amount or 1

	local totalPrice = 0
	local tempValue = math.max(0, currentValue - getUpgradeDefaultValue(config))

	for i = 1, amount do
		local cost = baseCost * (priceMultiplier ^ tempValue)
		totalPrice += cost
		tempValue += 1
	end

	return math.floor(totalPrice)
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

local function getResolvedPrice(player: Player, profile: any, config: any, currentValue: number): (number, boolean)
	local tutorialService = getTutorialService()
	if tutorialService
		and tutorialService.IsTutorialCharacterUpgradeFreeAvailable
		and tutorialService:IsTutorialCharacterUpgradeFreeAvailable(player, config.Id) then
		return 0, true
	end

	return getCompoundPrice(config, currentValue), false
end

function UpgradesSystem.PurchaseUpgrade(player: Player, upgradeId: string)
	local profile = PlayerController:GetProfile(player)
	local config = getUpgradeConfig(upgradeId)
	if not profile or not config then return end

	local statId = config.StatId
	local currentValue = profile.Data[statId] or 0

	-- Enforce Max Carry Limit
	if statId == "CarryCapacity" and currentValue >= getUpgradeDefaultValue(config) + MAX_CARRY_UPGRADES then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("ShowNotification") then 
			Events.ShowNotification:FireClient(player, "Max Carry Capacity Reached!", "Error") 
		end
		return
	end

	local price, isTutorialFree = getResolvedPrice(player, profile, config, currentValue)
	AnalyticsFunnelsService:HandleUpgradePurchaseRequested(player, upgradeId)
	AnalyticsEconomyService:FlushBombIncome(player)

	if isTutorialFree or PlayerController:DeductMoney(player, price) then
		-- Increase the actual stat
		profile.Data[statId] = currentValue + config.Amount
		if not isTutorialFree and price > 0 then
			AnalyticsEconomyService:LogCashSink(player, price, TRANSACTION_TYPES.Shop, `Upgrade:{upgradeId}`, {
				feature = "upgrade",
				content_id = upgradeId,
				context = "base",
			})
		end

		-- Save Attribute so client can read it
		player:SetAttribute(statId, profile.Data[statId])

		-- ## FIXED: Apply Physical Stat changes immediately with a base of 20 ##
		if statId == "BonusSpeed" then
			if PlayerController.ApplyWalkSpeed then
				PlayerController:ApplyWalkSpeed(player)
			end
		end

		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("ShowNotification") then 
			Events.ShowNotification:FireClient(player, config.DisplayName .. " Upgraded!", "Success") 
		end
		AnalyticsFunnelsService:HandleStatUpgradePurchased(player, upgradeId)

		if config.HiddenInUI ~= true then
			local tutorialService = getTutorialService()
			if tutorialService then
				tutorialService:HandlePostTutorialCharacterUpgradePurchased(player, upgradeId)
			end
		end

		UpgradesSystem.UpdateClientUI(player)
	else
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("ShowNotification") then 
			Events.ShowNotification:FireClient(player, "Not enough money!", "Error") 
		end
		AnalyticsFunnelsService:LogFailure(player, "not_enough_money", {
			zone = "base",
			funnel = "StatUpgradesConversion",
			upgrade_id = upgradeId,
		})
	end
end

function UpgradesSystem.UpdateClientUI(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	local uiData = {}

	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		local statId = config.StatId
		local currentVal = profile.Data[statId] or 0
		local resolvedCost, isTutorialFree = getResolvedPrice(player, profile, config, currentVal)

		uiData[config.Id] = { 
			Current = currentVal, 
			Cost = resolvedCost,
			Amount = config.Amount,
			IsTutorialFree = isTutorialFree,
		}
	end

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local updateEvent = Events and Events:FindFirstChild("UpdateUpgradesUI")
	if updateEvent then updateEvent:FireClient(player, uiData) end
end

function UpgradesSystem:Init(controllers)
	PlayerController = controllers.PlayerController
	local Events = ReplicatedStorage:WaitForChild("Events")

	local purchaseEvent = Events:FindFirstChild("RequestUpgradeAction") or Events:FindFirstChild("PurchaseUpgrade") 
	if not purchaseEvent then
		purchaseEvent = Instance.new("RemoteEvent")
		purchaseEvent.Name = "RequestUpgradeAction"
		purchaseEvent.Parent = Events
	end

	local updateEvent = Events:FindFirstChild("UpdateUpgradesUI") or Instance.new("RemoteEvent")
	updateEvent.Name = "UpdateUpgradesUI"
	updateEvent.Parent = Events

	purchaseEvent.OnServerEvent:Connect(function(player, upgradeId)
		UpgradesSystem.PurchaseUpgrade(player, upgradeId)
	end)

	updateEvent.OnServerEvent:Connect(function(player)
		local retries = 0
		local profile = PlayerController:GetProfile(player)
		while not profile and retries < 10 do
			task.wait(0.5)
			profile = PlayerController:GetProfile(player)
			retries += 1
		end
		if profile then UpgradesSystem.UpdateClientUI(player) end
	end)
end

function UpgradesSystem:Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			task.wait(1)
			local profile = PlayerController:GetProfile(player)
			if profile then
				if PlayerController.ApplyWalkSpeed then
					PlayerController:ApplyWalkSpeed(player)
				end
			end
		end)
	end)
end

return UpgradesSystem
