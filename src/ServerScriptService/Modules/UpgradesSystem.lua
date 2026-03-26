--!strict
-- LOCATION: ServerScriptService/Modules/UpgradesSystem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local UpgradesSystem = {}

local PlayerController 
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfigurations)

local function getUpgradeConfig(upgradeId: string)
	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		if config.Id == upgradeId then return config end
	end
	return nil
end

-- Calculates the compound price based on the amount being bought
local function getCompoundPrice(config: any, currentValue: number): number
	local baseCost = config.BaseCost or 5000
	local priceMultiplier = config.PriceMultiplier or 1.5
	local amount = config.Amount or 1

	local totalPrice = 0
	local tempValue = currentValue

	for i = 1, amount do
		local cost = baseCost * (priceMultiplier ^ tempValue)
		totalPrice += cost
		tempValue += 1
	end

	return math.floor(totalPrice)
end

function UpgradesSystem.PurchaseUpgrade(player: Player, upgradeId: string)
	local profile = PlayerController:GetProfile(player)
	local config = getUpgradeConfig(upgradeId)
	if not profile or not config then return end

	local statId = config.StatId
	local currentValue = profile.Data[statId] or 0

	-- Enforce Max Carry Limit
	if statId == "CarryCapacity" and currentValue >= 3 then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("ShowNotification") then 
			Events.ShowNotification:FireClient(player, "Max Carry Capacity Reached!", "Error") 
		end
		return
	end

	local price = getCompoundPrice(config, currentValue)

	if PlayerController:DeductMoney(player, price) then
		-- Increase the actual stat
		profile.Data[statId] = currentValue + config.Amount

		-- Save Attribute so client can read it
		player:SetAttribute(statId, profile.Data[statId])

		-- ## FIXED: Apply Physical Stat changes immediately with a base of 20 ##
		if statId == "BonusSpeed" then
			local char = player.Character
			local hum = char and char:FindFirstChild("Humanoid") :: Humanoid
			if hum then hum.WalkSpeed = 20 + profile.Data[statId] end
		end

		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("ShowNotification") then 
			Events.ShowNotification:FireClient(player, config.DisplayName .. " Upgraded!", "Success") 
		end

		UpgradesSystem.UpdateClientUI(player)
	else
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("ShowNotification") then 
			Events.ShowNotification:FireClient(player, "Not enough money!", "Error") 
		end
	end
end

function UpgradesSystem.UpdateClientUI(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	local uiData = {}

	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		local statId = config.StatId
		local currentVal = profile.Data[statId] or 0

		uiData[config.Id] = { 
			Current = currentVal, 
			Cost = getCompoundPrice(config, currentVal),
			Amount = config.Amount
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
				local hum = char:FindFirstChild("Humanoid") :: Humanoid
				-- ## FIXED: Apply correct base speed upon spawning into the game ##
				if hum then hum.WalkSpeed = 20 + (profile.Data["BonusSpeed"] or 0) end
			end
		end)
	end)
end

return UpgradesSystem
