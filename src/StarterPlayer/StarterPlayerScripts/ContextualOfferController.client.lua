--!strict
-- LOCATION: StarterPlayerScripts/ContextualOfferController

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local ContextualOfferConfiguration = require(ReplicatedStorage.Modules.ContextualOfferConfiguration)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")
local events = ReplicatedStorage:WaitForChild("Events")
local showContextualOfferEvent = events:WaitForChild("ShowContextualOffer") :: RemoteEvent
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local ROTATION_INTERVAL = 30
local SHOW_TWEEN_INFO = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local INITIAL_SCALE = 0.82
local OFFER_SURFACE = "contextual_offer"
local OFFER_CONTAINER_NAME_CANDIDATES = {
	"Pop-ups",
}
local OFFER_CONTAINER_KEYWORDS = {"offer", "popup", "suggest"}
local OFFER_KEY_ATTRIBUTE_CANDIDATES = {"OfferKey", "offerKey", "ContextualOfferKey"}
local PRODUCT_ATTRIBUTE_CANDIDATES = {"ProductName", "ProductKey", "productName"}
local GAMEPASS_ATTRIBUTE_CANDIDATES = {"GamePassName", "PassName", "GamepassName", "gamePassName"}
local FRAME_ATTRIBUTE_CANDIDATES = {"TargetFrame", "FrameName", "OpenFrame"}

local OFFER_ALIASES = {
	starterpack = "StarterPack",
	starter = "StarterPack",
	shield = "Shield",
	nuke = "NukeBooster",
	nukebooster = "NukeBooster",
	autobomb = "AutoBomb",
	autocollect = "AutoCollect",
	collectall = "AutoCollect",
	collect = "AutoCollect",
	hackerlb = "HackerLB",
	brainrotgodlb = "BrainrotGodLB",
	carryslot = "CarrySlot",
	bombupgrade = "BombUpgrade",
	bombs = "BombUpgrade",
	pickaxes = "BombUpgrade",
}

type OfferDefinition = any

type TransparencyEntry = {
	Instance: Instance,
	Property: string,
	Original: number,
}

type OfferButtonState = {
	Button: ImageButton,
	OfferKey: string,
	Definition: OfferDefinition,
	LayoutOrder: number,
	Scale: UIScale,
	TransparencyEntries: {TransparencyEntry},
	Bound: boolean,
}

local offerButtonsByInstance: {[ImageButton]: OfferButtonState} = {}
local orderedOfferButtons: {OfferButtonState} = {}
local offerContainer: GuiObject? = nil
local activeButtonState: OfferButtonState? = nil
local activeTweens: {Tween} = {}
local activeDisplayToken = 0
local currentIndex = 0
local nextRotationAt = 0
local queuedOfferKey: string? = nil
local warnedMissingContainer = false
local hideActiveOffer: (immediate: boolean?) -> ()
local priceTextCache: {[string]: string} = {}

local function normalizeToken(value: string?): string
	if type(value) ~= "string" then
		return ""
	end

	return string.lower((value :: string):gsub("[%W_]+", ""))
end

local function getResolvedOfferKey(offerKey: string, payload: {[string]: any}?): string
	if type(payload) == "table" and type(payload.ResolvedOfferKey) == "string" and payload.ResolvedOfferKey ~= "" then
		return payload.ResolvedOfferKey
	end

	return offerKey
end

local function canShowOffer(definition: OfferDefinition): boolean
	local action = definition.Action
	if not action then
		return false
	end

	if action.Type == "GamePass" then
		if action.Target == "StarterPack" then
			return player:GetAttribute("StarterPack") ~= true
		end

		if action.Target == "CollectAll" then
			return player:GetAttribute("HasCollectAll") ~= true
		end

		if action.Target == "AutoBomb" then
			return player:GetAttribute("HasAutoBomb") ~= true
		end
	end

	return true
end

local function createSyntheticDefinition(actionType: "Product" | "GamePass" | "OpenFrame", target: string): OfferDefinition
	return {
		Title = target,
		Description = "",
		ButtonText = "",
		AccentColor = Color3.new(1, 1, 1),
		Action = {
			Type = actionType,
			Target = target,
		},
	}
end

local function getOfferPriceInfo(definition: OfferDefinition): (Enum.InfoType?, number?)
	local action = definition.Action
	if not action then
		return nil, nil
	end

	if action.Type == "Product" then
		local productId = action.ProductId or ProductConfigurations.Products[action.Target]
		if type(productId) == "number" and productId > 0 then
			return Enum.InfoType.Product, productId
		end
	end

	if action.Type == "GamePass" then
		local passId = ProductConfigurations.GamePasses[action.Target]
		if type(passId) == "number" and passId > 0 then
			return Enum.InfoType.GamePass, passId
		end
	end

	return nil, nil
end

local function getCostLabel(button: ImageButton): TextLabel?
	local label = button:FindFirstChild("Cost", true)
	if label and label:IsA("TextLabel") then
		return label
	end

	return nil
end

local function setButtonCostText(button: ImageButton, text: string)
	local costLabel = getCostLabel(button)
	if not costLabel then
		return
	end

	costLabel.Text = text
end

local function updateButtonCost(button: ImageButton, definition: OfferDefinition)
	local infoType, purchaseId = getOfferPriceInfo(definition)
	if not infoType or not purchaseId then
		setButtonCostText(button, "")
		return
	end

	local cacheKey = tostring(infoType.Value) .. ":" .. tostring(purchaseId)
	local cachedText = priceTextCache[cacheKey]
	if cachedText then
		setButtonCostText(button, cachedText)
		return
	end

	task.spawn(function()
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfo(purchaseId, infoType)
		end)

		if not success or type(info) ~= "table" then
			return
		end

		local price = tonumber(info.PriceInRobux)
		if not price or price <= 0 then
			return
		end

		local priceText = " " .. tostring(math.floor(price))
		priceTextCache[cacheKey] = priceText
		if button.Parent then
			setButtonCostText(button, priceText)
		end
	end)
end

local function readStringAttribute(instance: Instance, attributeNames: {string}): string?
	for _, attributeName in ipairs(attributeNames) do
		local value = instance:GetAttribute(attributeName)
		if type(value) == "string" and value ~= "" then
			return value
		end
	end

	return nil
end

local function resolveNamedOffer(normalizedName: string): (string?, OfferDefinition?)
	if normalizedName == "" then
		return nil, nil
	end

	local aliasedOfferKey = OFFER_ALIASES[normalizedName]
	if aliasedOfferKey then
		local definition = ContextualOfferConfiguration.GetDefinition(aliasedOfferKey)
		if definition then
			return aliasedOfferKey, definition
		end
	end

	for productName in pairs(ProductConfigurations.Products) do
		if normalizeToken(productName) == normalizedName then
			return productName, createSyntheticDefinition("Product", productName)
		end
	end

	for gamePassName in pairs(ProductConfigurations.GamePasses) do
		if normalizeToken(gamePassName) == normalizedName then
			return gamePassName, createSyntheticDefinition("GamePass", gamePassName)
		end
	end

	return nil, nil
end

local function resolveOfferForButton(button: ImageButton): (string?, OfferDefinition?)
	local explicitOfferKey = readStringAttribute(button, OFFER_KEY_ATTRIBUTE_CANDIDATES)
	if explicitOfferKey then
		local definition = ContextualOfferConfiguration.GetDefinition(explicitOfferKey)
		if definition then
			return explicitOfferKey, definition
		end
	end

	local explicitProductName = readStringAttribute(button, PRODUCT_ATTRIBUTE_CANDIDATES)
	if explicitProductName and ProductConfigurations.Products[explicitProductName] then
		return explicitProductName, createSyntheticDefinition("Product", explicitProductName)
	end

	local explicitGamePassName = readStringAttribute(button, GAMEPASS_ATTRIBUTE_CANDIDATES)
	if explicitGamePassName and ProductConfigurations.GamePasses[explicitGamePassName] then
		return explicitGamePassName, createSyntheticDefinition("GamePass", explicitGamePassName)
	end

	local explicitFrameName = readStringAttribute(button, FRAME_ATTRIBUTE_CANDIDATES)
	if explicitFrameName then
		return explicitFrameName, createSyntheticDefinition("OpenFrame", explicitFrameName)
	end

	local buttonOfferKey = readStringAttribute(button, {"Offer", "OfferName"})
	if buttonOfferKey then
		local definition = ContextualOfferConfiguration.GetDefinition(buttonOfferKey)
		if definition then
			return buttonOfferKey, definition
		end
	end

	return resolveNamedOffer(normalizeToken(button.Name))
end

local function countOfferButtons(root: GuiObject): number
	local count = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ImageButton") then
			local offerKey, definition = resolveOfferForButton(descendant)
			if offerKey and definition and canShowOffer(definition) then
				count += 1
			end
		end
	end

	return count
end

local function findOfferContainer(): GuiObject?
	for _, candidateName in ipairs(OFFER_CONTAINER_NAME_CANDIDATES) do
		local candidate = hud:FindFirstChild(candidateName, true)
		if candidate and candidate:IsA("GuiObject") and countOfferButtons(candidate) > 0 then
			return candidate
		end
	end

	local bestContainer: GuiObject? = nil
	local bestCount = 0

	for _, descendant in ipairs(hud:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			local normalizedName = string.lower(descendant.Name)
			local matchesKeyword = false
			for _, keyword in ipairs(OFFER_CONTAINER_KEYWORDS) do
				if string.find(normalizedName, keyword, 1, true) then
					matchesKeyword = true
					break
				end
			end

			if not matchesKeyword then
				continue
			end

			local directButtonCount = 0
			for _, child in ipairs(descendant:GetChildren()) do
				if child:IsA("ImageButton") then
					local offerKey, definition = resolveOfferForButton(child)
					if offerKey and definition and canShowOffer(definition) then
						directButtonCount += 1
					end
				end
			end

			if directButtonCount > bestCount then
				bestCount = directButtonCount
				bestContainer = descendant
			end
		end
	end

	return bestContainer
end

local function addTransparencyEntry(entries: {TransparencyEntry}, instance: Instance, propertyName: string)
	local success, value = pcall(function()
		return (instance :: any)[propertyName]
	end)
	if success and type(value) == "number" then
		table.insert(entries, {
			Instance = instance,
			Property = propertyName,
			Original = value,
		})
	end
end

local function appendTransparencyEntries(entries: {TransparencyEntry}, instance: Instance)
	if instance:IsA("GuiObject") then
		addTransparencyEntry(entries, instance, "BackgroundTransparency")
	end

	if instance:IsA("ImageButton") or instance:IsA("ImageLabel") then
		addTransparencyEntry(entries, instance, "ImageTransparency")
	end

	if instance:IsA("TextButton") or instance:IsA("TextLabel") or instance:IsA("TextBox") then
		addTransparencyEntry(entries, instance, "TextTransparency")
		addTransparencyEntry(entries, instance, "TextStrokeTransparency")
	end

	if instance:IsA("UIStroke") then
		addTransparencyEntry(entries, instance, "Transparency")
	end
end

local function getOrCreateOfferScale(button: ImageButton): UIScale
	local existing = button:FindFirstChild("ContextualOfferScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = "ContextualOfferScale"
	scale.Parent = button
	return scale
end

local function setTransparencyAlpha(state: OfferButtonState, alpha: number)
	for _, entry in ipairs(state.TransparencyEntries) do
		local targetValue = entry.Original + ((1 - entry.Original) * alpha)
		pcall(function()
			(entry.Instance :: any)[entry.Property] = targetValue
		end)
	end
end

local function cancelActiveTweens()
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end
	table.clear(activeTweens)
end

local function createTransparencyTweens(state: OfferButtonState, tweenInfo: TweenInfo, alpha: number)
	local tweens = {}
	for _, entry in ipairs(state.TransparencyEntries) do
		local targetValue = entry.Original + ((1 - entry.Original) * alpha)
		local tween = TweenService:Create(entry.Instance :: any, tweenInfo, {
			[entry.Property] = targetValue,
		})
		table.insert(tweens, tween)
	end
	return tweens
end

local function bindOfferButton(state: OfferButtonState)
	if state.Bound then
		return
	end

	state.Bound = true
	state.Button.Activated:Connect(function()
		local currentState = offerButtonsByInstance[state.Button]
		if not currentState then
			return
		end

		local definition = currentState.Definition
		local action = definition.Action
		if not action then
			return
		end

		reportAnalyticsIntent:FireServer("ContextualOfferClicked", {
			offerKey = currentState.OfferKey,
			resolvedOfferKey = currentState.OfferKey,
			actionType = action.Type,
			target = action.Target,
		})

		if action.Type == "OpenFrame" then
			hideActiveOffer(true)
			FrameManager.open(action.Target)
			return
		end

		if action.Type == "Product" then
			local productId = action.ProductId or ProductConfigurations.Products[action.Target]
			if type(productId) == "number" and productId > 0 then
				reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
					surface = OFFER_SURFACE,
					section = OFFER_SURFACE,
					entrypoint = currentState.OfferKey,
					productName = action.Target,
					productId = productId,
					purchaseKind = "product",
					paymentType = "robux",
				})
				local success, err = pcall(function()
					MarketplaceService:PromptProductPurchase(player, productId)
				end)
				if not success then
					warn("[ContextualOfferController] Failed to prompt product:", action.Target, err)
				end
			end
		elseif action.Type == "GamePass" then
			local passId = ProductConfigurations.GamePasses[action.Target]
			if type(passId) == "number" and passId > 0 then
				reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
					surface = OFFER_SURFACE,
					section = OFFER_SURFACE,
					entrypoint = currentState.OfferKey,
					productName = action.Target,
					passId = passId,
					purchaseKind = "gamepass",
					paymentType = "robux",
				})
				local success, err = pcall(function()
					MarketplaceService:PromptGamePassPurchase(player, passId)
				end)
				if not success then
					warn("[ContextualOfferController] Failed to prompt gamepass:", action.Target, err)
				end
			end
		end

		hideActiveOffer(true)
	end)
end

local function buildOfferButtonState(button: ImageButton, offerKey: string, definition: OfferDefinition): OfferButtonState
	local entries = {}
	appendTransparencyEntries(entries, button)
	for _, descendant in ipairs(button:GetDescendants()) do
		appendTransparencyEntries(entries, descendant)
	end

	local state: OfferButtonState = {
		Button = button,
		OfferKey = offerKey,
		Definition = definition,
		LayoutOrder = button.LayoutOrder,
		Scale = getOrCreateOfferScale(button),
		TransparencyEntries = entries,
		Bound = false,
	}

	setTransparencyAlpha(state, 1)
	state.Scale.Scale = 1
	state.Button.Visible = false
	bindOfferButton(state)

	return state
end

local function refreshOfferButtons()
	offerContainer = findOfferContainer()
	if not offerContainer then
		orderedOfferButtons = {}
		if not warnedMissingContainer then
			warn("[ContextualOfferController] Offer container in HUD was not found.")
			warnedMissingContainer = true
		end
		return
	end

	warnedMissingContainer = false

	local refreshedButtons = {}
	for _, descendant in ipairs(offerContainer:GetDescendants()) do
		if descendant:IsA("ImageButton") then
			local offerKey, definition = resolveOfferForButton(descendant)
			if offerKey and definition and canShowOffer(definition) then
				local state = offerButtonsByInstance[descendant]
				if not state then
					state = buildOfferButtonState(descendant, offerKey, definition)
					offerButtonsByInstance[descendant] = state
				else
					state.OfferKey = offerKey
					state.Definition = definition
					state.LayoutOrder = descendant.LayoutOrder
				end

				bindOfferButton(state)
				setTransparencyAlpha(state, 1)
				state.Scale.Scale = 1
				state.Button.Visible = false
				updateButtonCost(state.Button, definition)
				table.insert(refreshedButtons, state)
			end
		end
	end

	table.sort(refreshedButtons, function(a, b)
		if a.LayoutOrder == b.LayoutOrder then
			return a.Button.Name < b.Button.Name
		end
		return a.LayoutOrder < b.LayoutOrder
	end)

	for instance in pairs(offerButtonsByInstance) do
		if instance.Parent == nil then
			offerButtonsByInstance[instance] = nil
		end
	end

	orderedOfferButtons = refreshedButtons
	if currentIndex > #orderedOfferButtons then
		currentIndex = 0
	end
end

local function hideOfferButton(state: OfferButtonState, immediate: boolean?)
	cancelActiveTweens()
	activeDisplayToken += 1

	if immediate then
		setTransparencyAlpha(state, 1)
		state.Scale.Scale = 1
		state.Button.Visible = false
		if activeButtonState == state then
			activeButtonState = nil
		end
		return
	end

	setTransparencyAlpha(state, 1)
	state.Scale.Scale = 1
	state.Button.Visible = false
	if activeButtonState == state then
		activeButtonState = nil
	end
end

hideActiveOffer = function(immediate: boolean?)
	if not activeButtonState then
		return
	end

	hideOfferButton(activeButtonState, immediate)
end

local function showOfferButton(state: OfferButtonState)
	hideActiveOffer(true)
	cancelActiveTweens()

	activeDisplayToken += 1
	activeButtonState = state
	nextRotationAt = os.clock() + ROTATION_INTERVAL

	state.Button.Visible = true
	state.Scale.Scale = INITIAL_SCALE
	setTransparencyAlpha(state, 1)

	local tweens = createTransparencyTweens(state, SHOW_TWEEN_INFO, 0)
	table.insert(tweens, TweenService:Create(state.Scale, SHOW_TWEEN_INFO, {Scale = 1}))
	activeTweens = tweens
	for _, tween in ipairs(tweens) do
		tween:Play()
	end
end

local function findButtonIndexByOfferKey(offerKey: string): number?
	for index, state in ipairs(orderedOfferButtons) do
		if state.OfferKey == offerKey then
			return index
		end
	end

	return nil
end

local function showNextOffer(preferredOfferKey: string?)
	refreshOfferButtons()
	if #orderedOfferButtons == 0 then
		hideActiveOffer(true)
		return
	end

	local nextIndex: number?
	if preferredOfferKey then
		nextIndex = findButtonIndexByOfferKey(preferredOfferKey)
		if nextIndex == nil then
			return
		end
	end

	if nextIndex == nil then
		currentIndex = (currentIndex % #orderedOfferButtons) + 1
		nextIndex = currentIndex
	else
		currentIndex = nextIndex
	end

	local state = orderedOfferButtons[nextIndex]
	if not state then
		return
	end

	if activeButtonState == state and state.Button.Visible then
		nextRotationAt = os.clock() + ROTATION_INTERVAL
		return
	end

	showOfferButton(state)
end

hud.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ImageButton") or descendant:IsA("Frame") then
		task.defer(refreshOfferButtons)
	end
end)

hud.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("ImageButton") or descendant:IsA("Frame") then
		task.defer(refreshOfferButtons)
	end
end)

FrameManager.Changed:Connect(function(anyFrameOpen)
	if anyFrameOpen then
		hideActiveOffer(true)
		return
	end

	if queuedOfferKey then
		local offerKey = queuedOfferKey
		queuedOfferKey = nil
		showNextOffer(offerKey)
		return
	end

	showNextOffer()
end)

showContextualOfferEvent.OnClientEvent:Connect(function(offerKey: string, payload: {[string]: any}?)
	local resolvedOfferKey = getResolvedOfferKey(offerKey, payload)
	local definition = ContextualOfferConfiguration.GetDefinition(resolvedOfferKey)
	if not definition or not canShowOffer(definition) then
		return
	end

	if FrameManager.isAnyFrameOpen() then
		queuedOfferKey = resolvedOfferKey
		return
	end

	showNextOffer(resolvedOfferKey)
end)

task.spawn(function()
	while true do
		if FrameManager.isAnyFrameOpen() then
			task.wait(0.25)
		else
			refreshOfferButtons()
			if #orderedOfferButtons == 0 then
				hideActiveOffer(true)
				task.wait(1)
			else
				local shouldRotate = activeButtonState == nil
					or activeButtonState.Button.Visible ~= true
					or os.clock() >= nextRotationAt

				if shouldRotate then
					showNextOffer()
				end

				task.wait(0.25)
			end
		end
	end
end)
