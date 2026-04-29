--!strict
-- LOCATION: StarterPlayerScripts/BoosterRewardedAdFallbackController

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NotificationManager = require(Modules:WaitForChild("NotificationManager"))
local ProductConfigurations = require(Modules:WaitForChild("ProductConfigurations"))

local Events = ReplicatedStorage:WaitForChild("Events")
local requestRewardedAdEvent = Events:WaitForChild("RequestRewardedAd") :: RemoteEvent
local rewardedAdResultEvent = Events:WaitForChild("RewardedAdResult") :: RemoteEvent

local REQUEST_TIMEOUT = 30
local MODAL_NAME = "BoosterRewardedAdFallbackGui"

local BOOSTER_ATTRIBUTE_BY_NAME = {
	MegaExplosion = "MegaExplosionEndsAt",
	Shield = "ShieldEndsAt",
}

local productNameById: {[number]: string} = {}
for productName in pairs(ProductConfigurations.RewardedAdBoosters) do
	local productId = ProductConfigurations.Products[productName]
	if type(productId) == "number" and productId > 0 then
		productNameById[productId] = productName
	end
end

local overlay: Frame? = nil
local titleLabel: TextLabel? = nil
local bodyLabel: TextLabel? = nil
local watchButton: TextButton? = nil
local cancelButton: TextButton? = nil
local activeOfferProductName: string? = nil
local requestPending = false
local requestSerial = 0
local rewardedAdFallbackUnavailable = false

local function getDisplayName(productName: string): string
	local boosterConfig = ProductConfigurations.Boosters[productName]
	if type(boosterConfig) == "table" and type(boosterConfig.DisplayName) == "string" and boosterConfig.DisplayName ~= "" then
		return boosterConfig.DisplayName
	end

	return productName
end

local function isBoosterActive(productName: string): boolean
	local attributeName = BOOSTER_ATTRIBUTE_BY_NAME[productName]
	if not attributeName then
		return false
	end

	local endsAt = math.max(0, tonumber(player:GetAttribute(attributeName)) or 0)
	return endsAt > os.time()
end

local function setButtonEnabled(button: TextButton?, enabled: boolean)
	if not button then
		return
	end

	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundTransparency = if enabled then 0 else 0.35
end

local function updateModalText()
	local productName = activeOfferProductName
	if not productName then
		return
	end

	local displayName = getDisplayName(productName)
	if titleLabel then
		titleLabel.Text = if requestPending then "Opening Ad..." else "Get " .. displayName .. " Free?"
	end
	if bodyLabel then
		bodyLabel.Text = "Watch a short ad to activate " .. displayName .. " for 10 minutes."
	end
	if watchButton then
		watchButton.Text = if requestPending then "PLEASE WAIT" else "WATCH AD"
	end

	setButtonEnabled(watchButton, not requestPending)
	setButtonEnabled(cancelButton, not requestPending)
end

local function hideOffer()
	if overlay then
		overlay.Visible = false
	end

	activeOfferProductName = nil
	requestPending = false
	updateModalText()
end

local function ensureModal(): Frame?
	if overlay and overlay.Parent then
		return overlay
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local existingGui = playerGui:FindFirstChild(MODAL_NAME)
	if existingGui and existingGui:IsA("ScreenGui") then
		existingGui:Destroy()
	end

	local newGui = Instance.new("ScreenGui")
	newGui.Name = MODAL_NAME
	newGui.IgnoreGuiInset = true
	newGui.ResetOnSpawn = false
	newGui.DisplayOrder = 950
	newGui.Enabled = true
	newGui.Parent = playerGui

	local newOverlay = Instance.new("Frame")
	newOverlay.Name = "Overlay"
	newOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	newOverlay.BackgroundTransparency = 0.35
	newOverlay.BorderSizePixel = 0
	newOverlay.Size = UDim2.fromScale(1, 1)
	newOverlay.Visible = false
	newOverlay.Parent = newGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.86, 0, 0, 190)
	panel.BackgroundColor3 = Color3.fromRGB(24, 30, 43)
	panel.BorderSizePixel = 0
	panel.Parent = newOverlay

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(380, 190)
	sizeConstraint.MinSize = Vector2.new(280, 190)
	sizeConstraint.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 205, 96)
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 18)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 34)
	title.Font = Enum.Font.GothamBold
	title.Text = ""
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 22
	title.TextWrapped = true
	title.LayoutOrder = 1
	title.Parent = panel

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 44)
	body.Font = Enum.Font.Gotham
	body.Text = ""
	body.TextColor3 = Color3.fromRGB(224, 231, 242)
	body.TextSize = 15
	body.TextWrapped = true
	body.LayoutOrder = 2
	body.Parent = panel

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 48)
	buttons.LayoutOrder = 3
	buttons.Parent = panel

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 10)
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Parent = buttons

	local function createButton(name: string, text: string, color: Color3, order: number): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Size = UDim2.new(0.5, -5, 1, 0)
		button.BackgroundColor3 = color
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.Text = text
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.TextSize = 14
		button.LayoutOrder = order
		button.Parent = buttons

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button

		return button
	end

	local newWatchButton = createButton("WatchAd", "WATCH AD", Color3.fromRGB(49, 176, 95), 1)
	local newCancelButton = createButton("Cancel", "NOT NOW", Color3.fromRGB(73, 82, 99), 2)

	newWatchButton.Activated:Connect(function()
		local productName = activeOfferProductName
		if not productName or requestPending then
			return
		end

		if isBoosterActive(productName) then
			hideOffer()
			return
		end

		requestPending = true
		requestSerial += 1
		local currentSerial = requestSerial
		updateModalText()
		requestRewardedAdEvent:FireServer(productName)

		task.delay(REQUEST_TIMEOUT, function()
			if requestPending and requestSerial == currentSerial then
				hideOffer()
				NotificationManager.show("Rewarded ad request timed out. Try again.", "Error")
			end
		end)
	end)

	newCancelButton.Activated:Connect(function()
		if requestPending then
			return
		end

		hideOffer()
	end)

	overlay = newOverlay
	titleLabel = title
	bodyLabel = body
	watchButton = newWatchButton
	cancelButton = newCancelButton

	return newOverlay
end

local function showOffer(productName: string)
	if rewardedAdFallbackUnavailable or requestPending or isBoosterActive(productName) then
		return
	end

	activeOfferProductName = productName
	local modal = ensureModal()
	if not modal then
		return
	end

	updateModalText()
	modal.Visible = true
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, wasPurchased: boolean)
	if userId ~= player.UserId or wasPurchased == true then
		return
	end

	local productName = productNameById[productId]
	if not productName then
		return
	end

	showOffer(productName)
end)

rewardedAdResultEvent.OnClientEvent:Connect(function(status: string, message: string?, rewardKey: string?)
	if not activeOfferProductName or rewardKey ~= activeOfferProductName then
		return
	end

	local failedMessage = if type(message) == "string" and message ~= "" then message else nil
	if status == "Unavailable" then
		rewardedAdFallbackUnavailable = true
	end
	hideOffer()

	if status ~= "Success" and failedMessage then
		NotificationManager.show(failedMessage, "Error")
	end
end)
