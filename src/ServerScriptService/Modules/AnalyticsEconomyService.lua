--!strict

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local EconomyValueUtils = require(script.Parent.EconomyValueUtils)

type BombIncomeBufferEntry = {
	Amount: number,
	BombName: string,
	BombTier: number,
}

local AnalyticsEconomyService = {}

local PlayerController: any = nil
local initialized = false
local bombIncomeBuffers: {[Player]: {[string]: BombIncomeBufferEntry}} = {}

local BOMB_FLUSH_INTERVAL = 30

local CURRENCIES = {
	Cash = "Cash",
	Spins = "Spins",
	ItemValue = "ItemValue",
}

local TRANSACTION_TYPES = {
	IAP = Enum.AnalyticsEconomyTransactionType.IAP.Name,
	TimedReward = Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
	Onboarding = Enum.AnalyticsEconomyTransactionType.Onboarding.Name,
	Shop = Enum.AnalyticsEconomyTransactionType.Shop.Name,
	Gameplay = Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
	ContextualPurchase = Enum.AnalyticsEconomyTransactionType.ContextualPurchase.Name,
}

local function getProfile(player: Player)
	if not PlayerController then
		return nil
	end

	return PlayerController:GetProfile(player)
end

local function getBombTierFromName(bombName: string?): number
	if type(bombName) ~= "string" then
		return 0
	end

	return tonumber(bombName:match("(%d+)")) or 0
end

local function getRebirthBucket(player: Player): string
	local profile = getProfile(player)
	local rebirths = profile and profile.Data and tonumber(profile.Data.Rebirths) or 0

	if rebirths <= 0 then
		return "0"
	end
	if rebirths < 5 then
		return "1-4"
	end
	if rebirths < 10 then
		return "5-9"
	end

	return "10+"
end

local function isVip(player: Player): boolean
	if PlayerController and PlayerController.IsVIP then
		return PlayerController:IsVIP(player) == true
	end

	return player:GetAttribute("IsVIP") == true
end

local function sanitizeCustomFields(fields: {[string]: any}?): {[string]: any}?
	if not fields then
		return nil
	end

	local sanitized = {}
	for key, value in pairs(fields) do
		local valueType = typeof(value)
		if value ~= nil and (valueType == "string" or valueType == "number" or valueType == "boolean") then
			sanitized[key] = value
		end
	end

	if next(sanitized) == nil then
		return nil
	end

	return sanitized
end

local function buildCustomFields(player: Player, customFields: {[string]: any}?): {[string]: any}?
	local fields = {
		vip = isVip(player),
		rebirth_bucket = getRebirthBucket(player),
	}

	for key, value in pairs(customFields or {}) do
		fields[key] = value
	end

	return sanitizeCustomFields(fields)
end

local function safeLogEconomyEvent(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyName: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	itemSku: string?,
	customFields: {[string]: any}?
): boolean
	local success, err = pcall(function()
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			currencyName,
			amount,
			endingBalance,
			transactionType,
			itemSku or "",
			customFields
		)
	end)
	if not success then
		warn(`[AnalyticsEconomyService] Failed to log economy event {currencyName}/{transactionType}/{itemSku or "N/A"} for {player.Name}: {err}`)
		return false
	end

	return true
end

local function safeLogCustomEvent(player: Player, eventName: string, value: number, customFields: {[string]: any}?)
	local success, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value, sanitizeCustomFields(customFields))
	end)
	if not success then
		warn(`[AnalyticsEconomyService] Failed to log custom event {eventName} for {player.Name}: {err}`)
	end
end

local function getMoneyBalance(player: Player): number
	local profile = getProfile(player)
	if profile and profile.Data then
		return tonumber(profile.Data.Money) or 0
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
	if moneyValue and moneyValue:IsA("NumberValue") then
		return moneyValue.Value
	end

	return 0
end

local function getSpinBalance(player: Player): number
	local profile = getProfile(player)
	if profile and profile.Data then
		return tonumber(profile.Data.SpinNumber) or 0
	end

	return tonumber(player:GetAttribute("SpinNumber")) or 0
end

local function estimatePlotItemValue(player: Player): number
	local profile = getProfile(player)
	if not profile or not profile.Data or not profile.Data.Plots then
		return 0
	end

	local total = 0
	for _, floorData in pairs(profile.Data.Plots) do
		for _, slotData in pairs(floorData) do
			if type(slotData) == "table" then
				if type(slotData.Item) == "table" and type(slotData.Item.Name) == "string" then
					total += EconomyValueUtils.GetItemReferencePrice(
						slotData.Item.Name,
						slotData.Item.Mutation,
						tonumber(slotData.Level) or 1
					)
				elseif slotData.ContentType == "LuckyBlock" and type(slotData.LuckyBlock) == "table" and type(slotData.LuckyBlock.Id) == "string" then
					total += EconomyValueUtils.GetLuckyBlockReferencePrice(slotData.LuckyBlock.Id)
				end
			end
		end
	end

	return total
end

local function estimateLiveInventoryValue(player: Player): number
	local total = 0

	local function scanContainer(container: Instance?)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsTemporary") ~= true then
				total += EconomyValueUtils.GetToolReferencePrice(child)
			end
		end
	end

	scanContainer(player:FindFirstChild("Backpack"))
	scanContainer(player.Character)

	return total
end

local function getPlayerBombBuffer(player: Player): {[string]: BombIncomeBufferEntry}
	local buffer = bombIncomeBuffers[player]
	if buffer then
		return buffer
	end

	buffer = {}
	bombIncomeBuffers[player] = buffer
	return buffer
end

function AnalyticsEconomyService:EstimateCashBalance(player: Player): number
	return getMoneyBalance(player)
end

function AnalyticsEconomyService:EstimateSpinBalance(player: Player): number
	return getSpinBalance(player)
end

function AnalyticsEconomyService:EstimateItemValueBalance(player: Player): number
	return estimatePlotItemValue(player) + estimateLiveInventoryValue(player)
end

function AnalyticsEconomyService:LogCashSource(
	player: Player,
	amount: number,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	if amount <= 0 then
		return false
	end

	return safeLogEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Source,
		CURRENCIES.Cash,
		amount,
		tonumber(endingBalanceOverride) or self:EstimateCashBalance(player),
		transactionType,
		itemSku,
		buildCustomFields(player, customFields)
	)
end

function AnalyticsEconomyService:LogCashSink(
	player: Player,
	amount: number,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	if amount <= 0 then
		return false
	end

	return safeLogEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Sink,
		CURRENCIES.Cash,
		amount,
		tonumber(endingBalanceOverride) or self:EstimateCashBalance(player),
		transactionType,
		itemSku,
		buildCustomFields(player, customFields)
	)
end

function AnalyticsEconomyService:LogSpinSource(
	player: Player,
	amount: number,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	if amount <= 0 then
		return false
	end

	return safeLogEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Source,
		CURRENCIES.Spins,
		amount,
		tonumber(endingBalanceOverride) or self:EstimateSpinBalance(player),
		transactionType,
		itemSku,
		buildCustomFields(player, customFields)
	)
end

function AnalyticsEconomyService:LogSpinSink(
	player: Player,
	amount: number,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	if amount <= 0 then
		return false
	end

	return safeLogEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Sink,
		CURRENCIES.Spins,
		amount,
		tonumber(endingBalanceOverride) or self:EstimateSpinBalance(player),
		transactionType,
		itemSku,
		buildCustomFields(player, customFields)
	)
end

function AnalyticsEconomyService:LogItemValueSource(
	player: Player,
	amount: number,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	if amount <= 0 then
		return false
	end

	return safeLogEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Source,
		CURRENCIES.ItemValue,
		amount,
		tonumber(endingBalanceOverride) or self:EstimateItemValueBalance(player),
		transactionType,
		itemSku,
		buildCustomFields(player, customFields)
	)
end

function AnalyticsEconomyService:LogItemValueSink(
	player: Player,
	amount: number,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	if amount <= 0 then
		return false
	end

	return safeLogEconomyEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Sink,
		CURRENCIES.ItemValue,
		amount,
		tonumber(endingBalanceOverride) or self:EstimateItemValueBalance(player),
		transactionType,
		itemSku,
		buildCustomFields(player, customFields)
	)
end

function AnalyticsEconomyService:LogItemValueSourceForItem(
	player: Player,
	itemName: string,
	mutation: string?,
	level: number?,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	local amount = EconomyValueUtils.GetItemReferencePrice(itemName, mutation, level)
	return self:LogItemValueSource(player, amount, transactionType, itemSku, customFields, endingBalanceOverride)
end

function AnalyticsEconomyService:LogItemValueSinkForItem(
	player: Player,
	itemName: string,
	mutation: string?,
	level: number?,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	local amount = EconomyValueUtils.GetItemReferencePrice(itemName, mutation, level)
	return self:LogItemValueSink(player, amount, transactionType, itemSku, customFields, endingBalanceOverride)
end

function AnalyticsEconomyService:LogItemValueSourceForLuckyBlock(
	player: Player,
	blockId: string,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	local amount = EconomyValueUtils.GetLuckyBlockReferencePrice(blockId)
	return self:LogItemValueSource(player, amount, transactionType, itemSku, customFields, endingBalanceOverride)
end

function AnalyticsEconomyService:LogItemValueSinkForLuckyBlock(
	player: Player,
	blockId: string,
	transactionType: string,
	itemSku: string,
	customFields: {[string]: any}?,
	endingBalanceOverride: number?
)
	local amount = EconomyValueUtils.GetLuckyBlockReferencePrice(blockId)
	return self:LogItemValueSink(player, amount, transactionType, itemSku, customFields, endingBalanceOverride)
end

function AnalyticsEconomyService:BufferBombIncome(player: Player, bombName: string, amount: number)
	if amount <= 0 then
		return
	end

	local buffer = getPlayerBombBuffer(player)
	local bufferKey = bombName
	local entry = buffer[bufferKey]

	if not entry then
		entry = {
			Amount = 0,
			BombName = bombName,
			BombTier = getBombTierFromName(bombName),
		}
		buffer[bufferKey] = entry
	end

	entry.Amount += amount
end

function AnalyticsEconomyService:FlushBombIncome(player: Player)
	local buffer = bombIncomeBuffers[player]
	if not buffer then
		return
	end

	local entries = {}
	local totalBuffered = 0
	for bufferKey, entry in pairs(buffer) do
		totalBuffered += entry.Amount
		table.insert(entries, {
			Key = bufferKey,
			Entry = entry,
		})
	end

	table.sort(entries, function(a, b)
		local left = a.Entry
		local right = b.Entry
		if left.BombTier == right.BombTier then
			return left.BombName < right.BombName
		end
		return left.BombTier < right.BombTier
	end)

	local runningBalance = math.max(0, self:EstimateCashBalance(player) - totalBuffered)

	for _, wrappedEntry in ipairs(entries) do
		local entry = wrappedEntry.Entry
		if entry.Amount > 0 then
			runningBalance += entry.Amount
			self:LogCashSource(
				player,
				entry.Amount,
				TRANSACTION_TYPES.Gameplay,
				`Bomb:{entry.BombName}`,
				{
					feature = "bomb",
					content_id = entry.BombName,
					context = "mine",
					bomb_tier = entry.BombTier,
				},
				runningBalance
			)
		end
		buffer[wrappedEntry.Key] = nil
	end

	if next(buffer) == nil then
		bombIncomeBuffers[player] = nil
	end
end

function AnalyticsEconomyService:LogEntitlementGranted(
	player: Player,
	entitlementType: string,
	contentId: string,
	cashEquivalent: number?,
	customFields: {[string]: any}?
)
	local fields = {
		feature = "entitlement",
		content_id = contentId,
		context = entitlementType,
		entitlement_type = entitlementType,
		cash_equivalent = cashEquivalent,
	}

	for key, value in pairs(customFields or {}) do
		fields[key] = value
	end

	safeLogCustomEvent(player, "entitlement_granted", math.max(1, math.floor(cashEquivalent or 1)), buildCustomFields(player, fields))
end

function AnalyticsEconomyService:GetTransactionTypes()
	return TRANSACTION_TYPES
end

function AnalyticsEconomyService:Init(controllers)
	if initialized then
		return
	end
	initialized = true

	PlayerController = controllers.PlayerController

	Players.PlayerRemoving:Connect(function(player)
		self:FlushBombIncome(player)
		bombIncomeBuffers[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(BOMB_FLUSH_INTERVAL)
			for player in pairs(bombIncomeBuffers) do
				if player.Parent == Players then
					self:FlushBombIncome(player)
				else
					bombIncomeBuffers[player] = nil
				end
			end
		end
	end)
end

return AnalyticsEconomyService
