--!strict
-- LOCATION: ServerScriptService/Modules/SellManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SellManager = {}

-- [ MODULES ]
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local EconomyValueUtils = require(ServerScriptService.Modules.EconomyValueUtils)

local PlayerController -- Lazy Load

local BATCH_THRESHOLD = 10
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

-- [ HELPER: Calculate Price ]
type SoldItemData = {
	Name: string,
	Mutation: string,
	Rarity: string,
	Level: number,
	Value: number,
}

local function getItemSellValue(tool: Tool): number
	return EconomyValueUtils.GetToolReferencePrice(tool)
end

local function getSoldItemData(tool: Tool): SoldItemData?
	local name = tool:GetAttribute("OriginalName")
	local mutation = tool:GetAttribute("Mutation")
	local level = tool:GetAttribute("Level") or 1

	if type(name) ~= "string" then return nil end

	local itemData = ItemConfigurations.GetItemData(name)
	if not itemData then return nil end

	return {
		Name = name,
		Mutation = if type(mutation) == "string" then mutation else "Normal",
		Rarity = itemData.Rarity,
		Level = tonumber(level) or 1,
		Value = getItemSellValue(tool),
	}
end

local function logSingleSale(player: Player, soldItem: SoldItemData)
	PlayerController:AddMoney(player, soldItem.Value)
	AnalyticsEconomyService:LogCashSource(player, soldItem.Value, TRANSACTION_TYPES.Shop, `Sell:{soldItem.Name}`, {
		feature = "sell",
		content_id = soldItem.Name,
		context = "base",
		rarity = soldItem.Rarity,
		mutation = soldItem.Mutation,
	})
	AnalyticsEconomyService:LogItemValueSinkForItem(
		player,
		soldItem.Name,
		soldItem.Mutation,
		soldItem.Level,
		TRANSACTION_TYPES.Shop,
		`Item:{soldItem.Name}`,
		{
			feature = "sell",
			content_id = soldItem.Name,
			context = "base",
			rarity = soldItem.Rarity,
			mutation = soldItem.Mutation,
		}
	)
end

local function logBatchSale(player: Player, soldItems: {SoldItemData})
	local groupedByRarity: {[string]: {Count: number, TotalValue: number}} = {}
	local totalValue = 0

	for _, soldItem in ipairs(soldItems) do
		totalValue += soldItem.Value
		local group = groupedByRarity[soldItem.Rarity]
		if not group then
			group = {
				Count = 0,
				TotalValue = 0,
			}
			groupedByRarity[soldItem.Rarity] = group
		end

		group.Count += 1
		group.TotalValue += soldItem.Value
	end

	PlayerController:AddMoney(player, totalValue)
	local runningCashBalance = math.max(0, AnalyticsEconomyService:EstimateCashBalance(player) - totalValue)
	local runningItemValueBalance = AnalyticsEconomyService:EstimateItemValueBalance(player) + totalValue
	local rarityKeys = {}

	for rarity in pairs(groupedByRarity) do
		table.insert(rarityKeys, rarity)
	end

	table.sort(rarityKeys)

	for _, rarity in ipairs(rarityKeys) do
		local group = groupedByRarity[rarity]
		runningCashBalance += group.TotalValue
		AnalyticsEconomyService:LogCashSource(player, group.TotalValue, TRANSACTION_TYPES.Shop, `SellBatch:{rarity}`, {
			feature = "sell_batch",
			content_id = rarity,
			context = "base",
			rarity = rarity,
			item_count = group.Count,
		}, runningCashBalance)
		runningItemValueBalance = math.max(0, runningItemValueBalance - group.TotalValue)
		AnalyticsEconomyService:LogItemValueSink(player, group.TotalValue, TRANSACTION_TYPES.Shop, `SellBatch:{rarity}`, {
			feature = "sell_batch",
			content_id = rarity,
			context = "base",
			rarity = rarity,
			item_count = group.Count,
		}, runningItemValueBalance)
	end
end

-- [ ACTIONS ]

function SellManager.SellEquipped(player: Player)
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")

	if tool then
		local soldItem = getSoldItemData(tool)
		local value = soldItem and soldItem.Value or 0

		if value > 0 then
			AnalyticsEconomyService:FlushBombIncome(player)
			tool:Destroy()
			if soldItem then
				logSingleSale(player, soldItem)
			end
			AnalyticsFunnelsService:HandleSellSuccess(player, "Equipped", 1)

			-- Notify
			if notif then notif:FireClient(player, "Sold for $"..NumberFormatter.Format(value), "Success") end

			-- PopUp Visual
			local popup = Events and Events:FindFirstChild("ShowCashPopUp")
			if popup then popup:FireClient(player, value) end
		else
			-- ## FIXED: Tell them if they are trying to sell a Pickaxe! ##
			if notif then notif:FireClient(player, "This item cannot be sold!", "Error") end
		end
	else
		if notif then notif:FireClient(player, "Hold an item to sell it!", "Error") end
	end
end

function SellManager.SellInventory(player: Player)
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character

	local totalValue = 0
	local itemsSold = 0
	local soldItems: {SoldItemData} = {}

	-- ## FIXED: Helper to scan any container for sellable items ##
	local function scanAndSell(container: Instance?)
		if not container then return end
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				local soldItem = getSoldItemData(tool)
				local value = soldItem and soldItem.Value or 0
				if value > 0 then
					totalValue += value
					itemsSold += 1
					if soldItem then
						table.insert(soldItems, soldItem)
					end
					tool:Destroy()
				end
			end
		end
	end

	-- Scan both locations!
	scanAndSell(backpack)
	scanAndSell(char)

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")

	if totalValue > 0 then
		AnalyticsEconomyService:FlushBombIncome(player)
		if #soldItems <= BATCH_THRESHOLD then
			for _, soldItem in ipairs(soldItems) do
				logSingleSale(player, soldItem)
			end
		else
			logBatchSale(player, soldItems)
		end
		AnalyticsFunnelsService:HandleSellSuccess(player, "Inventory", itemsSold)

		if notif then notif:FireClient(player, "Sold "..itemsSold.." items for $"..NumberFormatter.Format(totalValue), "Success") end

		local popup = Events and Events:FindFirstChild("ShowCashPopUp")
		if popup then popup:FireClient(player, totalValue) end
	else
		if notif then notif:FireClient(player, "You have no items to sell!", "Error") end
	end
end

-- [ INIT ]

function SellManager:Init(controllers)
	print("[SellManager] Initialized")
	PlayerController = controllers.PlayerController

	local Events = ReplicatedStorage:WaitForChild("Events")

	-- Create Remote
	local sellEvent = Events:FindFirstChild("RequestSell")
	if not sellEvent then
		sellEvent = Instance.new("RemoteEvent")
		sellEvent.Name = "RequestSell"
		sellEvent.Parent = Events
	end

	sellEvent.OnServerEvent:Connect(function(player, actionType)
		if actionType == "Equipped" then
			SellManager.SellEquipped(player)
		elseif actionType == "Inventory" then
			SellManager.SellInventory(player)
		end
	end)
end

function SellManager:Start()
	-- No loop needed
end

return SellManager
