--!strict
-- LOCATION: StarterPlayerScripts/ProductTouchPurchaseController

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local LuckyBlockConfiguration = require(ReplicatedStorage.Modules.LuckyBlockConfiguration)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local RarityManager = require(ReplicatedStorage.Modules.RarityManager)
local RarityUtils = require(ReplicatedStorage.Modules.RarityUtils)

local localPlayer = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestLimitedProductPrompt = events:WaitForChild("RequestLimitedProductPrompt") :: RemoteFunction
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent
local limitedProductStocks = ReplicatedStorage:WaitForChild("LimitedProductStocks")

local PRODUCT_MODEL_TAG = "ProductModel"
local PRODUCT_ID_ATTRIBUTE = "ProductId"
local TOUCH_COOLDOWN = 1.5

type ProductInstanceState = {
	Connections: {RBXScriptConnection},
	ConnectedParts: {[BasePart]: boolean},
	LastPromptAt: number,
	IdleTrack: AnimationTrack?,
	IdleAnimationId: string?,
}

type BillboardMetadata = {
	DisplayName: string?,
	RarityText: string?,
	RarityColor: Color3?,
	NumbersText: string?,
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

type AnimationPlaybackController = Humanoid | AnimationController

local productInstanceStates: {[Instance]: ProductInstanceState} = {}
local globalPromptLockedUntil = 0

local function getProductInstanceState(productInstance: Instance): ProductInstanceState
	local state = productInstanceStates[productInstance]
	if state then
		return state
	end

	state = {
		Connections = {},
		ConnectedParts = {},
		LastPromptAt = 0,
		IdleTrack = nil,
		IdleAnimationId = nil,
	}
	productInstanceStates[productInstance] = state
	return state
end

local function cleanupProductInstance(productInstance: Instance)
	local state = productInstanceStates[productInstance]
	if not state then
		return
	end

	if state.IdleTrack then
		pcall(function()
			state.IdleTrack:Stop(0)
			state.IdleTrack:Destroy()
		end)
	end

	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end

	productInstanceStates[productInstance] = nil
end

local function isLocalCharacterTouch(hit: BasePart): boolean
	local character = localPlayer.Character
	if not character then
		return false
	end

	return hit:IsDescendantOf(character)
end

local function normalizeProductId(rawValue: any): number?
	local numericValue: number?

	if type(rawValue) == "number" then
		numericValue = rawValue
	elseif type(rawValue) == "string" then
		numericValue = tonumber(rawValue)
	end

	if type(numericValue) ~= "number" or numericValue <= 0 then
		return nil
	end

	return math.floor(numericValue)
end

local function getProductIdFromInstance(instance: Instance?): number?
	if not instance then
		return nil
	end

	return normalizeProductId(instance:GetAttribute(PRODUCT_ID_ATTRIBUTE))
end

local function getProductId(productInstance: Instance): number?
	local directProductId = getProductIdFromInstance(productInstance)
	if directProductId then
		return directProductId
	end

	local currentParent = productInstance.Parent
	while currentParent do
		local parentProductId = getProductIdFromInstance(currentParent)
		if parentProductId then
			return parentProductId
		end

		currentParent = currentParent.Parent
	end

	for _, descendant in ipairs(productInstance:GetDescendants()) do
		local descendantProductId = getProductIdFromInstance(descendant)
		if descendantProductId then
			return descendantProductId
		end
	end

	return nil
end

local function isValidAnimation(animation: Animation): boolean
	local animationId = animation.AnimationId
	return type(animationId) == "string" and animationId ~= "" and animationId ~= "rbxassetid://"
end

local function instancePathContainsIdle(instance: Instance, root: Model): boolean
	local current: Instance? = instance
	while current and current ~= root do
		if string.find(string.lower(current.Name), "idle", 1, true) then
			return true
		end

		current = current.Parent
	end

	return false
end

local function findIdleAnimation(model: Model): Animation?
	local fallbackAnimation: Animation? = nil
	local validAnimationCount = 0

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Animation") and isValidAnimation(descendant) then
			validAnimationCount += 1
			fallbackAnimation = fallbackAnimation or descendant

			if instancePathContainsIdle(descendant, model) then
				return descendant
			end
		end
	end

	if validAnimationCount == 1 then
		return fallbackAnimation
	end

	return nil
end

local function findAnimationController(model: Model): AnimationPlaybackController?
	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid and humanoid:IsA("Humanoid") then
		return humanoid
	end

	local animationController = model:FindFirstChildWhichIsA("AnimationController", true)
	if animationController and animationController:IsA("AnimationController") then
		return animationController
	end

	return nil
end

local function getOrCreateAnimator(animationController: AnimationPlaybackController): Animator
	local animator = animationController:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local createdAnimator = Instance.new("Animator")
	createdAnimator.Parent = animationController
	return createdAnimator
end

local function findPlayingTrackByAnimationId(animator: Animator, animationId: string): AnimationTrack?
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local trackAnimation = track.Animation
		if trackAnimation and trackAnimation.AnimationId == animationId then
			return track
		end
	end

	return nil
end

local function ensureIdleAnimationPlaying(model: Model)
	local state = getProductInstanceState(model)
	if state.IdleTrack and state.IdleTrack.IsPlaying then
		return
	end

	local idleAnimation = findIdleAnimation(model)
	if not idleAnimation then
		return
	end

	local animationController = findAnimationController(model)
	if not animationController then
		return
	end

	local animator = getOrCreateAnimator(animationController)
	local animationId = idleAnimation.AnimationId
	local existingTrack = findPlayingTrackByAnimationId(animator, animationId)
	if existingTrack then
		state.IdleTrack = existingTrack
		state.IdleAnimationId = animationId
		return
	end

	if state.IdleTrack then
		pcall(function()
			state.IdleTrack:Stop(0)
			state.IdleTrack:Destroy()
		end)
		state.IdleTrack = nil
	end

	local success, trackOrError = pcall(function()
		local track = animator:LoadAnimation(idleAnimation)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play(0.1)
		return track
	end)

	if not success then
		warn("[ProductTouchPurchaseController] Failed to play idle animation for", model:GetFullName(), trackOrError)
		return
	end

	state.IdleTrack = trackOrError
	state.IdleAnimationId = animationId
end

local function isInsideBillboardGui(instance: Instance): boolean
	local current: Instance? = instance.Parent
	while current do
		if current:IsA("BillboardGui") then
			return true
		end

		current = current.Parent
	end

	return false
end

local function resolveRarityDisplay(rarity: string?): (string?, Color3?)
	local normalizedRarity = RarityUtils.Normalize(rarity)
	local displayName = RarityUtils.GetDisplayName(normalizedRarity or rarity) or rarity
	if not displayName then
		return nil, nil
	end

	local rarityInfo = normalizedRarity and RarityManager.GetRarityInfo(normalizedRarity) or nil
	return displayName, rarityInfo and rarityInfo.TextColor or nil
end

local function resolveItemMetadata(productName: string): BillboardMetadata?
	local rewardData = ProductConfigurations.ItemProductRewards[productName]
	if not rewardData then
		return nil
	end

	local itemName = rewardData.Name
	if type(itemName) ~= "string" or itemName == "" then
		return nil
	end

	local itemData = ItemConfigurations.GetItemData(itemName)
	if not itemData then
		return {
			DisplayName = itemName,
			RarityText = nil,
			RarityColor = nil,
			NumbersText = nil,
		}
	end

	local rarityText, rarityColor = resolveRarityDisplay(itemData.Rarity)
	return {
		DisplayName = itemData.DisplayName or itemName,
		RarityText = rarityText,
		RarityColor = rarityColor,
		NumbersText = nil,
	}
end

local function resolveLuckyBlockMetadata(productName: string): BillboardMetadata?
	local rewardData = ProductConfigurations.LuckyBlockProductRewards[productName]
	local blockId: string? = nil
	local quantity = 1

	if type(rewardData) == "string" then
		blockId = rewardData
	elseif type(rewardData) == "table" then
		blockId = rewardData.BlockId
		quantity = math.max(1, math.floor(tonumber(rewardData.Quantity) or 1))
	end

	if type(blockId) ~= "string" or blockId == "" then
		return nil
	end

	local blockConfig = LuckyBlockConfiguration.GetBlockConfig(blockId)
	if not blockConfig then
		return nil
	end

	local rarityText, rarityColor = resolveRarityDisplay(blockConfig.Rarity)
	local displayName = blockConfig.DisplayName
	if quantity > 1 then
		displayName = string.format("%dx %s", quantity, displayName)
	end

	return {
		DisplayName = displayName,
		RarityText = rarityText,
		RarityColor = rarityColor,
		NumbersText = nil,
	}
end

local function getLimitedNumbersText(productId: number): string?
	local limitedConfig = ProductConfigurations.GetLimitedItemProductConfigById(productId)
	if not limitedConfig then
		return nil
	end

	local total = math.max(0, math.floor(tonumber(limitedConfig.Total) or 0))
	local stockEntry = limitedProductStocks:FindFirstChild(tostring(productId))
	local remaining = total

	if stockEntry then
		remaining = math.max(0, math.floor(tonumber(stockEntry:GetAttribute("Remaining")) or total))
	end

	return string.format("%d/%d", remaining, total)
end

local function isLimitedProductSoldOut(productId: number): boolean
	local stockEntry = limitedProductStocks:FindFirstChild(tostring(productId))
	if not stockEntry then
		return false
	end

	return stockEntry:GetAttribute("SoldOut") == true
end

local function resolveBillboardMetadata(productId: number): BillboardMetadata?
	local productName = ProductConfigurations.GetProductById(productId)
	if not productName then
		return nil
	end

	local metadata = resolveItemMetadata(productName) or resolveLuckyBlockMetadata(productName)
	if not metadata then
		return nil
	end

	metadata.NumbersText = getLimitedNumbersText(productId)
	return metadata
end

local function refreshBillboards(productInstance: Instance)
	local productId = getProductId(productInstance)
	if not productId then
		return
	end

	local metadata = resolveBillboardMetadata(productId)
	if not metadata then
		return
	end

	for _, descendant in ipairs(productInstance:GetDescendants()) do
		if descendant:IsA("TextLabel") and isInsideBillboardGui(descendant) then
			if descendant.Name == "Name" and metadata.DisplayName then
				descendant.Text = metadata.DisplayName
			elseif descendant.Name == "Rare" and metadata.RarityText then
				descendant.Text = metadata.RarityText
				if metadata.RarityColor then
					descendant.TextColor3 = metadata.RarityColor
				end
			elseif descendant.Name == "Numbers" and metadata.NumbersText then
				descendant.Text = metadata.NumbersText
			end
		end
	end
end

local function requestLimitedPrompt(productId: number): PromptRequestResult
	local success, resultOrError = pcall(function()
		return requestLimitedProductPrompt:InvokeServer(productId)
	end)

	if not success then
		warn("[ProductTouchPurchaseController] Failed to request limited prompt for ProductId:", productId, resultOrError)
		return {
			Success = false,
			Reason = "Error",
			Message = "Product is unavailable right now.",
		}
	end

	if type(resultOrError) == "table" then
		return resultOrError
	end

	return {
		Success = false,
		Reason = "Error",
		Message = "Product is unavailable right now.",
	}
end

local function reportStorePromptFailed(productId: number?, productName: string?, limited: boolean, reason: string)
	reportAnalyticsIntent:FireServer("StorePromptFailed", {
		surface = "product_touch",
		section = "world",
		entrypoint = "touch",
		productName = productName,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
		reason = reason,
		limited = limited,
	})
end

local function releaseLimitedPromptReservation(productId: number)
	local releaseRequest: PromptReleaseRequest = {
		Action = "Release",
		ProductId = productId,
	}

	local success, resultOrError = pcall(function()
		return requestLimitedProductPrompt:InvokeServer(releaseRequest)
	end)

	if not success then
		warn("[ProductTouchPurchaseController] Failed to release limited prompt reservation for ProductId:", productId, resultOrError)
	end
end

local function promptProductPurchase(productInstance: Instance)
	local productId = getProductId(productInstance)
	if not productId then
		warn("[ProductTouchPurchaseController] Missing ProductId for", productInstance:GetFullName())
		return
	end
	local productName = ProductConfigurations.GetProductById(productId)
	local isLimitedProduct = ProductConfigurations.IsLimitedItemProductId(productId)

	local now = os.clock()
	local state = getProductInstanceState(productInstance)
	if now < globalPromptLockedUntil or (now - state.LastPromptAt) < TOUCH_COOLDOWN then
		return
	end

	state.LastPromptAt = now
	globalPromptLockedUntil = now + TOUCH_COOLDOWN

	if isLimitedProduct then
		if isLimitedProductSoldOut(productId) then
			refreshBillboards(productInstance)
			reportStorePromptFailed(productId, productName, true, "sold_out")
			NotificationManager.show("Sold out!", "Error")
			return
		end

		local promptReservationResult = requestLimitedPrompt(productId)
		if promptReservationResult.Success ~= true then
			refreshBillboards(productInstance)
			reportStorePromptFailed(productId, productName or promptReservationResult.ProductName, true, promptReservationResult.Reason or "reservation_failed")

			local errorMessage = promptReservationResult.Message
			if type(errorMessage) == "string" and errorMessage ~= "" then
				NotificationManager.show(errorMessage, "Error")
			end
			return
		end
	end

	reportAnalyticsIntent:FireServer("ProductTouchPrompted", {
		productId = productId,
		productName = productName,
		limited = isLimitedProduct,
	})

	local success, err = pcall(function()
		MarketplaceService:PromptProductPurchase(localPlayer, productId)
	end)

	if not success then
		if isLimitedProduct then
			releaseLimitedPromptReservation(productId)
			refreshBillboards(productInstance)
		end

		warn("[ProductTouchPurchaseController] Failed to prompt product purchase for", productInstance:GetFullName(), "ProductId:", productId, err)
		reportStorePromptFailed(productId, productName, isLimitedProduct, "prompt_failed")
		NotificationManager.show("Purchase prompt is unavailable right now.", "Error")
	end
end

local function connectPart(productInstance: Instance, part: BasePart)
	local state = getProductInstanceState(productInstance)
	if state.ConnectedParts[part] then
		return
	end

	state.ConnectedParts[part] = true
	table.insert(state.Connections, part.Touched:Connect(function(hit)
		if not isLocalCharacterTouch(hit) then
			return
		end

		promptProductPurchase(productInstance)
	end))
end

local function connectStockState(productInstance: Instance)
	local productId = getProductId(productInstance)
	if not productId or not ProductConfigurations.IsLimitedItemProductId(productId) then
		return
	end

	local entryName = tostring(productId)
	local state = getProductInstanceState(productInstance)

	local function connectStockEntry(stockEntry: Instance)
		table.insert(state.Connections, stockEntry:GetAttributeChangedSignal("Remaining"):Connect(function()
			refreshBillboards(productInstance)
		end))
		table.insert(state.Connections, stockEntry:GetAttributeChangedSignal("Total"):Connect(function()
			refreshBillboards(productInstance)
		end))
		table.insert(state.Connections, stockEntry:GetAttributeChangedSignal("SoldOut"):Connect(function()
			refreshBillboards(productInstance)
		end))
	end

	local stockEntry = limitedProductStocks:FindFirstChild(entryName)
	if stockEntry then
		connectStockEntry(stockEntry)
	end

	table.insert(state.Connections, limitedProductStocks.ChildAdded:Connect(function(child)
		if child.Name == entryName then
			connectStockEntry(child)
			refreshBillboards(productInstance)
		end
	end))
end

local function connectProductInstance(instance: Instance)
	if productInstanceStates[instance] then
		return
	end

	local state = getProductInstanceState(instance)

	if instance:IsA("BasePart") then
		connectPart(instance, instance)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
			connectPart(instance, descendant)
		end
	end

	if instance:IsA("Model") then
		ensureIdleAnimationPlaying(instance)
	end

	refreshBillboards(instance)
	connectStockState(instance)

	table.insert(state.Connections, instance.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
			connectPart(instance, descendant)
		end

		if descendant:IsA("BillboardGui") or descendant:IsA("TextLabel") or descendant:IsA("UIStroke") or descendant:IsA("UIGradient") then
			task.defer(refreshBillboards, instance)
		end

		if instance:IsA("Model")
			and (descendant:IsA("Animation") or descendant:IsA("Humanoid") or descendant:IsA("AnimationController") or descendant:IsA("Animator")) then
			task.defer(ensureIdleAnimationPlaying, instance)
		end
	end))

	table.insert(state.Connections, instance.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupProductInstance(instance)
		end
	end))
end

for _, instance in ipairs(CollectionService:GetTagged(PRODUCT_MODEL_TAG)) do
	connectProductInstance(instance)
end

CollectionService:GetInstanceAddedSignal(PRODUCT_MODEL_TAG):Connect(connectProductInstance)
CollectionService:GetInstanceRemovedSignal(PRODUCT_MODEL_TAG):Connect(function(instance)
	cleanupProductInstance(instance)
end)
