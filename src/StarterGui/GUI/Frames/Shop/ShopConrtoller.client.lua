local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local ProductConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProductConfigurations"))
local LuckyBlockConfiguration = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("LuckyBlockConfiguration"))
local ItemConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemConfigurations"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestAutoBombState = events:WaitForChild("RequestAutoBombState")
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent")

local ShopFrame = script.Parent
local MainFrame = ShopFrame:WaitForChild("MainFrame")
local Content = MainFrame:WaitForChild("Content")

-- local hoverSound = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("UIHoverSound")
-- local clickSound = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("UIClickSound")

local initialized = false
local infoCache = {}
local trackedPackFrames = {}
local trackedBoosterCards = {}
local refreshLoopStarted = false

local function findAnyChild(parent, childNames)
	if not parent then
		return nil
	end

	for _, childName in ipairs(childNames) do
		local child = parent:FindFirstChild(childName)
		if child then
			return child
		end
	end

	return nil
end

local function findNamedDescendant(parent, childNames, className)
	if not parent then
		return nil
	end

	for _, childName in ipairs(childNames) do
		local child = parent:FindFirstChild(childName, true)
		if child and (not className or child:IsA(className)) then
			return child
		end
	end

	return nil
end

local function findFirstDescendantOfClass(parent, className)
	if not parent then
		return nil
	end

	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant:IsA(className) then
			return descendant
		end
	end

	return nil
end

local function findGuiButton(parent, names)
	local namedButton = names and findNamedDescendant(parent, names, "GuiButton")
	if namedButton then
		return namedButton
	end

	return findFirstDescendantOfClass(parent, "GuiButton")
end

local function findTextLabel(parent, names)
	local namedLabel = names and findNamedDescendant(parent, names, "TextLabel")
	if namedLabel then
		return namedLabel
	end

	return findFirstDescendantOfClass(parent, "TextLabel")
end

local function findPrimaryImageLabel(target)
	if not target then
		return nil
	end

	if target:IsA("ImageLabel") then
		return target
	end

	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("ImageLabel") then
			local name = descendant.Name
			if name ~= "White" and name ~= "Pattern" and name ~= "Glow" and name ~= "Background" then
				return descendant
			end
		end
	end

	return findFirstDescendantOfClass(target, "ImageLabel")
end

local function setText(target, text)
	if not target then
		return
	end

	if target:IsA("TextLabel") or target:IsA("TextButton") then
		target.Text = text
	end
end

local function formatRobux(price)
	return "R$" .. tostring(price)
end

local function formatCash(amount)
	return "$" .. NumberFormatter.Format(amount)
end

local function toSnakeCase(value)
	if type(value) ~= "string" then
		return "unknown"
	end

	local normalized = value
		:gsub("([a-z0-9])([A-Z])", "%1_%2")
		:gsub("%s+", "_")
		:gsub("[^%w_]+", "_")
		:gsub("_+", "_")
		:gsub("^_+", "")
		:gsub("_+$", "")
		:lower()

	if normalized == "" then
		return "unknown"
	end

	return normalized
end

local function getCachedProductInfo(productId, infoType)
	local cacheKey = tostring(infoType) .. ":" .. tostring(productId)
	if infoCache[cacheKey] ~= nil then
		return infoCache[cacheKey]
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, infoType)
	end)

	if not ok then
		warn("[ShopController] Failed to load product info:", productId, infoType, info)
		infoCache[cacheKey] = false
		return nil
	end

	infoCache[cacheKey] = info
	return info
end

local function applyBasePriceText(label, text)
	if not label then
		return
	end

	label:SetAttribute("BasePriceText", text)
	setText(label, text)
end

local function restoreBasePriceText(label)
	if not label then
		return
	end

	local baseText = label:GetAttribute("BasePriceText")
	if type(baseText) == "string" and baseText ~= "" then
		setText(label, baseText)
	end
end

local function setRobuxPriceAsync(label, productId, infoType, onResolved)
	if not label or type(productId) ~= "number" or productId <= 0 then
		return
	end

	task.spawn(function()
		local info = getCachedProductInfo(productId, infoType)
		local price = info and info.PriceInRobux
		local text = if type(price) == "number" then formatRobux(price) else "R$?"
		applyBasePriceText(label, text)

		if onResolved then
			onResolved(if type(price) == "number" then price else nil)
		end
	end)
end

local function setupButtonEffects(button, scaleParent)
	if not button or button:GetAttribute("ShopEffectsBound") == true then
		return
	end

	button:SetAttribute("ShopEffectsBound", true)

	local target = button
	if scaleParent and button.Parent and button.Parent:IsA("GuiObject") then
		target = button.Parent
	end

	local defaultSize = target.Size
	local hoverSize = defaultSize + UDim2.fromScale(0.03, 0.03)
	local clickSize = defaultSize - UDim2.fromScale(0.02, 0.02)
	local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function tweenTo(size)
		TweenService:Create(target, tweenInfo, {Size = size}):Play()
	end

	button.MouseEnter:Connect(function()
		tweenTo(hoverSize)
		--hoverSound:Play()
	end)

	button.MouseLeave:Connect(function()
		tweenTo(defaultSize)
	end)

	button.MouseButton1Down:Connect(function()
		tweenTo(clickSize)
	end)

	button.MouseButton1Up:Connect(function()
		tweenTo(hoverSize)
		--clickSound:Play()
	end)
end

local function bindButtonOnce(button, callback)
	if not button or button:GetAttribute("ShopActionBound") == true then
		return
	end

	button:SetAttribute("ShopActionBound", true)
	button.Activated:Connect(callback)
end

local function reportStoreOpened(surface)
	reportAnalyticsIntent:FireServer("StoreOpened", {
		surface = surface,
		section = "shop",
		entrypoint = "frame_open",
	})
end

local function reportStorePromptFailed(section, entrypoint, productName, purchaseKind, purchaseId, reason)
	local payload = {
		surface = "shop_frame",
		section = section,
		entrypoint = entrypoint,
		productName = productName,
		purchaseKind = purchaseKind,
		paymentType = "robux",
		reason = reason,
	}

	if purchaseKind == "gamepass" then
		payload.passId = purchaseId
	else
		payload.productId = purchaseId
	end

	reportAnalyticsIntent:FireServer("StorePromptFailed", payload)
end

local function promptProductPurchaseWithAnalytics(section, entrypoint, productName, productId)
	if type(productId) ~= "number" or productId <= 0 then
		reportStorePromptFailed(section, entrypoint, productName, "product", productId, "missing_product_id")
		return
	end

	reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
		surface = "shop_frame",
		section = section,
		entrypoint = entrypoint,
		productName = productName,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
	})
	local success, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not success then
		warn("[ShopController] Failed to prompt product:", productName, err)
		reportStorePromptFailed(section, entrypoint, productName, "product", productId, "prompt_failed")
	end
end

local function promptGamePassPurchaseWithAnalytics(section, entrypoint, productName, passId)
	if type(passId) ~= "number" or passId <= 0 then
		reportStorePromptFailed(section, entrypoint, productName, "gamepass", passId, "missing_pass_id")
		return
	end

	reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
		surface = "shop_frame",
		section = section,
		entrypoint = entrypoint,
		productName = productName,
		passId = passId,
		purchaseKind = "gamepass",
		paymentType = "robux",
	})
	local success, err = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, passId)
	end)
	if not success then
		warn("[ShopController] Failed to prompt gamepass:", productName, err)
		reportStorePromptFailed(section, entrypoint, productName, "gamepass", passId, "prompt_failed")
	end
end

local function findPriceLabel(button)
	local priceLabel = findNamedDescendant(button, {"Price"}, "TextLabel")
	if priceLabel then
		return priceLabel
	end

	if button and button:IsA("TextButton") then
		return button
	end

	return findTextLabel(button)
end

local function setImage(target, imageId)
	local imageLabel = findPrimaryImageLabel(target)
	if imageLabel and type(imageId) == "string" then
		imageLabel.Image = imageId
	end
end

local function getItemDisplayName(itemName)
	local itemConfig = ItemConfigurations.GetItemData(itemName)
	if not itemConfig then
		return itemName
	end

	return itemConfig.DisplayName or itemName
end

local function configurePackVisuals(contentFrame, packName, title)
	local rewards = ProductConfigurations.PackRewards[packName]
	if not rewards then
		return
	end

	local firstReward = rewards.Items and rewards.Items[1]
	local secondReward = rewards.Items and rewards.Items[2]

	setText(findNamedDescendant(contentFrame, {"Name"}, "TextLabel"), title)

	local cashLabel = findNamedDescendant(contentFrame, {"Cash"}, "TextLabel")
	if cashLabel then
		cashLabel.Text = "+ " .. formatCash(rewards.Money) .. " CASH"
	end

	if firstReward then
		setText(findNamedDescendant(contentFrame, {"BrainrotName"}, "TextLabel"), getItemDisplayName(firstReward.Name))
		local firstConfig = ItemConfigurations.GetItemData(firstReward.Name)
		if firstConfig then
			setImage(findAnyChild(contentFrame, {"BrainrotImage"}), firstConfig.ImageId)
		end
	end

	if secondReward then
		setText(findNamedDescendant(contentFrame, {"LavaCoil", "SecondItemName"}, "TextLabel"), getItemDisplayName(secondReward.Name))
		local secondConfig = ItemConfigurations.GetItemData(secondReward.Name)
		if secondConfig then
			setImage(findAnyChild(contentFrame, {"LavaCoilImage", "SecondItemImage"}), secondConfig.ImageId)
		end
	end
end

local function refreshPackVisibility()
	for _, entry in ipairs(trackedPackFrames) do
		if entry.Frame then
			entry.Frame.Visible = player:GetAttribute(entry.Attribute) ~= true
		end
	end
end

local function setupPackSection(frameNames, packName, title)
	local frame = findAnyChild(Content, frameNames)
	if not frame then
		return
	end

	local contentFrame = findAnyChild(frame, {"Content"}) or frame
	local buttonsFrame = findAnyChild(contentFrame, {"Buttons"}) or contentFrame
	local buyButton = findGuiButton(buttonsFrame, {"Buy", "Buy39Robux", "Buy149Robux"})
	local passId = ProductConfigurations.GamePasses[packName]

	configurePackVisuals(contentFrame, packName, title)

	if buyButton and type(passId) == "number" and passId > 0 then
		setupButtonEffects(buyButton, false)
		setRobuxPriceAsync(findPriceLabel(buyButton), passId, Enum.InfoType.GamePass)
		bindButtonOnce(buyButton, function()
			promptGamePassPurchaseWithAnalytics("packs", toSnakeCase(packName), packName, passId)
		end)
	end

	table.insert(trackedPackFrames, {
		Frame = frame,
		Attribute = packName,
	})
end

local function setupMoneySection()
	local moneyFrame = findAnyChild(Content, {"Moneys"})
	local moneyContent = moneyFrame and findAnyChild(moneyFrame, {"Content"})
	if not moneyContent then
		return
	end

	local moneyPacks = {
		{FrameNames = {"Tiny Pack"}, ProductName = "CashProduct1"},
		{FrameNames = {"Mega Pack", "Mega  Pack"}, ProductName = "CashProduct2"},
		{FrameNames = {"Ultimate Pack"}, ProductName = "CashProduct3"},
	}

	for _, definition in ipairs(moneyPacks) do
		local frame = findAnyChild(moneyContent, definition.FrameNames)
		if frame then
			local button = findGuiButton(frame, {"Buy"})
			local productId = ProductConfigurations.Products[definition.ProductName]
			if button and type(productId) == "number" and productId > 0 then
				setupButtonEffects(button, true)
				setRobuxPriceAsync(findPriceLabel(button), productId, Enum.InfoType.Product)
				bindButtonOnce(button, function()
					promptProductPurchaseWithAnalytics("money", toSnakeCase(definition.ProductName), definition.ProductName, productId)
				end)
			end
		end
	end
end

local function setupHackerLuckyBlockSection()
	local hackerFrame = findAnyChild(Content, {"HackerLuckyBlock"})
	local hackerContent = hackerFrame and findAnyChild(hackerFrame, {"Content"})
	local hackerButtons = hackerContent and findAnyChild(hackerContent, {"Buttons"})
	if not hackerContent or not hackerButtons then
		return
	end

	local buttonDefinitions = {
		{Button = findAnyChild(hackerButtons, {"Buy_1"}), ProductName = "HackerLuckyBlock", AmountLabel = "LuckyBlocksAmount_1", AmountText = "1 Lucky Block"},
		{Button = findAnyChild(hackerButtons, {"Buy_2"}), ProductName = "HackerLuckyBlockX2", AmountLabel = "LuckyBlocksAmount_2", AmountText = "2 Lucky Blocks"},
		{Button = findAnyChild(hackerButtons, {"Buy_10"}), ProductName = "HackerLuckyBlockX10", AmountLabel = "LuckyBlocksAmount_3", AmountText = "10 Lucky Blocks"},
	}

	for _, definition in ipairs(buttonDefinitions) do
		local button = definition.Button
		local productId = ProductConfigurations.Products[definition.ProductName]
		if button and type(productId) == "number" and productId > 0 then
			setupButtonEffects(button, false)
			setRobuxPriceAsync(findPriceLabel(button), productId, Enum.InfoType.Product)
			bindButtonOnce(button, function()
				promptProductPurchaseWithAnalytics("hacker_lucky_block", toSnakeCase(definition.ProductName), definition.ProductName, productId)
			end)
		end

		local amountLabel = findNamedDescendant(hackerContent, {definition.AmountLabel}, "TextLabel")
		if amountLabel then
			amountLabel.Text = definition.AmountText
		end
	end

	local buyTwoButton = buttonDefinitions[2].Button
	local buyTenButton = buttonDefinitions[3].Button
	local baseProductId = ProductConfigurations.Products.HackerLuckyBlock
	if type(baseProductId) == "number" and baseProductId > 0 then
		local function updateDiscount(label, multiplier)
			if not label then
				return
			end

			local info = getCachedProductInfo(baseProductId, Enum.InfoType.Product)
			local price = info and info.PriceInRobux
			if type(price) == "number" then
				label.Text = formatRobux(price * multiplier)
			end
		end

		task.spawn(function()
			updateDiscount(findNamedDescendant(buyTwoButton, {"Discount"}, "TextLabel"), 2)
			updateDiscount(findNamedDescendant(buyTenButton, {"Discount"}, "TextLabel"), 10)
		end)
	end

	local blockConfig = LuckyBlockConfiguration.GetBlockConfig("luckyblock_hacker")
	if not blockConfig then
		return
	end

	setText(findNamedDescendant(hackerContent, {"Name"}, "TextLabel"), blockConfig.DisplayName)
	setImage(findAnyChild(hackerContent, {"Image"}), blockConfig.Image)

	local chancesFrame = findAnyChild(hackerContent, {"Chances"})
	if not chancesFrame then
		return
	end

	local totalWeight = 0
	for _, reward in ipairs(blockConfig.Rewards) do
		totalWeight += math.max(0, reward.Weight or 0)
	end
	if totalWeight <= 0 then
		return
	end

	for index, reward in ipairs(blockConfig.Rewards) do
		local chanceFrame = findAnyChild(chancesFrame, {"Chance" .. index})
		if chanceFrame then
			local chanceLabel = findNamedDescendant(chanceFrame, {"Chance"}, "TextLabel")
			local chancePercent = (math.max(0, reward.Weight or 0) / totalWeight) * 100
			if chanceLabel then
				chanceLabel.Text = string.format("%.1f%%", chancePercent)
			end

			local itemConfig = ItemConfigurations.GetItemData(reward.ItemName)
			if itemConfig then
				setImage(findAnyChild(chanceFrame, {"Icon"}), itemConfig.ImageId)
			end
		end
	end
end

local function formatRemainingTime(endsAt)
	local remaining = math.max(0, math.floor(endsAt - os.time()))
	local minutes = math.floor(remaining / 60)
	local seconds = remaining % 60
	return string.format("%02d:%02d", minutes, seconds)
end

local function registerTrackedCard(key, priceLabel, infoType, id)
	if not priceLabel then
		return
	end

	trackedBoosterCards[key] = {
		PriceLabel = priceLabel,
		InfoType = infoType,
		Id = id,
	}
end

local function refreshTrackedBoosterCards()
	local megaData = trackedBoosterCards.MegaExplosion
	if megaData and megaData.PriceLabel then
		local endsAt = math.max(0, tonumber(player:GetAttribute("MegaExplosionEndsAt")) or 0)
		if endsAt > os.time() then
			setText(megaData.PriceLabel, formatRemainingTime(endsAt))
		else
			restoreBasePriceText(megaData.PriceLabel)
		end
	end

	local shieldData = trackedBoosterCards.Shield
	if shieldData and shieldData.PriceLabel then
		local endsAt = math.max(0, tonumber(player:GetAttribute("ShieldEndsAt")) or 0)
		if endsAt > os.time() then
			setText(shieldData.PriceLabel, formatRemainingTime(endsAt))
		else
			restoreBasePriceText(shieldData.PriceLabel)
		end
	end

	local collectAllData = trackedBoosterCards.CollectAll
	if collectAllData and collectAllData.PriceLabel then
		if player:GetAttribute("HasCollectAll") == true then
			setText(collectAllData.PriceLabel, "Owned")
		else
			restoreBasePriceText(collectAllData.PriceLabel)
		end
	end

	local autoBombData = trackedBoosterCards.AutoBomb
	if autoBombData and autoBombData.PriceLabel then
		if player:GetAttribute("HasAutoBomb") == true then
			setText(autoBombData.PriceLabel, if player:GetAttribute("AutoBombEnabled") == true then "On" else "Off")
		else
			restoreBasePriceText(autoBombData.PriceLabel)
		end
	end

	local nukeData = trackedBoosterCards.NukeBooster
	if nukeData and nukeData.PriceLabel then
		restoreBasePriceText(nukeData.PriceLabel)
	end
end

local function setupBoosterCard(card, productName, infoType, id, onActivated)
	if not card then
		return
	end

	local button = findGuiButton(card, {"Buy"})
	if not button then
		return
	end

	setupButtonEffects(button, true)

	local priceLabel = findPriceLabel(button)
	if type(id) == "number" and id > 0 then
		setRobuxPriceAsync(priceLabel, id, infoType)
	end

	if onActivated then
		bindButtonOnce(button, onActivated)
	end

	registerTrackedCard(productName, priceLabel, infoType, id)
end

local function setupBoosterSections()
	local booster2 = findAnyChild(Content, {"Booster2"})
	local booster2Content = booster2 and findAnyChild(booster2, {"Content"})
	if booster2Content then
		local collectAllCard = findAnyChild(booster2Content, {"Auto Collect", "AutoCollect"})
		setupBoosterCard(
			collectAllCard,
			"CollectAll",
			Enum.InfoType.GamePass,
			ProductConfigurations.GamePasses.CollectAll,
			function()
				local passId = ProductConfigurations.GamePasses.CollectAll
				if type(passId) ~= "number" or passId <= 0 then
					return
				end

				if player:GetAttribute("HasCollectAll") == true then
					return
				end

				promptGamePassPurchaseWithAnalytics("boosters", "collect_all", "CollectAll", passId)
			end
		)

		local autoBombCard = findAnyChild(booster2Content, {"Auto Bomb", "AutoBomb"})
		setupBoosterCard(
			autoBombCard,
			"AutoBomb",
			Enum.InfoType.GamePass,
			ProductConfigurations.GamePasses.AutoBomb,
			function()
				if player:GetAttribute("HasAutoBomb") == true then
					local nextState = not (player:GetAttribute("AutoBombEnabled") == true)
					reportAnalyticsIntent:FireServer("AutoBombToggleRequested", {
						surface = "shop_frame",
						enabled = nextState,
					})
					requestAutoBombState:FireServer(nextState)
					return
				end

				local passId = ProductConfigurations.GamePasses.AutoBomb
				promptGamePassPurchaseWithAnalytics("boosters", "auto_bomb", "AutoBomb", passId)
			end
		)
	end

	local booster3 = findAnyChild(Content, {"Booster3"})
	local booster3Content = booster3 and findAnyChild(booster3, {"Content"})
	if booster3Content then
		local productCards = {
			{CardNames = {"Mega Explosion", "MegaExplosion"}, ProductName = "MegaExplosion"},
			{CardNames = {"Shield"}, ProductName = "Shield"},
			{CardNames = {"Nuke Booster", "NukeBooster"}, ProductName = "NukeBooster"},
		}

		for _, definition in ipairs(productCards) do
			local card = findAnyChild(booster3Content, definition.CardNames)
			local productId = ProductConfigurations.Products[definition.ProductName]
			setupBoosterCard(
				card,
				definition.ProductName,
				Enum.InfoType.Product,
				productId,
				function()
					if type(productId) == "number" and productId > 0 then
						promptProductPurchaseWithAnalytics("boosters", toSnakeCase(definition.ProductName), definition.ProductName, productId)
					end
				end
			)
		end
	end
end

local function startRefreshLoop()
	if refreshLoopStarted then
		return
	end

	refreshLoopStarted = true
	task.spawn(function()
		while ShopFrame.Parent do
			refreshPackVisibility()
			refreshTrackedBoosterCards()
			task.wait(1)
		end
	end)
end

local function init()
	if initialized then
		return
	end
	initialized = true

	setupPackSection({"StarterPack"}, "StarterPack", "Starter Pack")
	setupPackSection({"Pro Pack", "ProPack"}, "ProPack", "Pro Pack")
	setupHackerLuckyBlockSection()
	setupMoneySection()
	setupBoosterSections()

	ShopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if ShopFrame.Visible then
			reportStoreOpened("shop_frame")
		end
	end)
	if ShopFrame.Visible then
		reportStoreOpened("shop_frame")
	end

	refreshPackVisibility()
	refreshTrackedBoosterCards()

	player:GetAttributeChangedSignal("StarterPack"):Connect(refreshPackVisibility)
	player:GetAttributeChangedSignal("ProPack"):Connect(refreshPackVisibility)
	player:GetAttributeChangedSignal("HasCollectAll"):Connect(refreshTrackedBoosterCards)
	player:GetAttributeChangedSignal("HasAutoBomb"):Connect(refreshTrackedBoosterCards)
	player:GetAttributeChangedSignal("AutoBombEnabled"):Connect(refreshTrackedBoosterCards)
	player:GetAttributeChangedSignal("MegaExplosionEndsAt"):Connect(refreshTrackedBoosterCards)
	player:GetAttributeChangedSignal("ShieldEndsAt"):Connect(refreshTrackedBoosterCards)

	startRefreshLoop()
end

init()
