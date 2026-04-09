--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local RebirthRequirements = require(ReplicatedStorage.Modules.RebirthRequirements)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)
local FrameManager = require(ReplicatedStorage.Modules.FrameManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local RequestRebirth = Events:WaitForChild("RequestRebirth") :: RemoteEvent
local UpdateRebirthUI = Events:WaitForChild("UpdateRebirthUI") :: RemoteEvent
local ReportAnalyticsIntent = Events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")
local frames = gui:WaitForChild("Frames")
local rootUI = frames:WaitForChild("Rebirth") :: GuiObject
local mainFrame = rootUI:WaitForChild("MainFrame") :: GuiObject

local buttonContainer = mainFrame:WaitForChild("Button")
local rebirthButton = buttonContainer:WaitForChild("Soft") :: GuiButton
local skipButton = buttonContainer:WaitForChild("Robux") :: GuiButton
local statusLabel = rebirthButton:FindFirstChild("TextLabel", true)
local robuxPriceLabel = skipButton:FindFirstChild("Price", true)
local closeButton = rootUI:FindFirstChild("Close", true)

local contentFrame = mainFrame:WaitForChild("Content")
local youNeedContent = contentFrame:WaitForChild("YouNeed"):WaitForChild("Content")
local templateNeed = youNeedContent:WaitForChild("Template") :: Frame
local youRewardContent = contentFrame:WaitForChild("Rewards"):WaitForChild("Content")
local templateFloor = youRewardContent:FindFirstChild("Floor")
local templateMoney = youRewardContent:FindFirstChild("Money")
local templateSlots = youRewardContent:FindFirstChild("Slots")

local hudRebirthButton = hud:WaitForChild("Left"):WaitForChild("Buttons1"):WaitForChild("Rebirth")
local notificationDot = hudRebirthButton:FindFirstChild("Notification")

local FALLBACK_ITEM_ICON = "rbxassetid://114633371829343"
local CASH_ICON = "rbxassetid://102121104989061"
local BUTTON_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type ClientState = {
	targetLevel: number,
	requirement: any?,
	canRebirth: boolean,
	currentMoney: number,
	currentMult: number,
	nextMult: number,
	missingMoney: number,
	missingItems: {string},
}

local refreshQueued = false
local requestInFlight = false
local warnedMissingItems: {[string]: boolean} = {}
local plotConnections: {RBXScriptConnection} = {}
local characterConnections: {RBXScriptConnection} = {}
local rootConnections: {RBXScriptConnection} = {}
local watchedPlot: Instance? = nil
local skipProductId = ProductConfigurations.Products["SkipRebirth"]

local hoverSound = ReplicatedStorage:FindFirstChild("Assets")
	and ReplicatedStorage.Assets:FindFirstChild("Sounds")
	and ReplicatedStorage.Assets.Sounds:FindFirstChild("UIHoverSound")
local clickSound = ReplicatedStorage:FindFirstChild("Assets")
	and ReplicatedStorage.Assets:FindFirstChild("Sounds")
	and ReplicatedStorage.Assets.Sounds:FindFirstChild("UIClickSound")

local function disconnectAll(connections: {RBXScriptConnection})
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function setupButtonEffects(button: GuiButton)
	if button:GetAttribute("RebirthFxBound") == true then
		return
	end

	button:SetAttribute("RebirthFxBound", true)
	local uiScale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	uiScale.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(uiScale, BUTTON_TWEEN_INFO, {Scale = 1.03}):Play()
		if hoverSound and hoverSound:IsA("Sound") then
			hoverSound:Play()
		end
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(uiScale, BUTTON_TWEEN_INFO, {Scale = 1}):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(uiScale, BUTTON_TWEEN_INFO, {Scale = 0.97}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(uiScale, BUTTON_TWEEN_INFO, {Scale = 1.03}):Play()
		if clickSound and clickSound:IsA("Sound") then
			clickSound:Play()
		end
	end)
end

local function bindCloseButton(button: Instance?)
	if not button or not button:IsA("GuiButton") or button:GetAttribute("RebirthCloseBound") == true then
		return
	end

	button:SetAttribute("RebirthCloseBound", true)
	setupButtonEffects(button)
	button.MouseButton1Click:Connect(function()
		FrameManager.close("Rebirth")
	end)
end

local function getMoneyValue(): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyStat = leaderstats and leaderstats:FindFirstChild("Money")
	if moneyStat and moneyStat:IsA("NumberValue") then
		return moneyStat.Value
	end

	return 0
end

local function getRarityColor(rarity: string?): Color3
	if rarity == "Mythic" then
		rarity = "Mythical"
	end

	if rarity == "Brainrotgod" then
		return Color3.fromRGB(255, 216, 102)
	end

	local rarityConfig = rarity and (RarityConfigurations[rarity] :: any) or nil
	if rarityConfig and rarityConfig.TextColor then
		return rarityConfig.TextColor
	end

	return Color3.new(1, 1, 1)
end

local function getItemDisplayData(itemId: string): (string, string, string, Color3)
	local itemData = ItemConfigurations.GetItemData(itemId) :: any
	if not itemData then
		if not warnedMissingItems[itemId] then
			warn("[RebirthScript] Missing item configuration for rebirth requirement:", itemId)
			warnedMissingItems[itemId] = true
		end

		return itemId, FALLBACK_ITEM_ICON, "Brainrot", Color3.new(1, 1, 1)
	end

	local displayName = type(itemData.DisplayName) == "string" and itemData.DisplayName or itemId
	local imageId = type(itemData.ImageId) == "string" and itemData.ImageId or FALLBACK_ITEM_ICON
	local rarity = type(itemData.Rarity) == "string" and itemData.Rarity or "Brainrot"
	return displayName, imageId, rarity, getRarityColor(rarity)
end

local function setStatusText(text: string)
	if statusLabel and statusLabel:IsA("TextLabel") then
		statusLabel.Text = text
	elseif rebirthButton:IsA("TextButton") then
		rebirthButton.Text = text
	end
end

local function setNotificationVisible(visible: boolean)
	if notificationDot and notificationDot:IsA("GuiObject") then
		notificationDot.Visible = visible
	end
end

local function clearRequirements()
	for _, child in ipairs(youNeedContent:GetChildren()) do
		if child:IsA("Frame") and child ~= templateNeed then
			child:Destroy()
		end
	end
end

local function clearRewards()
	for _, child in ipairs(youRewardContent:GetChildren()) do
		if child:IsA("Frame") and child ~= templateFloor and child ~= templateMoney and child ~= templateSlots then
			child:Destroy()
		end
	end
end

local function getOwnedBrainrots(): {[string]: boolean}
	local owned: {[string]: boolean} = {}

	local function mark(itemName: any)
		if type(itemName) == "string" and itemName ~= "" then
			owned[itemName] = true
		end
	end

	local function scanContainer(container: Instance?)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsTemporary") ~= true then
				mark(child:GetAttribute("OriginalName"))
			end
		end
	end

	scanContainer(player:FindFirstChild("Backpack"))
	scanContainer(player.Character)

	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if plot then
		for _, descendant in ipairs(plot:GetDescendants()) do
			if descendant:IsA("Model") and descendant.Name == "VisualItem" and descendant:GetAttribute("IsLuckyBlock") ~= true then
				mark(descendant:GetAttribute("OriginalName"))
			end
		end
	end

	return owned
end

local function getClientState(): ClientState
	local rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
	local targetLevel = rebirths + 1
	local requirement = RebirthRequirements.Get(targetLevel)
	local currentMoney = getMoneyValue()
	local currentMult = 1 + (rebirths * 0.5)
	local nextMult = requirement and (1 + (targetLevel * 0.5)) or currentMult

	if not requirement then
		return {
			targetLevel = targetLevel,
			requirement = nil,
			canRebirth = false,
			currentMoney = currentMoney,
			currentMult = currentMult,
			nextMult = currentMult,
			missingMoney = 0,
			missingItems = {},
		}
	end

	local missingMoney = math.max((tonumber(requirement.soft_required) or 0) - currentMoney, 0)
	local ownedBrainrots = getOwnedBrainrots()
	local missingItems = {}

	for _, itemId in ipairs(requirement.item_required or {}) do
		if type(itemId) == "string" and itemId ~= "" and not ownedBrainrots[itemId] then
			table.insert(missingItems, itemId)
		end
	end

	return {
		targetLevel = targetLevel,
		requirement = requirement,
		canRebirth = missingMoney <= 0 and #missingItems == 0,
		currentMoney = currentMoney,
		currentMult = currentMult,
		nextMult = nextMult,
		missingMoney = missingMoney,
		missingItems = missingItems,
	}
end

local function createRequirementRow(layoutOrder: number, title: string, valueText: string, iconImage: string, accentColor: Color3, isMet: boolean)
	local row = templateNeed:Clone()
	row.Name = "Requirement" .. tostring(layoutOrder)
	row.Visible = true
	row.LayoutOrder = layoutOrder
	row.Parent = youNeedContent

	local icon = row:FindFirstChild("ImageLabel")
	local nameLabel = row:FindFirstChild("NameLabel")
	local needLabel = row:FindFirstChild("NeedLabel")

	if icon and icon:IsA("ImageLabel") then
		icon.Image = iconImage
	end

	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = title
		nameLabel.TextColor3 = accentColor
	end

	if needLabel and needLabel:IsA("TextLabel") then
		needLabel.Text = valueText
		needLabel.TextColor3 = isMet and Color3.fromRGB(0, 255, 120) or Color3.fromRGB(255, 70, 90)
	end
end

local function renderRequirements(state: ClientState)
	clearRequirements()

	if not state.requirement then
		createRequirementRow(1, "Max Rebirth", "No more rebirth levels configured", CASH_ICON, Color3.new(1, 1, 1), false)
		return
	end

	local requiredMoney = tonumber(state.requirement.soft_required) or 0
	createRequirementRow(
		1,
		"Cash",
		`{NumberFormatter.Format(state.currentMoney)} / {NumberFormatter.Format(requiredMoney)}`,
		CASH_ICON,
		Color3.new(1, 1, 1),
		state.currentMoney >= requiredMoney
	)

	local missingLookup: {[string]: boolean} = {}
	for _, itemId in ipairs(state.missingItems) do
		missingLookup[itemId] = true
	end

	for index, itemId in ipairs(state.requirement.item_required or {}) do
		local displayName, imageId, rarityName, rarityColor = getItemDisplayData(itemId)
		createRequirementRow(
			index + 1,
			rarityName,
			displayName,
			imageId,
			rarityColor,
			not missingLookup[itemId]
		)
	end
end

local function cloneRewardTemplate(template: Instance?, name: string, valueText: string, iconImage: string)
	if not template or not template:IsA("Frame") then
		return
	end

	local row = template:Clone()
	row.Name = "Reward_" .. name
	row.Visible = true
	row.Parent = youRewardContent

	local icon = row:FindFirstChild("ImageLabel")
	local nameLabel = row:FindFirstChild("NameLabel")
	local valueLabel = row:FindFirstChild("ValueLabel")

	if icon and icon:IsA("ImageLabel") then
		icon.Image = iconImage
	end

	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = name
	end

	if valueLabel and valueLabel:IsA("TextLabel") then
		valueLabel.Text = valueText
	end
end

local function renderRewards(state: ClientState)
	clearRewards()

	cloneRewardTemplate(templateFloor, "Current", "x" .. string.format("%.1f", state.currentMult), CASH_ICON)

	if state.requirement then
		cloneRewardTemplate(templateMoney, "After Rebirth", "x" .. string.format("%.1f", state.nextMult), CASH_ICON)
		cloneRewardTemplate(templateSlots, "Target Level", tostring(state.targetLevel), CASH_ICON)
	else
		cloneRewardTemplate(templateMoney, "After Rebirth", "MAX", CASH_ICON)
	end
end

local function updateButtons(state: ClientState)
	local canUse = state.canRebirth and not requestInFlight
	rebirthButton.Active = canUse

	if rebirthButton:IsA("TextButton") or rebirthButton:IsA("ImageButton") then
		rebirthButton.AutoButtonColor = canUse
	end

	setNotificationVisible(canUse)
end

local function refreshUI()
	local state = getClientState()

	renderRequirements(state)
	renderRewards(state)
	updateButtons(state)

	if not state.requirement then
		setStatusText("Max Rebirth")
		return
	end

	if requestInFlight then
		setStatusText("Processing...")
		return
	end

	if state.canRebirth then
		--setStatusText("Rebirth!")
	elseif state.missingMoney > 0 and #state.missingItems > 0 then
		--setStatusText("Need cash + brainrots")
	elseif state.missingMoney > 0 then
		--setStatusText("Need more cash")
	else
		--setStatusText("Need brainrots")
	end
end

local function queueRefresh()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		refreshUI()
	end)
end

local function bindVisualItem(instance: Instance)
	if not (instance:IsA("Model") and instance.Name == "VisualItem") then
		return
	end

	table.insert(plotConnections, instance:GetAttributeChangedSignal("OriginalName"):Connect(queueRefresh))
	table.insert(plotConnections, instance:GetAttributeChangedSignal("IsLuckyBlock"):Connect(queueRefresh))
end

local function bindPlot(plot: Instance?)
	if watchedPlot == plot then
		return
	end

	disconnectAll(plotConnections)
	watchedPlot = plot

	if not plot then
		queueRefresh()
		return
	end

	table.insert(plotConnections, plot.DescendantAdded:Connect(function(descendant)
		bindVisualItem(descendant)
		queueRefresh()
	end))

	table.insert(plotConnections, plot.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("Model") and descendant.Name == "VisualItem" then
			queueRefresh()
		end
	end))

	for _, descendant in ipairs(plot:GetDescendants()) do
		bindVisualItem(descendant)
	end

	queueRefresh()
end

local function bindCharacter(character: Model?)
	disconnectAll(characterConnections)

	if not character then
		queueRefresh()
		return
	end

	table.insert(characterConnections, character.ChildAdded:Connect(queueRefresh))
	table.insert(characterConnections, character.ChildRemoved:Connect(queueRefresh))
	queueRefresh()
end

local function setRobuxPrice()
	if not robuxPriceLabel or not robuxPriceLabel:IsA("TextLabel") or not skipProductId then
		return
	end

	if rootUI.Visible ~= true then
		return
	end

	local cachedPrice = robuxPriceLabel:GetAttribute("CachedRobuxPrice")
	if type(cachedPrice) == "string" and cachedPrice ~= "" then
		robuxPriceLabel.Text = cachedPrice
		return
	end

	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(skipProductId, Enum.InfoType.Product)
		end)

		if ok and info and info.PriceInRobux then
			local priceText = tostring(info.PriceInRobux)
			robuxPriceLabel:SetAttribute("CachedRobuxPrice", priceText)
			robuxPriceLabel.Text = priceText
		end
	end)
end

local function reportStoreOpened(surface: string)
	ReportAnalyticsIntent:FireServer("StoreOpened", {
		surface = surface,
		section = "rebirth",
		entrypoint = "frame_open",
	})
end

local function reportStorePromptFailed(reason: string)
	ReportAnalyticsIntent:FireServer("StorePromptFailed", {
		surface = "rebirth",
		section = "rebirth",
		entrypoint = "skip_button",
		productName = "SkipRebirth",
		productId = skipProductId,
		purchaseKind = "product",
		paymentType = "robux",
		reason = reason,
	})
end

local function bindObservers()
	local backpack = player:WaitForChild("Backpack")
	table.insert(rootConnections, backpack.ChildAdded:Connect(queueRefresh))
	table.insert(rootConnections, backpack.ChildRemoved:Connect(queueRefresh))

	table.insert(rootConnections, player.CharacterAdded:Connect(bindCharacter))
	table.insert(rootConnections, player.CharacterRemoving:Connect(function()
		bindCharacter(nil)
	end))

	if player.Character then
		bindCharacter(player.Character)
	end

	table.insert(rootConnections, player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		requestInFlight = false
		queueRefresh()
	end))

	table.insert(rootConnections, UpdateRebirthUI.OnClientEvent:Connect(function()
		requestInFlight = false
		queueRefresh()
	end))

	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 10)
		if not leaderstats then
			return
		end

		local moneyStat = leaderstats:WaitForChild("Money", 10)
		if moneyStat and moneyStat:IsA("NumberValue") then
			table.insert(rootConnections, moneyStat.Changed:Connect(queueRefresh))
		end

		queueRefresh()
	end)

	local plotName = "Plot_" .. player.Name
	local function refreshPlotBinding()
		bindPlot(Workspace:FindFirstChild(plotName))
	end

	table.insert(rootConnections, Workspace.ChildAdded:Connect(function(child)
		if child.Name == plotName then
			refreshPlotBinding()
		end
	end))

	table.insert(rootConnections, Workspace.ChildRemoved:Connect(function(child)
		if child == watchedPlot or child.Name == plotName then
			refreshPlotBinding()
		end
	end))

	refreshPlotBinding()
end

setupButtonEffects(rebirthButton)
setupButtonEffects(skipButton)
bindCloseButton(closeButton)
setRobuxPrice()
bindObservers()
queueRefresh()

rootUI.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "Close" then
		bindCloseButton(descendant)
	end
end)

rebirthButton.MouseButton1Click:Connect(function()
	local state = getClientState()
	if requestInFlight or not state.canRebirth then
		return
	end

	requestInFlight = true
	queueRefresh()
	RequestRebirth:FireServer()

	task.delay(1.5, function()
		requestInFlight = false
		queueRefresh()
	end)
end)

skipButton.MouseButton1Click:Connect(function()
	if not skipProductId then
		reportStorePromptFailed("missing_product_id")
		return
	end

	ReportAnalyticsIntent:FireServer("StoreOfferPrompted", {
		surface = "rebirth",
		section = "rebirth",
		entrypoint = "skip_button",
		productName = "SkipRebirth",
		productId = skipProductId,
		purchaseKind = "product",
		paymentType = "robux",
	})
	local success, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, skipProductId)
	end)
	if not success then
		warn("[RebirthScript] Failed to prompt SkipRebirth:", err)
		reportStorePromptFailed("prompt_failed")
	end
end)

rootUI:GetPropertyChangedSignal("Visible"):Connect(function()
	if rootUI.Visible then
		setRobuxPrice()
		ReportAnalyticsIntent:FireServer("RebirthUIOpened")
		reportStoreOpened("rebirth")
		queueRefresh()
	end
end)
