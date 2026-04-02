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

local function setButtonEnabled(button: GuiButton?, enabled: boolean, backgroundColor: Color3?)
	if not button then
		return
	end

	button.Active = enabled
	button.AutoButtonColor = enabled

	if button:IsA("GuiButton") then
		button.Selectable = enabled
	end

	if backgroundColor and button:IsA("GuiObject") then
		button.BackgroundColor3 = backgroundColor
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

local function getRobuxPriceText(productId: number?): string?
	if type(productId) ~= "number" or productId <= 0 then
		return nil
	end

	local cachedPrice = robuxPriceCache[productId]
	if cachedPrice then
		return cachedPrice
	end

	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)

	if success and info and info.PriceInRobux then
		local priceText = "R$" .. tostring(info.PriceInRobux)
		robuxPriceCache[productId] = priceText
		return priceText
	end

	return "N/A"
end

local function getPickaxesFrame(): Frame
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("GUI")
	local frames = mainGui:WaitForChild("Frames")
	return frames:WaitForChild("Pickaxes") :: Frame
end

local function getScrollingFrame(pickaxesFrame: Frame): Frame
	local scrollingFrame = pickaxesFrame:FindFirstChild("ScrollingFrame") or pickaxesFrame:FindFirstChild("Scrolling")
	return scrollingFrame :: Frame
end

local function getShowcaseFrame(pickaxesFrame: Frame, scrollingFrame: Frame): Frame
	local showcaseFrame = scrollingFrame:FindFirstChild("Showcase") or pickaxesFrame:FindFirstChild("Showcase")
	return showcaseFrame :: Frame
end

local function getTemplate(scrollingFrame: Frame): GuiObject
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

local function shouldPreferNextAvailablePickaxe(): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep >= 7 and onboardingStep <= 8
end

local function resolveAutoSelectedPickaxeId(sortedPickaxes: {{Id: string, Data: any}}): string
	if shouldPreferNextAvailablePickaxe() and currentNextAvailableId and PickaxesConfigurations.Pickaxes[currentNextAvailableId] then
		return currentNextAvailableId
	end

	if selectedPickaxeId and PickaxesConfigurations.Pickaxes[selectedPickaxeId] then
		return selectedPickaxeId
	end

	if PickaxesConfigurations.Pickaxes[currentEquippedPickaxe] then
		return currentEquippedPickaxe
	end

	return currentNextAvailableId or sortedPickaxes[#sortedPickaxes].Id
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
		leftPrimary.Text = "Explosion Radius: " .. formatStatValue(config.ExplosionRadius)
	end
	if leftSecondary then
		leftSecondary.Text = "Knockback: " .. formatStatValue(config.KnockbackForce)
	end
	if rightPrimary then
		rightPrimary.Text = "Max Depth: " .. formatStatValue(config.MaxDepthLevel)
	end
	if rightSecondary then
		rightSecondary.Text = "Cooldown: " .. formatStatValue(config.Cooldown) .. "s"
	end

	if softBuyButton then
		if isOwned then
			setButtonText(softBuyButton, if isEquipped then "EQUIPPED" else "OWNED")
			setButtonEnabled(softBuyButton, false, Color3.fromRGB(100, 100, 100))
		elseif isLockedForSoftPurchase then
			setButtonText(softBuyButton, "LOCKED")
			setButtonEnabled(softBuyButton, false, Color3.fromRGB(150, 50, 50))
		else
			if (config.Price or 0) > 0 then
				setButtonText(softBuyButton, "BUY $" .. NumberFormatter.Format(config.Price))
			else
				setButtonText(softBuyButton, "FREE")
			end
			setButtonEnabled(softBuyButton, true, Color3.fromRGB(50, 150, 50))
		end
	end

	if robuxButton then
		if isOwned then
			setButtonText(robuxButton, if isEquipped then "EQUIPPED" else "OWNED")
			setButtonEnabled(robuxButton, false, Color3.fromRGB(100, 100, 100))
		else
			local robuxPriceText = getRobuxPriceText(robuxProductId)
			if robuxPriceText then
				setButtonText(robuxButton, robuxPriceText)
				setButtonEnabled(robuxButton, true, Color3.fromRGB(35, 120, 170))
			else
				setButtonText(robuxButton, "N/A")
				setButtonEnabled(robuxButton, false, Color3.fromRGB(100, 100, 100))
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
			local isLockedForSoftPurchase = not isOwned and currentNextAvailableId ~= nil and selectedPickaxeId ~= currentNextAvailableId
			if isOwned or isLockedForSoftPurchase then
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
				MarketplaceService:PromptProductPurchase(player, robuxProductId)
			else
				warn("[PickaxesUIController] Robux purchase is not configured for bomb:", selectedPickaxeId)
			end
		end)
	end
end

local function initializeUI()
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

	local pickaxeToAutoSelect = resolveAutoSelectedPickaxeId(sortedPickaxes)

	for index, pickaxe in ipairs(sortedPickaxes) do
		local newTemplate = template:Clone()
		newTemplate.Name = pickaxe.Id
		newTemplate:SetAttribute("GeneratedPickaxeEntry", true)
		newTemplate.Visible = true
		newTemplate.LayoutOrder = index
		newTemplate.Parent = scrollingFrame

		local isOwned = currentOwnedPickaxes[pickaxe.Id] == true
		local isEquipped = currentEquippedPickaxe == pickaxe.Id

		local imageLabel = newTemplate:FindFirstChild("Image") :: ImageLabel?
		local lockedIcon = newTemplate:FindFirstChild("Locked") :: GuiObject?
		local checkmarkIcon = newTemplate:FindFirstChild("Checkmark") :: GuiObject?
		local levelLabel = newTemplate:FindFirstChild("Level") :: TextLabel?
		local nameCostFrame = newTemplate:FindFirstChild("NameCost")
		local nameLabel = nameCostFrame and nameCostFrame:FindFirstChild("Name") :: TextLabel?
		local costLabel = nameCostFrame and nameCostFrame:FindFirstChild("Cost") :: TextLabel?
		local equipButton = newTemplate:FindFirstChild("Buy") :: GuiButton?

		if imageLabel then
			imageLabel.Image = pickaxe.Data.ImageId
			imageLabel.ImageColor3 = if isOwned then Color3.new(1, 1, 1) else Color3.new(0.2, 0.2, 0.2)
		end

		if lockedIcon then
			lockedIcon.Visible = not isOwned
		end

		if checkmarkIcon then
			checkmarkIcon.Visible = isOwned
		end

		if levelLabel then
			levelLabel.Text = "Lvl " .. tostring(getBombTier(pickaxe.Id))
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
				setButtonText(equipButton, if isEquipped then "EQUIPPED" else "EQUIP")
				setButtonEnabled(equipButton, not isEquipped, if isEquipped then Color3.fromRGB(100, 100, 100) else Color3.fromRGB(50, 150, 50))
			else
				setButtonText(equipButton, "LOCKED")
				setButtonEnabled(equipButton, false, Color3.fromRGB(150, 50, 50))
			end

			equipButton.MouseButton1Click:Connect(function()
				if currentOwnedPickaxes[pickaxe.Id] ~= true or currentEquippedPickaxe == pickaxe.Id then
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
	end

	bindShowcaseButtons(pickaxesFrame)
end

task.spawn(function()
	local pickaxesFrame = getPickaxesFrame()
	pickaxesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if pickaxesFrame.Visible then
			initializeUI()
			reportAnalyticsIntent:FireServer("BombShopOpened")
		end
	end)
end)

local updateUIEvent = Events:WaitForChild("UpdatePickaxeUI") :: RemoteEvent
updateUIEvent.OnClientEvent:Connect(function()
	initializeUI()
end)

initializeUI()

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	initializeUI()
end)
