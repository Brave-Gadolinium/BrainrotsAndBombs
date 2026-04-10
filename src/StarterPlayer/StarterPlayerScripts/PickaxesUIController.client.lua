--!strict
-- LOCATION: StarterPlayerScripts/PickaxesUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PickaxesConfigurations = require(Modules:WaitForChild("PickaxesConfigurations"))
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))
local PickaxesFolder = ReplicatedStorage:WaitForChild("Pickaxes")

local Events = ReplicatedStorage:WaitForChild("Events")
local requestEvent = Events:WaitForChild("RequestPickaxeAction") :: RemoteEvent
local getDataFunction = Events:WaitForChild("GetPickaxeData") :: RemoteFunction
local reportAnalyticsIntent = Events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local selectedPickaxeId: string? = nil
local currentOwnedPickaxes: {[string]: boolean} = {["Bomb 1"] = true}
local currentEquippedPickaxe = "Bomb 1"
local currentNextAvailableId: string? = nil
local robuxPriceCache: {[number]: string} = {}

local HOVER_SCALE = 1.05
local CLICK_SCALE = 0.95
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DISABLED_BUTTON_BACKGROUND_TRANSPARENCY_OFFSET = 0.14
local DISABLED_BUTTON_TEXT_TRANSPARENCY_OFFSET = 0.18
local ACTION_BUTTON_BUY = Color3.fromRGB(34, 255, 0)
local ACTION_BUTTON_EQUIP = Color3.fromRGB(255, 214, 64)
local ACTION_BUTTON_LOCKED = Color3.fromRGB(120, 120, 120)
local ACTION_BUTTON_TEXT = Color3.fromRGB(255, 255, 255)

type TextVisualSnapshot = {
	TextColor3: Color3,
	TextTransparency: number,
}

type ButtonVisualSnapshot = {
	AutoButtonColor: boolean,
	BackgroundColor3: Color3,
	BackgroundTransparency: number,
	ImageColor3: Color3?,
	TextElements: {[GuiObject]: TextVisualSnapshot},
}

local buttonVisualSnapshots: {[GuiButton]: ButtonVisualSnapshot} = {}

local function setupButtonAnimation(button: GuiButton)
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "AnimationScale"
		uiScale.Parent = button
	end

	button.MouseEnter:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, {Scale = 1}):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, {Scale = CLICK_SCALE}):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play()
	end)
end

local function getBombTier(pickaxeId: string): number
	return tonumber(pickaxeId:match("(%d+)")) or 0
end

local function formatStatValue(value: number): string
	if math.abs(value - math.round(value)) < 0.001 then
		return tostring(math.round(value))
	end

	return string.format("%.1f", value)
end

local function getButtonVisualSnapshot(button: GuiButton): ButtonVisualSnapshot
	local existingSnapshot = buttonVisualSnapshots[button]
	if existingSnapshot then
		return existingSnapshot
	end

	local textElements: {[GuiObject]: TextVisualSnapshot} = {}
	local function registerTextElement(element: GuiObject)
		if element:IsA("TextLabel") or element:IsA("TextButton") then
			textElements[element] = {
				TextColor3 = element.TextColor3,
				TextTransparency = element.TextTransparency,
			}
		end
	end

	registerTextElement(button)
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			registerTextElement(descendant)
		end
	end

	local snapshot = {
		AutoButtonColor = button.AutoButtonColor,
		BackgroundColor3 = button.BackgroundColor3,
		BackgroundTransparency = button.BackgroundTransparency,
		ImageColor3 = if button:IsA("ImageButton") then button.ImageColor3 else nil,
		TextElements = textElements,
	}
	buttonVisualSnapshots[button] = snapshot

	button.AncestryChanged:Connect(function(_, parent)
		if not parent then
			buttonVisualSnapshots[button] = nil
		end
	end)

	return snapshot
end

local function restoreButtonVisuals(button: GuiButton)
	local snapshot = getButtonVisualSnapshot(button)
	button.AutoButtonColor = snapshot.AutoButtonColor
	button.BackgroundColor3 = snapshot.BackgroundColor3
	button.BackgroundTransparency = snapshot.BackgroundTransparency

	if button:IsA("ImageButton") and snapshot.ImageColor3 then
		button.ImageColor3 = snapshot.ImageColor3
	end

	for textElement, textSnapshot in pairs(snapshot.TextElements) do
		if textElement.Parent and (textElement:IsA("TextLabel") or textElement:IsA("TextButton")) then
			textElement.TextColor3 = textSnapshot.TextColor3
			textElement.TextTransparency = textSnapshot.TextTransparency
		end
	end
end

local function applyButtonTheme(button: GuiButton?, backgroundColor: Color3, textColor: Color3?)
	if not button then
		return
	end

	local resolvedTextColor = textColor or ACTION_BUTTON_TEXT
	button.BackgroundColor3 = backgroundColor

	if button:IsA("ImageButton") then
		button.ImageColor3 = backgroundColor
	end

	local snapshot = getButtonVisualSnapshot(button)
	for textElement in pairs(snapshot.TextElements) do
		if textElement.Parent and (textElement:IsA("TextLabel") or textElement:IsA("TextButton")) then
			textElement.TextColor3 = resolvedTextColor
		end
	end
end

local function setButtonEnabled(button: GuiButton?, enabled: boolean)
	if not button then
		return
	end

	local snapshot = getButtonVisualSnapshot(button)
	restoreButtonVisuals(button)

	button.Active = enabled
	button.AutoButtonColor = if enabled then snapshot.AutoButtonColor else false
	button.Selectable = enabled

	if not enabled then
		button.BackgroundTransparency = math.clamp(snapshot.BackgroundTransparency + DISABLED_BUTTON_BACKGROUND_TRANSPARENCY_OFFSET, 0, 1)

		for textElement, textSnapshot in pairs(snapshot.TextElements) do
			if textElement.Parent and (textElement:IsA("TextLabel") or textElement:IsA("TextButton")) then
				textElement.TextTransparency = math.clamp(textSnapshot.TextTransparency + DISABLED_BUTTON_TEXT_TRANSPARENCY_OFFSET, 0, 1)
			end
		end
	end
end

local function findTextLabel(parent: Instance?): TextLabel?
	if not parent then
		return nil
	end

	if parent:IsA("TextLabel") then
		return parent
	end

	local priceLabel = parent:FindFirstChild("Price", true)
	if priceLabel and priceLabel:IsA("TextLabel") then
		return priceLabel
	end

	local textLabel = parent:FindFirstChild("Text", true)
	if textLabel and textLabel:IsA("TextLabel") then
		return textLabel
	end

	if parent:IsA("TextButton") then
		return parent
	end

	return parent:FindFirstChildWhichIsA("TextLabel", true)
end

local function setButtonText(button: GuiButton?, text: string)
	if not button then
		return
	end

	local label = findTextLabel(button)
	if label then
		label.Text = text
	elseif button:IsA("TextButton") then
		button.Text = text
	end
end

local function isPickaxesFrameVisible(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	local mainGui = playerGui and playerGui:FindFirstChild("GUI")
	local frames = mainGui and mainGui:FindFirstChild("Frames")
	local pickaxesFrame = frames and frames:FindFirstChild("Pickaxes")
	return pickaxesFrame ~= nil and pickaxesFrame:IsA("GuiObject") and pickaxesFrame.Visible
end

local function getRobuxPriceText(productId: number?): string?
	if type(productId) ~= "number" or productId <= 0 then
		return nil
	end

	local cachedPrice = robuxPriceCache[productId]
	if cachedPrice then
		return cachedPrice
	end

	if not isPickaxesFrameVisible() then
		return nil
	end

	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)

	if success and info and info.PriceInRobux then
		local priceText = " " .. tostring(info.PriceInRobux)
		robuxPriceCache[productId] = priceText
		return priceText
	end

	return "N/A"
end

local function reportStoreOpened(surface: string)
	reportAnalyticsIntent:FireServer("StoreOpened", {
		surface = surface,
		section = "bombs",
		entrypoint = "frame_open",
	})
end

local function reportStorePromptFailed(productName: string, productId: number?, reason: string)
	reportAnalyticsIntent:FireServer("StorePromptFailed", {
		surface = "pickaxes",
		section = "bombs",
		entrypoint = "robux_button",
		productName = productName,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
		reason = reason,
	})
end

local function getPickaxesFrame(): Frame
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("GUI")
	local frames = mainGui:WaitForChild("Frames")
	return frames:WaitForChild("Pickaxes") :: Frame
end

local function getScrollingFrame(pickaxesFrame: Frame): ScrollingFrame
	local scrollingFrame = pickaxesFrame:FindFirstChild("ScrollingFrame") or pickaxesFrame:FindFirstChild("Scrolling")
	return scrollingFrame :: ScrollingFrame
end

local function getShowcaseFrame(pickaxesFrame: Frame, scrollingFrame: GuiObject): Frame
	local showcaseFrame = scrollingFrame:FindFirstChild("Showcase") or pickaxesFrame:FindFirstChild("Showcase")
	return showcaseFrame :: Frame
end

local function getTemplate(scrollingFrame: GuiObject): GuiObject
	return scrollingFrame:WaitForChild("PickaxeTemplate") :: GuiObject
end

local function parsePickaxeData(rawData): ({[string]: boolean}, string, string?)
	if type(rawData) == "table" and rawData.OwnedPickaxes then
		local ownedPickaxes = rawData.OwnedPickaxes
		local equippedPickaxe = if type(rawData.EquippedPickaxe) == "string" then rawData.EquippedPickaxe else "Bomb 1"
		local nextPickaxeToBuy = if type(rawData.NextPickaxeToBuy) == "string" then rawData.NextPickaxeToBuy else nil
		return ownedPickaxes, equippedPickaxe, nextPickaxeToBuy
	end

	if type(rawData) == "table" then
		return rawData, "Bomb 1", nil
	end

	return {["Bomb 1"] = true}, "Bomb 1", nil
end

local function getNextAvailableId(ownedPickaxes: {[string]: boolean}): string?
	local sortedPickaxes = {}
	for id, data in pairs(PickaxesConfigurations.Pickaxes) do
		if PickaxesFolder:FindFirstChild(id) then
			table.insert(sortedPickaxes, {Id = id, Data = data})
		end
	end

	table.sort(sortedPickaxes, function(a, b)
		if a.Data.Price == b.Data.Price then
			return a.Id < b.Id
		end
		return a.Data.Price < b.Data.Price
	end)

	for _, pickaxe in ipairs(sortedPickaxes) do
		if not ownedPickaxes[pickaxe.Id] then
			return pickaxe.Id
		end
	end

	return nil
end

local function getHighestOwnedPickaxeId(sortedPickaxes: {{Id: string, Data: any}}): string?
	for index = #sortedPickaxes, 1, -1 do
		local pickaxeId = sortedPickaxes[index].Id
		if currentOwnedPickaxes[pickaxeId] == true then
			return pickaxeId
		end
	end

	return nil
end

local function shouldPreferNextAvailablePickaxe(): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep >= 7 and onboardingStep <= 8
end

local function resolveAutoSelectedPickaxeId(sortedPickaxes: {{Id: string, Data: any}}, preferHighestOwned: boolean?): string
	local highestOwnedPickaxeId = getHighestOwnedPickaxeId(sortedPickaxes)

	if shouldPreferNextAvailablePickaxe() and currentNextAvailableId and PickaxesConfigurations.Pickaxes[currentNextAvailableId] then
		return currentNextAvailableId
	end

	if preferHighestOwned and highestOwnedPickaxeId and PickaxesConfigurations.Pickaxes[highestOwnedPickaxeId] then
		return highestOwnedPickaxeId
	end

	if selectedPickaxeId and PickaxesConfigurations.Pickaxes[selectedPickaxeId] then
		return selectedPickaxeId
	end

	if PickaxesConfigurations.Pickaxes[currentEquippedPickaxe] then
		return currentEquippedPickaxe
	end

	return highestOwnedPickaxeId or currentNextAvailableId or sortedPickaxes[#sortedPickaxes].Id
end

local function scrollToPickaxeEntry(scrollingFrame: ScrollingFrame, entry: GuiObject)
	local function applyScroll()
		if not scrollingFrame.Parent or not entry.Parent then
			return
		end

		local windowHeight = scrollingFrame.AbsoluteWindowSize.Y
		if windowHeight <= 0 then
			windowHeight = scrollingFrame.AbsoluteSize.Y
		end

		local entryTop = entry.AbsolutePosition.Y - scrollingFrame.AbsolutePosition.Y + scrollingFrame.CanvasPosition.Y
		local maxCanvasY = math.max(0, scrollingFrame.AbsoluteCanvasSize.Y - windowHeight)
		local targetY = math.clamp(math.floor(entryTop - 12 + 0.5), 0, maxCanvasY)
		scrollingFrame.CanvasPosition = Vector2.new(scrollingFrame.CanvasPosition.X, targetY)
	end

	task.defer(function()
		applyScroll()
		task.defer(applyScroll)
	end)
end

local function bindTemplateSelection(template: GuiObject, onSelected: () -> ())
	if template:GetAttribute("SelectionConnectionSet") then
		return
	end

	template:SetAttribute("SelectionConnectionSet", true)

	if template:IsA("GuiButton") then
		setupButtonAnimation(template)
		template.MouseButton1Click:Connect(onSelected)
		return
	end

	template.Active = true
	template.InputBegan:Connect(function(inputObject)
		local inputType = inputObject.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			onSelected()
		end
	end)
end

local function updateShowcase(pickaxesFrame: Frame, pickaxeId: string, shouldReport: boolean?)
	selectedPickaxeId = pickaxeId

	local scrollingFrame = getScrollingFrame(pickaxesFrame)
	local showcaseFrame = getShowcaseFrame(pickaxesFrame, scrollingFrame)
	local config = PickaxesConfigurations.Pickaxes[pickaxeId]
	if not config then
		return
	end

	local isOwned = currentOwnedPickaxes[pickaxeId] == true
	local isEquipped = currentEquippedPickaxe == pickaxeId
	local isLockedForSoftPurchase = not isOwned and currentNextAvailableId ~= nil and pickaxeId ~= currentNextAvailableId
	local robuxProductId = config.RobuxProductId

	local titleLabel = showcaseFrame:FindFirstChild("Title") :: TextLabel?
	local imageLabel = showcaseFrame:FindFirstChild("Image") :: ImageLabel?
	local infoFrame = showcaseFrame:FindFirstChild("Info")
	local leftFrame = infoFrame and infoFrame:FindFirstChild("Left")
	local rightFrame = infoFrame and infoFrame:FindFirstChild("Right")
	local leftPrimary = leftFrame and leftFrame:FindFirstChild("Damage") :: TextLabel?
	local leftSecondary = leftFrame and leftFrame:FindFirstChild("Speed") :: TextLabel?
	local rightPrimary = rightFrame and rightFrame:FindFirstChild("Damage") :: TextLabel?
	local rightSecondary = rightFrame and rightFrame:FindFirstChild("Speed") :: TextLabel?

	local buttonsFrame = showcaseFrame:FindFirstChild("Buttons")
	local softBuyButton = buttonsFrame and buttonsFrame:FindFirstChild("Buy") :: GuiButton?
	local robuxButton = buttonsFrame and buttonsFrame:FindFirstChild("Robux") :: GuiButton?

	if titleLabel then
		titleLabel.Text = string.format("Bomb %d - %s", getBombTier(pickaxeId), config.DisplayName)
	end

	if imageLabel then
		imageLabel.Image = config.ImageId
		imageLabel.ImageColor3 = if isOwned or not isLockedForSoftPurchase then Color3.new(1, 1, 1) else Color3.new(0.2, 0.2, 0.2)
	end

	if leftPrimary then
		leftPrimary.Text = "Radius: " .. formatStatValue(config.ExplosionRadius)
	end
	if leftSecondary then
		leftSecondary.Text = "KB: " .. formatStatValue(config.KnockbackForce)
	end
	if rightPrimary then
		rightPrimary.Text = "Depth: " .. formatStatValue(config.MaxDepthLevel)
	end
	if rightSecondary then
		rightSecondary.Text = "CD: " .. formatStatValue(config.Cooldown) .. "s"
	end

	if softBuyButton then
		if isOwned then
			setButtonText(softBuyButton, if isEquipped then "Equipped" else "Equip")
			setButtonEnabled(softBuyButton, not isEquipped)
			applyButtonTheme(softBuyButton, ACTION_BUTTON_EQUIP)
		elseif isLockedForSoftPurchase then
			setButtonText(softBuyButton, "Locked")
			setButtonEnabled(softBuyButton, false)
			applyButtonTheme(softBuyButton, ACTION_BUTTON_LOCKED)
		else
			setButtonText(softBuyButton, "Buy")
			setButtonEnabled(softBuyButton, true)
			applyButtonTheme(softBuyButton, ACTION_BUTTON_BUY)
		end
	end

	if robuxButton then
		if isOwned then
			setButtonText(robuxButton, if isEquipped then "EQUIPPED" else "OWNED")
			setButtonEnabled(robuxButton, false)
		else
			local robuxPriceText = getRobuxPriceText(robuxProductId)
			if robuxPriceText then
				setButtonText(robuxButton, robuxPriceText)
				setButtonEnabled(robuxButton, true)
			else
				setButtonText(robuxButton, "N/A")
				setButtonEnabled(robuxButton, false)
			end
		end
	end

	if shouldReport ~= false then
		reportAnalyticsIntent:FireServer("BombSelected", {
			pickaxeName = pickaxeId,
		})
	end
end

local function clearGeneratedEntries(scrollingFrame: Frame, template: GuiObject, showcaseFrame: Frame)
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child ~= template and child ~= showcaseFrame and child:GetAttribute("GeneratedPickaxeEntry") == true then
			child:Destroy()
		end
	end
end

local function bindShowcaseButtons(pickaxesFrame: Frame)
	local scrollingFrame = getScrollingFrame(pickaxesFrame)
	local showcaseFrame = getShowcaseFrame(pickaxesFrame, scrollingFrame)
	local buttonsFrame = showcaseFrame:FindFirstChild("Buttons")
	if not buttonsFrame then
		return
	end

	local softBuyButton = buttonsFrame:FindFirstChild("Buy")
	if softBuyButton and softBuyButton:IsA("GuiButton") and not softBuyButton:GetAttribute("ConnectionSet") then
		softBuyButton:SetAttribute("ConnectionSet", true)
		setupButtonAnimation(softBuyButton)
		softBuyButton.MouseButton1Click:Connect(function()
			if not selectedPickaxeId then
				return
			end

			local isOwned = currentOwnedPickaxes[selectedPickaxeId] == true
			local isEquipped = currentEquippedPickaxe == selectedPickaxeId
			local isLockedForSoftPurchase = not isOwned and currentNextAvailableId ~= nil and selectedPickaxeId ~= currentNextAvailableId
			if isLockedForSoftPurchase or isEquipped then
				return
			end

			requestEvent:FireServer(selectedPickaxeId)
		end)
	end

	local robuxButton = buttonsFrame:FindFirstChild("Robux")
	if robuxButton and robuxButton:IsA("GuiButton") and not robuxButton:GetAttribute("ConnectionSet") then
		robuxButton:SetAttribute("ConnectionSet", true)
		setupButtonAnimation(robuxButton)
		robuxButton.MouseButton1Click:Connect(function()
			if not selectedPickaxeId then
				return
			end

			local config = PickaxesConfigurations.Pickaxes[selectedPickaxeId]
			if not config or currentOwnedPickaxes[selectedPickaxeId] == true then
				return
			end

			local robuxProductId = config.RobuxProductId
			if type(robuxProductId) == "number" and robuxProductId > 0 then
				reportAnalyticsIntent:FireServer("BombPurchaseRequested", {
					pickaxeName = selectedPickaxeId,
					paymentType = "robux",
					surface = "pickaxes",
				})
				local success, err = pcall(function()
					MarketplaceService:PromptProductPurchase(player, robuxProductId)
				end)
				if not success then
					warn("[PickaxesUIController] Failed to prompt robux purchase for bomb:", selectedPickaxeId, err)
					reportStorePromptFailed(selectedPickaxeId, robuxProductId, "prompt_failed")
				end
			else
				reportStorePromptFailed(selectedPickaxeId, robuxProductId, "missing_product_id")
				warn("[PickaxesUIController] Robux purchase is not configured for bomb:", selectedPickaxeId)
			end
		end)
	end
end

local function initializeUI(preferHighestOwned: boolean?)
	local pickaxesFrame = getPickaxesFrame()
	local scrollingFrame = getScrollingFrame(pickaxesFrame)
	local template = getTemplate(scrollingFrame)
	local showcaseFrame = getShowcaseFrame(pickaxesFrame, scrollingFrame)

	template.Visible = false

	local rawData = getDataFunction:InvokeServer()
	local ownedPickaxes, equippedPickaxe, nextPickaxeToBuy = parsePickaxeData(rawData)
	currentOwnedPickaxes = ownedPickaxes
	currentEquippedPickaxe = equippedPickaxe
	currentNextAvailableId = nextPickaxeToBuy or getNextAvailableId(ownedPickaxes)

	clearGeneratedEntries(scrollingFrame, template, showcaseFrame)

	local sortedPickaxes = {}
	for id, data in pairs(PickaxesConfigurations.Pickaxes) do
		local toolTemplate = PickaxesFolder:FindFirstChild(id)
		if toolTemplate then
			table.insert(sortedPickaxes, {Id = id, Data = data})
		end
	end

	table.sort(sortedPickaxes, function(a, b)
		if a.Data.Price == b.Data.Price then
			return a.Id < b.Id
		end
		return a.Data.Price < b.Data.Price
	end)

	if #sortedPickaxes == 0 then
		selectedPickaxeId = nil
		return
	end

	local pickaxeToAutoSelect = resolveAutoSelectedPickaxeId(sortedPickaxes, preferHighestOwned)
	local pickaxeToScrollTo = if preferHighestOwned then getHighestOwnedPickaxeId(sortedPickaxes) or pickaxeToAutoSelect else nil
	local scrollTargetEntry: GuiObject? = nil

	for index, pickaxe in ipairs(sortedPickaxes) do
		local newTemplate = template:Clone()
		newTemplate.Name = pickaxe.Id
		newTemplate:SetAttribute("GeneratedPickaxeEntry", true)
		newTemplate.Visible = true
		newTemplate.LayoutOrder = index
		newTemplate.Parent = scrollingFrame

		local isOwned = currentOwnedPickaxes[pickaxe.Id] == true
		local isEquipped = currentEquippedPickaxe == pickaxe.Id
		local isLockedForSoftPurchase = not isOwned and currentNextAvailableId ~= nil and pickaxe.Id ~= currentNextAvailableId

		local imageLabel = newTemplate:FindFirstChild("Image") :: ImageLabel?
		local lockedIcon = imageLabel:FindFirstChild("Locked") :: GuiObject?
		local checkmarkIcon = imageLabel:FindFirstChild("Checkmark") :: GuiObject?
		local levelLabel = imageLabel:FindFirstChild("Level")
		local nameCostFrame = newTemplate:FindFirstChild("NameCost")
		local nameLabel = nameCostFrame and nameCostFrame:FindFirstChild("Name") :: TextLabel?
		local costLabel = nameCostFrame and nameCostFrame:FindFirstChild("Cost") :: TextLabel?
		local equipButton = newTemplate:FindFirstChild("Buy") :: GuiButton?

		if imageLabel then
			imageLabel.Image = pickaxe.Data.ImageId
			imageLabel.ImageColor3 = if isOwned or not isLockedForSoftPurchase then Color3.new(1, 1, 1) else Color3.new(0.2, 0.2, 0.2)
		end

		-- if lockedIcon then
		-- 	lockedIcon.Visible = not isOwned
		-- end

		-- if checkmarkIcon then
		-- 	checkmarkIcon.Visible = isOwned
		-- end

		if levelLabel then
			levelLabel.Text = tostring(getBombTier(pickaxe.Id))
		end

		if nameLabel then
			nameLabel.Text = pickaxe.Data.DisplayName
		end

		if costLabel then
			costLabel.Text = if pickaxe.Data.Price > 0 then "$" .. NumberFormatter.Format(pickaxe.Data.Price) else "FREE"
		end

		if equipButton then
			setupButtonAnimation(equipButton)
			if isOwned then
				setButtonText(equipButton, if isEquipped then "Equipped" else "Equip")
				setButtonEnabled(equipButton, not isEquipped)
				applyButtonTheme(equipButton, ACTION_BUTTON_EQUIP)
			elseif isLockedForSoftPurchase then
				setButtonText(equipButton, "Locked")
				setButtonEnabled(equipButton, false)
				applyButtonTheme(equipButton, ACTION_BUTTON_LOCKED)
			else
				setButtonText(equipButton, "Buy")
				setButtonEnabled(equipButton, true)
				applyButtonTheme(equipButton, ACTION_BUTTON_BUY)
			end

			equipButton.MouseButton1Click:Connect(function()
				local currentlyOwned = currentOwnedPickaxes[pickaxe.Id] == true
				local currentlyEquipped = currentEquippedPickaxe == pickaxe.Id
				local currentlyLockedForSoftPurchase = not currentlyOwned
					and currentNextAvailableId ~= nil
					and pickaxe.Id ~= currentNextAvailableId

				if currentlyEquipped or currentlyLockedForSoftPurchase then
					return
				end

				requestEvent:FireServer(pickaxe.Id)
			end)
		end

		bindTemplateSelection(newTemplate, function()
			updateShowcase(pickaxesFrame, pickaxe.Id, true)
		end)

		if pickaxe.Id == pickaxeToAutoSelect then
			updateShowcase(pickaxesFrame, pickaxe.Id, false)
		end

		if pickaxe.Id == pickaxeToScrollTo then
			scrollTargetEntry = newTemplate
		end
	end

	bindShowcaseButtons(pickaxesFrame)

	if scrollTargetEntry then
		scrollToPickaxeEntry(scrollingFrame, scrollTargetEntry)
	end
end

task.spawn(function()
	local pickaxesFrame = getPickaxesFrame()
	pickaxesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if pickaxesFrame.Visible then
			initializeUI(true)
			reportAnalyticsIntent:FireServer("BombShopOpened")
			reportStoreOpened("pickaxes")
		end
	end)
end)

local updateUIEvent = Events:WaitForChild("UpdatePickaxeUI") :: RemoteEvent
updateUIEvent.OnClientEvent:Connect(function()
	initializeUI(false)
end)

initializeUI(false)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	initializeUI(false)
end)
