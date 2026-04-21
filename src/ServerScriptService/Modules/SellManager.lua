--!strict
-- LOCATION: ServerScriptService/Modules/SellManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local SellManager = {}

-- [ MODULES ]
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local EconomyValueUtils = require(ServerScriptService.Modules.EconomyValueUtils)

local PlayerController -- Lazy Load

local BATCH_THRESHOLD = 10
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()
local DEBUG_BRAINROT_TRACE = false

-- [ HELPER: Calculate Price ]
type SoldItemData = {
	Name: string,
	Mutation: string,
	Rarity: string,
	Level: number,
	Value: number,
}

local function summarizeTool(tool: Tool): string
	return ("Tool{name=%s,orig=%s,mut=%s,rar=%s,lvl=%s,parent=%s}"):format(
		tostring(tool.Name),
		tostring(tool:GetAttribute("OriginalName")),
		tostring(tool:GetAttribute("Mutation")),
		tostring(tool:GetAttribute("Rarity")),
		tostring(tool:GetAttribute("Level")),
		tostring(tool.Parent and tool.Parent.Name or "nil")
	)
end

local function summarizeToolContainer(container: Instance?): string
	if not container then
		return "[]"
	end

	local entries = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			table.insert(entries, summarizeTool(child))
		end
	end

	table.sort(entries)
	return "[" .. table.concat(entries, ", ") .. "]"
end

local function logSellTrace(player: Player, message: string)
	if not DEBUG_BRAINROT_TRACE then
		return
	end

	print(("[BrainrotTrace][SellManager][%s][step=%s][server=%.3f] %s | char=%s | backpack=%s"):format(
		player.Name,
		tostring(player:GetAttribute("OnboardingStep")),
		Workspace:GetServerTimeNow(),
		message,
		summarizeToolContainer(player.Character),
		summarizeToolContainer(player:FindFirstChild("Backpack"))
	))
end

local function shouldBlockTutorialSell(player: Player): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep > 0
		and onboardingStep < TutorialConfiguration.FinalStep
		and (onboardingStep == 4 or onboardingStep == 5)
end

local function notifyTutorialSellBlocked(player: Player, actionType: string)
	local events = ReplicatedStorage:FindFirstChild("Events")
	local notif = events and events:FindFirstChild("ShowNotification")
	if notif then
		notif:FireClient(player, "Place the tutorial Brainrot on your base first!", "Error")
	end

	logSellTrace(player, ("tutorial sell blocked action=%s"):format(actionType))
end

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
	logSellTrace(player, "SellEquipped requested")
	if shouldBlockTutorialSell(player) then
		notifyTutorialSellBlocked(player, "Equipped")
		return
	end

	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")

	if tool then
		logSellTrace(player, ("SellEquipped found tool=%s"):format(summarizeTool(tool)))
		local soldItem = getSoldItemData(tool)
		local value = soldItem and soldItem.Value or 0

		if value > 0 then
			AnalyticsEconomyService:FlushBombIncome(player)
			logSellTrace(player, ("SellEquipped destroying tool=%s value=%s"):format(
				summarizeTool(tool),
				tostring(value)
			))
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
			logSellTrace(player, ("SellEquipped success sold=%s value=%s"):format(
				tostring(soldItem and soldItem.Name or tool.Name),
				tostring(value)
			))
		else
			-- ## FIXED: Tell them if they are trying to sell a Pickaxe! ##
			if notif then notif:FireClient(player, "This item cannot be sold!", "Error") end
			logSellTrace(player, ("SellEquipped rejected unsellable tool=%s"):format(summarizeTool(tool)))
		end
	else
		if notif then notif:FireClient(player, "Hold an item to sell it!", "Error") end
		logSellTrace(player, "SellEquipped rejected noTool")
	end
end

function SellManager.SellInventory(player: Player)
	logSellTrace(player, "SellInventory requested")
	if shouldBlockTutorialSell(player) then
		notifyTutorialSellBlocked(player, "Inventory")
		return
	end

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
					logSellTrace(player, ("SellInventory destroying tool=%s value=%s"):format(
						summarizeTool(tool),
						tostring(value)
					))
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
		logSellTrace(player, ("SellInventory success itemsSold=%s totalValue=%s"):format(
			tostring(itemsSold),
			tostring(totalValue)
		))
	else
		if notif then notif:FireClient(player, "You have no items to sell!", "Error") end
		logSellTrace(player, "SellInventory rejected empty")
	end
end

-- [ INIT ]

function SellManager:Init(controllers)
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
		logSellTrace(player, ("RequestSell received actionType=%s"):format(tostring(actionType)))
		if actionType == "Equipped" then
			SellManager.SellEquipped(player)
		elseif actionType == "Inventory" then
			SellManager.SellInventory(player)
		else
			logSellTrace(player, ("RequestSell ignored unknown actionType=%s"):format(tostring(actionType)))
		end
	end)
end

function SellManager:Start()
	-- No loop needed
end

return SellManager
