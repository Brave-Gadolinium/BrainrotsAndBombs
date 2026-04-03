--!strict
-- LOCATION: ServerScriptService/Modules/LimitedProductStockService

local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local LimitedProductStockService = {}

local STOCK_FOLDER_NAME = "LimitedProductStocks"
local REQUEST_PROMPT_REMOTE_NAME = "RequestLimitedProductPrompt"
local DATASTORE_NAME = "LimitedProductStock_v1"
local MESSAGING_TOPIC = "LimitedProductStockUpdated_v1"
local RESERVATION_TTL_SECONDS = 180
local PUBLIC_REFRESH_INTERVAL = 30
local MEMORY_FALLBACK_WARNING = "[LimitedProductStockService] Falling back to in-memory stock state; global persistence is unavailable."

type LimitedProductConfig = {
	Total: number,
}

type ReservationRecord = {
	UserId: number,
	CreatedAt: number,
	ExpiresAt: number,
	JobId: string,
}

type GrantedReceiptRecord = {
	PlayerId: number,
	ProductId: number,
	GrantedAt: number,
	Delivered: boolean,
	Oversell: boolean,
}

type StockRecord = {
	Total: number,
	SoldCount: number,
	Reservations: {[string]: ReservationRecord},
	GrantedReceipts: {[string]: GrantedReceiptRecord},
}

type PublicStockState = {
	ProductId: number,
	ProductName: string,
	Total: number,
	SoldCount: number,
	Remaining: number,
	SoldOut: boolean,
}

type PromptRequestResult = {
	Success: boolean,
	Reason: string,
	Message: string?,
	ProductId: number?,
	ProductName: string?,
	Remaining: number?,
	Total: number?,
	SoldOut: boolean?,
}

type PromptReleaseRequest = {
	Action: string,
	ProductId: number,
}

type ReceiptGrantResult = {
	Success: boolean,
	IsLimited: boolean,
	ShouldGrant: boolean,
	AlreadyDelivered: boolean,
	ProductId: number?,
	ProductName: string?,
	PurchaseId: string?,
	Remaining: number?,
	Total: number?,
	SoldOut: boolean?,
}

local dataStore: DataStore? = nil
local isPersistentStoreAvailable = false
local hasWarnedMemoryFallback = false
local messagingConnection: RBXScriptConnection? = nil
local requestPromptRemote: RemoteFunction? = nil
local stockFolder: Folder? = nil

local limitedConfigsByProductId: {[number]: LimitedProductConfig} = {}
local productNamesById: {[number]: string} = {}
local publicStateCache: {[number]: PublicStockState} = {}
local stockInstancesByProductId: {[number]: Folder} = {}

local memoryRecords: {[number]: StockRecord} = {}
local memoryLocks: {[number]: boolean} = {}

local function getReservationKey(userId: number): string
	return tostring(userId)
end

local function getPurchaseId(receiptInfo): string
	local rawPurchaseId = receiptInfo.PurchaseId
	if type(rawPurchaseId) == "string" and rawPurchaseId ~= "" then
		return rawPurchaseId
	end

	if type(rawPurchaseId) == "number" then
		return tostring(rawPurchaseId)
	end

	return string.format(
		"%s:%s:%s:%s",
		tostring(receiptInfo.PlayerId),
		tostring(receiptInfo.ProductId),
		tostring(receiptInfo.CurrencySpent or 0),
		tostring(receiptInfo.PlaceIdWherePurchased or 0)
	)
end

local function getLimitedConfigByProductId(productId: number): LimitedProductConfig?
	return limitedConfigsByProductId[productId]
end

local function getProductName(productId: number): string
	return productNamesById[productId] or tostring(productId)
end

local function warnMemoryFallback()
	if hasWarnedMemoryFallback then
		return
	end

	hasWarnedMemoryFallback = true
	warn(MEMORY_FALLBACK_WARNING)
end

local function cloneReservationRecord(rawReservation: any): ReservationRecord?
	if type(rawReservation) ~= "table" then
		return nil
	end

	local userId = math.floor(tonumber(rawReservation.UserId) or 0)
	local expiresAt = math.floor(tonumber(rawReservation.ExpiresAt) or 0)
	if userId <= 0 or expiresAt <= 0 then
		return nil
	end

	return {
		UserId = userId,
		CreatedAt = math.floor(tonumber(rawReservation.CreatedAt) or 0),
		ExpiresAt = expiresAt,
		JobId = tostring(rawReservation.JobId or ""),
	}
end

local function cloneGrantedReceiptRecord(rawReceipt: any, productId: number): GrantedReceiptRecord?
	if type(rawReceipt) ~= "table" then
		return nil
	end

	local playerId = math.floor(tonumber(rawReceipt.PlayerId) or 0)
	if playerId <= 0 then
		return nil
	end

	return {
		PlayerId = playerId,
		ProductId = math.floor(tonumber(rawReceipt.ProductId) or productId),
		GrantedAt = math.floor(tonumber(rawReceipt.GrantedAt) or 0),
		Delivered = rawReceipt.Delivered == true,
		Oversell = rawReceipt.Oversell == true,
	}
end

local function normalizeStockRecord(productId: number, rawRecord: any): StockRecord
	local limitedConfig = getLimitedConfigByProductId(productId)
	local total = math.max(0, math.floor(tonumber(limitedConfig and limitedConfig.Total) or 0))

	local record: StockRecord = {
		Total = total,
		SoldCount = 0,
		Reservations = {},
		GrantedReceipts = {},
	}

	if type(rawRecord) ~= "table" then
		return record
	end

	record.SoldCount = math.max(0, math.floor(tonumber(rawRecord.SoldCount) or 0))

	local rawReservations = rawRecord.Reservations
	if type(rawReservations) == "table" then
		for reservationKey, rawReservation in pairs(rawReservations) do
			local reservation = cloneReservationRecord(rawReservation)
			if reservation then
				record.Reservations[tostring(reservationKey)] = reservation
			end
		end
	end

	local rawGrantedReceipts = rawRecord.GrantedReceipts
	if type(rawGrantedReceipts) == "table" then
		for purchaseId, rawReceipt in pairs(rawGrantedReceipts) do
			local receiptRecord = cloneGrantedReceiptRecord(rawReceipt, productId)
			if receiptRecord then
				record.GrantedReceipts[tostring(purchaseId)] = receiptRecord
			end
		end
	end

	return record
end

local function cleanupExpiredReservations(record: StockRecord, now: number): boolean
	local didChange = false

	for reservationKey, reservation in pairs(record.Reservations) do
		if reservation.ExpiresAt <= now then
			record.Reservations[reservationKey] = nil
			didChange = true
		end
	end

	return didChange
end

local function countActiveReservations(record: StockRecord): number
	local count = 0

	for _ in pairs(record.Reservations) do
		count += 1
	end

	return count
end

local function buildPublicState(productId: number, record: StockRecord): PublicStockState
	local total = math.max(0, record.Total)
	local soldCount = math.max(0, record.SoldCount)
	local remaining = math.max(total - soldCount, 0)

	return {
		ProductId = productId,
		ProductName = getProductName(productId),
		Total = total,
		SoldCount = soldCount,
		Remaining = remaining,
		SoldOut = remaining <= 0,
	}
end

local function getOrCreateStockFolder(): Folder
	local existingFolder = ReplicatedStorage:FindFirstChild(STOCK_FOLDER_NAME)
	if existingFolder and existingFolder:IsA("Folder") then
		stockFolder = existingFolder
		return existingFolder
	end

	local createdFolder = Instance.new("Folder")
	createdFolder.Name = STOCK_FOLDER_NAME
	createdFolder.Parent = ReplicatedStorage
	stockFolder = createdFolder
	return createdFolder
end

local function getOrCreateStockInstance(productId: number): Folder
	local existingInstance = stockInstancesByProductId[productId]
	if existingInstance and existingInstance.Parent then
		return existingInstance
	end

	local folder = getOrCreateStockFolder()
	local instanceName = tostring(productId)
	local foundInstance = folder:FindFirstChild(instanceName)
	if foundInstance and foundInstance:IsA("Folder") then
		stockInstancesByProductId[productId] = foundInstance
		return foundInstance
	end

	local createdInstance = Instance.new("Folder")
	createdInstance.Name = instanceName
	createdInstance.Parent = folder
	stockInstancesByProductId[productId] = createdInstance
	return createdInstance
end

local function publicStateEquals(left: PublicStockState?, right: PublicStockState): boolean
	return left ~= nil
		and left.ProductId == right.ProductId
		and left.ProductName == right.ProductName
		and left.Total == right.Total
		and left.SoldCount == right.SoldCount
		and left.Remaining == right.Remaining
		and left.SoldOut == right.SoldOut
end

local function applyPublicState(productId: number, publicState: PublicStockState)
	publicStateCache[productId] = publicState

	local instance = getOrCreateStockInstance(productId)
	instance:SetAttribute("ProductId", publicState.ProductId)
	instance:SetAttribute("ProductName", publicState.ProductName)
	instance:SetAttribute("Total", publicState.Total)
	instance:SetAttribute("SoldCount", publicState.SoldCount)
	instance:SetAttribute("Remaining", publicState.Remaining)
	instance:SetAttribute("SoldOut", publicState.SoldOut)
end

local function broadcastPublicState(publicState: PublicStockState)
	local ok, publishError = pcall(function()
		MessagingService:PublishAsync(MESSAGING_TOPIC, publicState)
	end)

	if not ok then
		warn("[LimitedProductStockService] Failed to publish stock update:", publishError)
	end
end

local function storeSupportsPersistence(): boolean
	return isPersistentStoreAvailable and dataStore ~= nil
end

local function updateMemoryRecord(productId: number, transform: (StockRecord) -> (StockRecord, any)): (boolean, StockRecord?, any)
	warnMemoryFallback()

	while memoryLocks[productId] do
		task.wait()
	end

	memoryLocks[productId] = true

	local currentRecord = normalizeStockRecord(productId, memoryRecords[productId])
	local updatedRecord, transformResult = transform(currentRecord)
	memoryRecords[productId] = updatedRecord

	memoryLocks[productId] = nil
	return true, updatedRecord, transformResult
end

local function updatePersistentRecord(productId: number, transform: (StockRecord) -> (StockRecord, any)): (boolean, StockRecord?, any)
	local transformResult: any = nil
	local savedRecord: StockRecord? = nil

	local ok, updateError = pcall(function()
		local updatedRawRecord = (dataStore :: DataStore):UpdateAsync(tostring(productId), function(currentRecord)
			local normalizedRecord = normalizeStockRecord(productId, currentRecord)
			local nextRecord, nextResult = transform(normalizedRecord)
			transformResult = nextResult
			return nextRecord
		end)

		savedRecord = normalizeStockRecord(productId, updatedRawRecord)
	end)

	if not ok then
		warn("[LimitedProductStockService] Failed to update stock record:", productId, updateError)
		return false, nil, nil
	end

	return true, savedRecord, transformResult
end

local function updateStockRecord(productId: number, transform: (StockRecord) -> (StockRecord, any)): (boolean, StockRecord?, any)
	if storeSupportsPersistence() then
		return updatePersistentRecord(productId, transform)
	end

	return updateMemoryRecord(productId, transform)
end

local function loadStockRecord(productId: number): (boolean, StockRecord?)
	if not storeSupportsPersistence() then
		warnMemoryFallback()
		return true, normalizeStockRecord(productId, memoryRecords[productId])
	end

	local loadedRecord: StockRecord? = nil
	local ok, loadError = pcall(function()
		local rawRecord = (dataStore :: DataStore):GetAsync(tostring(productId))
		loadedRecord = normalizeStockRecord(productId, rawRecord)
	end)

	if not ok then
		warn("[LimitedProductStockService] Failed to load stock record:", productId, loadError)
		return false, nil
	end

	return true, loadedRecord
end

local function publishCurrentRecord(productId: number, record: StockRecord, shouldBroadcast: boolean?)
	local publicState = buildPublicState(productId, record)
	local previousState = publicStateCache[productId]
	local hasMeaningfulChange = not publicStateEquals(previousState, publicState)

	if hasMeaningfulChange then
		applyPublicState(productId, publicState)

		if shouldBroadcast == true and storeSupportsPersistence() then
			broadcastPublicState(publicState)
		end
	end
end

local function ensureRemoteFunction(): RemoteFunction
	if requestPromptRemote and requestPromptRemote.Parent then
		return requestPromptRemote
	end

	local eventsFolder = ReplicatedStorage:WaitForChild("Events")
	local existingRemote = eventsFolder:FindFirstChild(REQUEST_PROMPT_REMOTE_NAME)
	if existingRemote and existingRemote:IsA("RemoteFunction") then
		requestPromptRemote = existingRemote
		return existingRemote
	end

	local createdRemote = Instance.new("RemoteFunction")
	createdRemote.Name = REQUEST_PROMPT_REMOTE_NAME
	createdRemote.Parent = eventsFolder
	requestPromptRemote = createdRemote
	return createdRemote
end

function LimitedProductStockService:IsLimitedProductId(productId: number): boolean
	return getLimitedConfigByProductId(productId) ~= nil
end

function LimitedProductStockService:GetPublicState(productId: number): PublicStockState?
	return publicStateCache[productId]
end

function LimitedProductStockService:RefreshPublicState(productId: number): boolean
	local isLoadSuccessful, stockRecord = loadStockRecord(productId)
	if not isLoadSuccessful or not stockRecord then
		return false
	end

	publishCurrentRecord(productId, stockRecord, false)
	return true
end

function LimitedProductStockService:RequestPrompt(player: Player, productId: number): PromptRequestResult
	if not self:IsLimitedProductId(productId) then
		return {
			Success = false,
			Reason = "NotLimited",
			Message = "This product is not configured as a limited stand.",
		}
	end

	local reservationKey = getReservationKey(player.UserId)
	local now = os.time()
	local updateSuccessful, savedRecord, transformResult = updateStockRecord(productId, function(record)
		cleanupExpiredReservations(record, now)

		local publicState = buildPublicState(productId, record)
		if publicState.SoldOut then
			return record, {
				Success = false,
				Reason = "SoldOut",
				Message = "Sold out!",
				ProductId = productId,
				ProductName = publicState.ProductName,
				Remaining = publicState.Remaining,
				Total = publicState.Total,
				SoldOut = true,
			}
		end

		if record.Reservations[reservationKey] then
			return record, {
				Success = false,
				Reason = "Pending",
				Message = "Purchase already in progress.",
				ProductId = productId,
				ProductName = publicState.ProductName,
				Remaining = publicState.Remaining,
				Total = publicState.Total,
				SoldOut = false,
			}
		end

		local sellableRemaining = math.max(publicState.Remaining - countActiveReservations(record), 0)
		if sellableRemaining <= 0 then
			return record, {
				Success = false,
				Reason = "Reserved",
				Message = "Someone is already buying the last copy. Try again shortly.",
				ProductId = productId,
				ProductName = publicState.ProductName,
				Remaining = publicState.Remaining,
				Total = publicState.Total,
				SoldOut = false,
			}
		end

		record.Reservations[reservationKey] = {
			UserId = player.UserId,
			CreatedAt = now,
			ExpiresAt = now + RESERVATION_TTL_SECONDS,
			JobId = game.JobId,
		}

		return record, {
			Success = true,
			Reason = "Reserved",
			ProductId = productId,
			ProductName = publicState.ProductName,
			Remaining = publicState.Remaining,
			Total = publicState.Total,
			SoldOut = false,
		}
	end)

	if not updateSuccessful or not savedRecord then
		return {
			Success = false,
			Reason = "Error",
			Message = "Product is unavailable right now.",
		}
	end

	publishCurrentRecord(productId, savedRecord, false)
	return transformResult
end

function LimitedProductStockService:ReleaseReservation(userId: number, productId: number): boolean
	if not self:IsLimitedProductId(productId) then
		return false
	end

	local reservationKey = getReservationKey(userId)
	local now = os.time()
	local updateSuccessful, savedRecord, hadReservation = updateStockRecord(productId, function(record)
		cleanupExpiredReservations(record, now)

		local didReleaseReservation = record.Reservations[reservationKey] ~= nil
		record.Reservations[reservationKey] = nil
		return record, didReleaseReservation
	end)

	if not updateSuccessful or not savedRecord then
		return false
	end

	publishCurrentRecord(productId, savedRecord, false)
	return hadReservation == true
end

function LimitedProductStockService:BeginReceiptGrant(receiptInfo): ReceiptGrantResult
	local productId = math.floor(tonumber(receiptInfo.ProductId) or 0)
	if not self:IsLimitedProductId(productId) then
		return {
			Success = true,
			IsLimited = false,
			ShouldGrant = true,
			AlreadyDelivered = false,
		}
	end

	local purchaseId = getPurchaseId(receiptInfo)
	local playerId = math.floor(tonumber(receiptInfo.PlayerId) or 0)
	local reservationKey = getReservationKey(playerId)
	local now = os.time()

	local updateSuccessful, savedRecord, transformResult = updateStockRecord(productId, function(record)
		cleanupExpiredReservations(record, now)

		local existingReceipt = record.GrantedReceipts[purchaseId]
		if existingReceipt then
			local publicState = buildPublicState(productId, record)
			return record, {
				Success = true,
				IsLimited = true,
				ShouldGrant = existingReceipt.Delivered ~= true,
				AlreadyDelivered = existingReceipt.Delivered == true,
				ProductId = productId,
				ProductName = publicState.ProductName,
				PurchaseId = purchaseId,
				Remaining = publicState.Remaining,
				Total = publicState.Total,
				SoldOut = publicState.SoldOut,
			}
		end

		record.Reservations[reservationKey] = nil

		local publicStateBeforeSale = buildPublicState(productId, record)
		local isOversell = publicStateBeforeSale.Remaining <= 0
		record.SoldCount += 1
		record.GrantedReceipts[purchaseId] = {
			PlayerId = playerId,
			ProductId = productId,
			GrantedAt = now,
			Delivered = false,
			Oversell = isOversell,
		}

		local publicStateAfterSale = buildPublicState(productId, record)
		return record, {
			Success = true,
			IsLimited = true,
			ShouldGrant = true,
			AlreadyDelivered = false,
			ProductId = productId,
			ProductName = publicStateAfterSale.ProductName,
			PurchaseId = purchaseId,
			Remaining = publicStateAfterSale.Remaining,
			Total = publicStateAfterSale.Total,
			SoldOut = publicStateAfterSale.SoldOut,
		}
	end)

	if not updateSuccessful or not savedRecord then
		return {
			Success = false,
			IsLimited = true,
			ShouldGrant = false,
			AlreadyDelivered = false,
			ProductId = productId,
			ProductName = getProductName(productId),
			PurchaseId = purchaseId,
		}
	end

	publishCurrentRecord(productId, savedRecord, true)
	return transformResult
end

function LimitedProductStockService:MarkReceiptDelivered(productId: number, purchaseId: string): boolean
	if not self:IsLimitedProductId(productId) then
		return true
	end

	local updateSuccessful, savedRecord = updateStockRecord(productId, function(record)
		local grantedReceipt = record.GrantedReceipts[purchaseId]
		if grantedReceipt then
			grantedReceipt.Delivered = true
		end

		return record, true
	end)

	if not updateSuccessful or not savedRecord then
		return false
	end

	publishCurrentRecord(productId, savedRecord, false)
	return true
end

local function isPromptReleaseRequest(value: any): boolean
	return type(value) == "table"
		and value.Action == "Release"
		and type(value.ProductId) == "number"
end

local function buildReleaseResponse(productId: number, didReleaseReservation: boolean): PromptRequestResult
	local publicState = LimitedProductStockService:GetPublicState(productId)
	return {
		Success = true,
		Reason = if didReleaseReservation then "Released" else "NoReservation",
		ProductId = productId,
		ProductName = publicState and publicState.ProductName or getProductName(productId),
		Remaining = publicState and publicState.Remaining or nil,
		Total = publicState and publicState.Total or nil,
		SoldOut = publicState and publicState.SoldOut or nil,
	}
end

function LimitedProductStockService:Init()
	local limitedItemProducts = ProductConfigurations.LimitedItemProducts
	for productName, limitedConfig in pairs(limitedItemProducts) do
		local productId = ProductConfigurations.Products[productName]
		if type(productId) == "number" and productId > 0 then
			limitedConfigsByProductId[productId] = {
				Total = math.max(0, math.floor(tonumber(limitedConfig.Total) or 0)),
			}
			productNamesById[productId] = productName
		else
			warn("[LimitedProductStockService] Missing ProductId for limited product:", productName)
		end
	end

	local ok, resolvedStore = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)

	if ok then
		dataStore = resolvedStore
		isPersistentStoreAvailable = true
	else
		warn("[LimitedProductStockService] Failed to access DataStore:", resolvedStore)
		isPersistentStoreAvailable = false
		warnMemoryFallback()
	end

	getOrCreateStockFolder()
	ensureRemoteFunction()

	for productId, limitedConfig in pairs(limitedConfigsByProductId) do
		local stockInstance = getOrCreateStockInstance(productId)
		stockInstance:SetAttribute("ProductId", productId)
		stockInstance:SetAttribute("ProductName", getProductName(productId))
		stockInstance:SetAttribute("Total", limitedConfig.Total)
		stockInstance:SetAttribute("SoldCount", 0)
		stockInstance:SetAttribute("Remaining", limitedConfig.Total)
		stockInstance:SetAttribute("SoldOut", limitedConfig.Total <= 0)
	end

	(ensureRemoteFunction()).OnServerInvoke = function(player: Player, request: number | PromptReleaseRequest)
		if type(request) == "number" then
			return self:RequestPrompt(player, request)
		end

		if isPromptReleaseRequest(request) then
			local productId = math.floor(request.ProductId)
			local didReleaseReservation = self:ReleaseReservation(player.UserId, productId)
			return buildReleaseResponse(productId, didReleaseReservation)
		end

		return {
			Success = false,
			Reason = "InvalidRequest",
			Message = "Invalid limited product request.",
		}
	end
end

function LimitedProductStockService:Start()
	for productId in pairs(limitedConfigsByProductId) do
		task.spawn(function()
			self:RefreshPublicState(productId)
		end)
	end

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		if not self:IsLimitedProductId(productId) or isPurchased == true then
			return
		end

		self:ReleaseReservation(userId, productId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		for productId in pairs(limitedConfigsByProductId) do
			self:ReleaseReservation(player.UserId, productId)
		end
	end)

	local subscribeOk, subscribeResult = pcall(function()
		return MessagingService:SubscribeAsync(MESSAGING_TOPIC, function(message)
			local data = message.Data
			if type(data) ~= "table" then
				return
			end

			local productId = math.floor(tonumber(data.ProductId) or 0)
			if productId <= 0 or not self:IsLimitedProductId(productId) then
				return
			end

			local stockRecord = normalizeStockRecord(productId, {
				SoldCount = data.SoldCount,
				Total = data.Total,
				Reservations = {},
				GrantedReceipts = {},
			})
			publishCurrentRecord(productId, stockRecord, false)
		end)
	end)

	if subscribeOk then
		messagingConnection = subscribeResult
	else
		warn("[LimitedProductStockService] Failed to subscribe for stock updates:", subscribeResult)
	end

	task.spawn(function()
		while true do
			task.wait(PUBLIC_REFRESH_INTERVAL)

			for productId in pairs(limitedConfigsByProductId) do
				self:RefreshPublicState(productId)
			end
		end
	end)
end

return LimitedProductStockService
