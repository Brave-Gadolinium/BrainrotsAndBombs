-- LOCATION: StarterPlayerScripts/UpgradesUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UpgradesConfig = require(Modules:WaitForChild("UpgradesConfigurations"))
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))
local TutorialConfiguration = require(Modules:WaitForChild("TutorialConfiguration"))

local player = Players.LocalPlayer
local Templates = ReplicatedStorage:WaitForChild("Templates")

local Events = ReplicatedStorage:WaitForChild("Events")
local requestUpgradeEvent = Events:WaitForChild("RequestUpgradeAction") :: RemoteEvent
local updateEvent = Events:WaitForChild("UpdateUpgradesUI") :: RemoteEvent
local reportAnalyticsIntent = Events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local HOVER_SCALE = 1.05
local CLICK_SCALE = 0.95
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAX_CARRY_CAPACITY = 4
local FRAME_OPEN_REFRESH_COOLDOWN = 0.75

local uiReferences = {}
local lastUpgradeUiData = {}
local robuxPriceCache = {}
local robuxPriceRequestsInFlight = {}
local uiInitialized = false
local lastVisibleOpenHandledAt = 0
local upgradeTemplateCache: Frame? = nil
local hasWarnedAboutMissingUpgradeTemplate = false

local function getUpgradeConfig(upgradeId: string): any?
	for _, upgrade in ipairs(UpgradesConfig.Upgrades) do
		if upgrade.Id == upgradeId then
			return upgrade
		end
	end

	return nil
end

local function isTutorialFreeUpgrade(upgradeId: string, upgradeData: any): boolean
	if upgradeId ~= TutorialConfiguration.TutorialCharacterUpgradeId then
		return false
	end

	if upgradeData and upgradeData.IsTutorialFree == true then
		return true
	end

	local upgradeConfig = getUpgradeConfig(upgradeId)
	local defaultValue = tonumber(upgradeConfig and upgradeConfig.DefaultValue) or 0
	local amount = tonumber(upgradeConfig and upgradeConfig.Amount) or 1
	local currentValue = tonumber(upgradeData and upgradeData.Current) or 0

	return (tonumber(player:GetAttribute("OnboardingStep")) or 0) == 10
		and currentValue < defaultValue + amount
end

local function setupButtonAnimation(button: GuiButton)
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "AnimationScale"
		uiScale.Parent = button
	end
	button.MouseEnter:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
	button.MouseLeave:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = 1}):Play() end)
	button.MouseButton1Down:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = CLICK_SCALE}):Play() end)
	button.MouseButton1Up:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
end

local function findTextLabel(parent: Instance): TextLabel?
	local label = parent:FindFirstChild("Text") or parent:FindFirstChild("Price")
	if label and label:IsA("TextLabel") then
		return label
	end
	return parent:FindFirstChildWhichIsA("TextLabel", true)
end

local function getUpgradesFrame(): Frame
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("GUI")
	local frames = mainGui:WaitForChild("Frames")
	return frames:WaitForChild("Upgrades") :: Frame
end

local function isUpgradesFrameVisible(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	local mainGui = playerGui and playerGui:FindFirstChild("GUI")
	local frames = mainGui and mainGui:FindFirstChild("Frames")
	local upgradesFrame = frames and frames:FindFirstChild("Upgrades")
	return upgradesFrame ~= nil and upgradesFrame:IsA("GuiObject") and upgradesFrame.Visible
end

local function getUpgradesScrollingFrame(): ScrollingFrame?
	local upgradesFrame = getUpgradesFrame()
	local directScrolling = upgradesFrame:FindFirstChild("Scrolling")
	if directScrolling and directScrolling:IsA("ScrollingFrame") then
		return directScrolling
	end

	local fallbackScrolling = upgradesFrame:FindFirstChildWhichIsA("ScrollingFrame", true)
	if fallbackScrolling then
		return fallbackScrolling
	end

	return nil
end

local function stripScripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
end

local function ensureScrollingLayout(scrollingFrame: ScrollingFrame)
	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 10)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = scrollingFrame
	end

	local padding = scrollingFrame:FindFirstChildOfClass("UIPadding")
	if not padding then
		padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.Parent = scrollingFrame
	end
end

local function createStatValueFrame(name: string, titleText: string, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromOffset(70, 42)
	frame.Position = position
	frame.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -8, 0, 14)
	title.Position = UDim2.fromOffset(4, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamSemibold
	title.Text = titleText
	title.TextColor3 = Color3.fromRGB(171, 180, 196)
	title.TextSize = 11
	title.Parent = frame

	local value = Instance.new("TextLabel")
	value.Name = "Text"
	value.Size = UDim2.new(1, -8, 0, 20)
	value.Position = UDim2.fromOffset(4, 18)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.Text = "0"
	value.TextColor3 = Color3.fromRGB(255, 255, 255)
	value.TextSize = 16
	value.Parent = frame

	return frame
end

local function createFallbackUpgradeTemplate(): Frame
	local card = Instance.new("Frame")
	card.Name = "UpgradeTemplate"
	card.Size = UDim2.new(1, -16, 0, 112)
	card.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	card.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(54, 62, 78)
	stroke.Thickness = 1
	stroke.Parent = card

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Text"
	titleLabel.Size = UDim2.new(1, -110, 0, 24)
	titleLabel.Position = UDim2.fromOffset(92, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "Upgrade"
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 20
	titleLabel.Parent = card

	local designFrame = Instance.new("Frame")
	designFrame.Name = "Design"
	designFrame.Size = UDim2.fromOffset(72, 72)
	designFrame.Position = UDim2.fromOffset(10, 20)
	designFrame.BackgroundColor3 = Color3.fromRGB(28, 33, 44)
	designFrame.BorderSizePixel = 0
	designFrame.Parent = card

	local designCorner = Instance.new("UICorner")
	designCorner.CornerRadius = UDim.new(0, 10)
	designCorner.Parent = designFrame

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.Size = UDim2.new(1, -12, 1, -12)
	image.Position = UDim2.fromOffset(6, 6)
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = designFrame

	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "Stats"
	statsFrame.Size = UDim2.fromOffset(160, 50)
	statsFrame.Position = UDim2.fromOffset(92, 48)
	statsFrame.BackgroundTransparency = 1
	statsFrame.Parent = card

	local beforeFrame = createStatValueFrame("Before", "Current", UDim2.fromOffset(0, 0))
	beforeFrame.Parent = statsFrame

	local afterFrame = createStatValueFrame("After", "Next", UDim2.fromOffset(82, 0))
	afterFrame.Parent = statsFrame

	local buttonsFrame = Instance.new("Frame")
	buttonsFrame.Name = "Buttons"
	buttonsFrame.Size = UDim2.fromOffset(172, 82)
	buttonsFrame.Position = UDim2.new(1, -182, 0, 15)
	buttonsFrame.BackgroundTransparency = 1
	buttonsFrame.Parent = card

	local moneyButton = Instance.new("TextButton")
	moneyButton.Name = "Money"
	moneyButton.Size = UDim2.new(1, 0, 0, 34)
	moneyButton.Position = UDim2.fromOffset(0, 0)
	moneyButton.BackgroundColor3 = Color3.fromRGB(62, 148, 86)
	moneyButton.BorderSizePixel = 0
	moneyButton.AutoButtonColor = true
	moneyButton.Font = Enum.Font.GothamBold
	moneyButton.Text = ""
	moneyButton.TextSize = 16
	moneyButton.Parent = buttonsFrame

	local moneyCorner = Instance.new("UICorner")
	moneyCorner.CornerRadius = UDim.new(0, 10)
	moneyCorner.Parent = moneyButton

	local moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "Text"
	moneyLabel.Size = UDim2.new(1, -8, 1, 0)
	moneyLabel.Position = UDim2.fromOffset(4, 0)
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Font = Enum.Font.GothamBold
	moneyLabel.Text = "$0"
	moneyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	moneyLabel.TextSize = 15
	moneyLabel.Parent = moneyButton

	local robuxButton = Instance.new("TextButton")
	robuxButton.Name = "Robux"
	robuxButton.Size = UDim2.new(1, 0, 0, 34)
	robuxButton.Position = UDim2.fromOffset(0, 42)
	robuxButton.BackgroundColor3 = Color3.fromRGB(45, 96, 172)
	robuxButton.BorderSizePixel = 0
	robuxButton.AutoButtonColor = true
	robuxButton.Font = Enum.Font.GothamBold
	robuxButton.Text = ""
	robuxButton.TextSize = 16
	robuxButton.Parent = buttonsFrame

	local robuxCorner = Instance.new("UICorner")
	robuxCorner.CornerRadius = UDim.new(0, 10)
	robuxCorner.Parent = robuxButton

	local robuxLabel = Instance.new("TextLabel")
	robuxLabel.Name = "Text"
	robuxLabel.Size = UDim2.new(1, -8, 1, 0)
	robuxLabel.Position = UDim2.fromOffset(4, 0)
	robuxLabel.BackgroundTransparency = 1
	robuxLabel.Font = Enum.Font.GothamBold
	robuxLabel.Text = "R$"
	robuxLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	robuxLabel.TextSize = 15
	robuxLabel.Parent = robuxButton

	return card
end

local function getUpgradeTemplate(): Frame
	if upgradeTemplateCache then
		return upgradeTemplateCache
	end

	local replicatedTemplate = Templates:FindFirstChild("UpgradeTemplate")
	if replicatedTemplate and replicatedTemplate:IsA("Frame") then
		upgradeTemplateCache = replicatedTemplate
		return replicatedTemplate
	end

	if not hasWarnedAboutMissingUpgradeTemplate then
		hasWarnedAboutMissingUpgradeTemplate = true
		warn("[UpgradesUIController] ReplicatedStorage.Templates.UpgradeTemplate is missing. Falling back to a code-built template.")
	end

	upgradeTemplateCache = createFallbackUpgradeTemplate()
	return upgradeTemplateCache
end

local function reportStoreOpened(surface: string)
	reportAnalyticsIntent:FireServer("StoreOpened", {
		surface = surface,
		section = "upgrades",
		entrypoint = "frame_open",
	})
end

local function reportStorePromptFailed(upgradeId: string, productId: number?, reason: string)
	reportAnalyticsIntent:FireServer("StorePromptFailed", {
		surface = "upgrades",
		section = "upgrades",
		entrypoint = "robux_button",
		productName = upgradeId,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
		reason = reason,
	})
end

local function trySetRobuxPrice(label: TextLabel?, productId: number?)
	if not label or type(productId) ~= "number" or productId <= 0 then
		return
	end

	local cachedPrice = robuxPriceCache[productId]
	if cachedPrice then
		label.Text = cachedPrice
		return
	end

	if not isUpgradesFrameVisible() then
		return
	end

	if robuxPriceRequestsInFlight[productId] then
		return
	end

	robuxPriceRequestsInFlight[productId] = true

	task.spawn(function()
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		robuxPriceRequestsInFlight[productId] = nil
		if success and info and label.Parent then
			local priceText = "R$ " .. tostring(info.PriceInRobux)
			robuxPriceCache[productId] = priceText
			label.Text = priceText
		end
	end)
end

local function initializeUI(forceRebuild: boolean?)
	if uiInitialized and not forceRebuild then
		return true
	end

	local scrollingFrame = getUpgradesScrollingFrame()
	if not scrollingFrame then
		return false
	end

	ensureScrollingLayout(scrollingFrame)

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	table.clear(uiReferences)
	local upgradeTemplate = getUpgradeTemplate()

	for _, upgrade in ipairs(UpgradesConfig.Upgrades) do
		if upgrade.HiddenInUI == true then
			continue
		end

		local newUpgrade = upgradeTemplate:Clone()
		stripScripts(newUpgrade)
		newUpgrade.Name = upgrade.Id
		newUpgrade.Visible = true

		local titleLabel = newUpgrade:FindFirstChild("Text") :: TextLabel
		if titleLabel then
			titleLabel.Text = upgrade.DisplayName
		end

		local designFrame = newUpgrade:FindFirstChild("Design")
		if designFrame then
			local img = designFrame:FindFirstChild("Image") or designFrame:FindFirstChildWhichIsA("ImageLabel") :: ImageLabel
			if img then
				img.Image = upgrade.ImageId
			end
		end

		local buttonsFrame = newUpgrade:FindFirstChild("Buttons")
		local moneyBtn = buttonsFrame and buttonsFrame:FindFirstChild("Money") :: TextButton
		local robuxBtn = buttonsFrame and buttonsFrame:FindFirstChild("Robux") :: TextButton

		local moneyPriceLabel = moneyBtn and findTextLabel(moneyBtn)
		local robuxPriceLabel = robuxBtn and findTextLabel(robuxBtn)

		local statsFrame = newUpgrade:FindFirstChild("Stats")
		local beforeFrame = statsFrame and statsFrame:FindFirstChild("Before")
		local afterFrame = statsFrame and statsFrame:FindFirstChild("After")

		local beforeLabel = beforeFrame and beforeFrame:FindFirstChild("Text") :: TextLabel
		local afterLabel = afterFrame and afterFrame:FindFirstChild("Text") :: TextLabel

		if moneyBtn then
			setupButtonAnimation(moneyBtn)
			moneyBtn.MouseButton1Click:Connect(function()
				reportAnalyticsIntent:FireServer("UpgradeSelected", {
					upgradeId = upgrade.Id,
				})
				requestUpgradeEvent:FireServer(upgrade.Id)
			end)
		end

		if robuxBtn then
			local robuxId = upgrade.RobuxProductId
			if robuxId then
				setupButtonAnimation(robuxBtn)
				trySetRobuxPrice(robuxPriceLabel, robuxId)
				robuxBtn.MouseButton1Click:Connect(function()
					reportAnalyticsIntent:FireServer("UpgradePurchaseRequested", {
						upgradeId = upgrade.Id,
						paymentType = "robux",
						surface = "upgrades",
					})
					local success, err = pcall(function()
						MarketplaceService:PromptProductPurchase(player, robuxId)
					end)
					if not success then
						warn("[UpgradesUIController] Failed to prompt robux upgrade:", upgrade.Id, err)
						reportStorePromptFailed(upgrade.Id, robuxId, "prompt_failed")
					end
				end)
			else
				robuxBtn.Visible = false
			end
		end

		uiReferences[upgrade.Id] = {
			MoneyPriceLabel = moneyPriceLabel,
			BeforeLabel = beforeLabel,
			AfterLabel = afterLabel,
			Amount = upgrade.Amount,
		}

		newUpgrade.Parent = scrollingFrame
	end

	uiInitialized = true
	return true
end

local function refreshUpgradeVisual(upgradeId: string, upgradeData: any)
	local ref = uiReferences[upgradeId]
	if not ref then
		return
	end

	if upgradeId == "Carry1" and upgradeData.Current >= MAX_CARRY_CAPACITY then
		if ref.MoneyPriceLabel then ref.MoneyPriceLabel.Text = "MAX" end
		if ref.BeforeLabel then ref.BeforeLabel.Text = tostring(upgradeData.Current) end
		if ref.AfterLabel then ref.AfterLabel.Text = "MAX" end
		return
	end

	if ref.MoneyPriceLabel then
		if isTutorialFreeUpgrade(upgradeId, upgradeData) then
			ref.MoneyPriceLabel.Text = "FREE"
		else
			ref.MoneyPriceLabel.Text = "$" .. NumberFormatter.Format(upgradeData.Cost)
		end
	end
	if ref.BeforeLabel then ref.BeforeLabel.Text = tostring(upgradeData.Current) end
	if ref.AfterLabel then ref.AfterLabel.Text = tostring(upgradeData.Current + upgradeData.Amount) end
end

local function refreshUpgradeVisuals()
	for upgradeId, upgradeData in pairs(lastUpgradeUiData) do
		refreshUpgradeVisual(upgradeId, upgradeData)
	end
end

local function handleUpgradesFrameOpened()
	local now = tick()
	if now - lastVisibleOpenHandledAt < FRAME_OPEN_REFRESH_COOLDOWN then
		return
	end

	if not initializeUI() then
		return
	end

	lastVisibleOpenHandledAt = now
	reportAnalyticsIntent:FireServer("UpgradesOpened")
	reportStoreOpened("upgrades")
	updateEvent:FireServer()
	task.defer(refreshUpgradeVisuals)
end

task.spawn(function()
	local upgradesFrame = getUpgradesFrame()

	upgradesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if upgradesFrame.Visible then
			handleUpgradesFrameOpened()
		end
	end)
end)

local function onServerUpdate(data: any)
	lastUpgradeUiData = data or {}

	for upgradeId, upgradeData in pairs(data or {}) do
		refreshUpgradeVisual(upgradeId, upgradeData)
	end
end

initializeUI(true)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	initializeUI(true)
	updateEvent:FireServer()
	task.defer(refreshUpgradeVisuals)
end)

updateEvent.OnClientEvent:Connect(onServerUpdate)
player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
	refreshUpgradeVisuals()
end)
updateEvent:FireServer()
