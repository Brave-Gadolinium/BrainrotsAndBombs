--!strict
-- LOCATION: StarterPlayerScripts/BoostersController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local ClientZoneService = require(ReplicatedStorage.Modules.ClientZoneService)

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestAutoBombState = events:WaitForChild("RequestAutoBombState") :: RemoteEvent
local requestUseBoosterCharge = events:WaitForChild("RequestUseBoosterCharge") :: RemoteEvent
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

type HudBoosterDefinition = {
	ProductName: string,
	CandidateNames: {string},
}

local HUD_BOOSTER_DEFINITIONS: {HudBoosterDefinition} = {
	{ProductName = "MegaExplosion", CandidateNames = {"MegaExplosion", "Mega Explosion"}},
	{ProductName = "Shield", CandidateNames = {"Shield"}},
	{ProductName = "NukeBooster", CandidateNames = {"Nuke", "NukeBooster", "Nuke Booster"}},
}

local WATCHED_HUD_DESCENDANTS = {
	GUI = true,
	HUD = true,
	Left = true,
	Buttons1 = true,
	MegaExplosion = true,
	["Mega Explosion"] = true,
	Shield = true,
	Nuke = true,
	NukeBooster = true,
	["Nuke Booster"] = true,
}

local HUD_CHARGE_BADGE_NAME = "ChargeCount"

local function formatRemainingTime(endsAt: number): string
	local remaining = math.max(0, math.floor(endsAt - os.time()))
	local minutes = math.floor(remaining / 60)
	local seconds = remaining % 60
	return string.format("%02d:%02d", minutes, seconds)
end

local function safeFindCard(frame: Instance, cardName: string): Frame?
	local card = frame:FindFirstChild(cardName)
	if card and card:IsA("Frame") then
		return card
	end

	return nil
end

local function setButtonText(button: GuiButton?, text: string)
	if not button then
		return
	end

	if button:IsA("TextButton") then
		button.Text = text
		return
	end

	local label = button:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = text
	end
end

local function ensureHudChargeBadge(parent: GuiObject): TextLabel
	local existing = parent:FindFirstChild(HUD_CHARGE_BADGE_NAME)
	if existing and existing:IsA("TextLabel") then
		return existing
	end

	local badge = Instance.new("TextLabel")
	badge.Name = HUD_CHARGE_BADGE_NAME
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -2, 0, 2)
	badge.Size = UDim2.fromOffset(34, 20)
	badge.BackgroundColor3 = Color3.fromRGB(255, 196, 64)
	badge.BorderSizePixel = 0
	badge.Font = Enum.Font.GothamBold
	badge.TextColor3 = Color3.fromRGB(25, 25, 25)
	badge.TextScaled = true
	badge.Visible = false
	badge.ZIndex = parent.ZIndex + 10
	badge.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = badge

	return badge
end

local function setHudChargeBadge(parent: GuiObject?, productName: string)
	if not parent then
		return
	end

	local badge = ensureHudChargeBadge(parent)
	local attributeName: string? = nil
	if productName == "MegaExplosion" then
		attributeName = "MegaExplosionCharges"
	elseif productName == "Shield" then
		attributeName = "ShieldCharges"
	elseif productName == "NukeBooster" then
		attributeName = "NukeBoosterCharges"
	end
	local count = if attributeName then math.max(0, math.floor(tonumber(player:GetAttribute(attributeName)) or 0)) else 0
	if count > 0 then
		badge.Text = "x" .. tostring(count)
		badge.Visible = true
	else
		badge.Visible = false
	end
end

local function bindButtonOnce(button: GuiButton?, attributeName: string, callback: () -> ())
	if not button or button:GetAttribute(attributeName) == true then
		return
	end

	button:SetAttribute(attributeName, true)
	button.Activated:Connect(callback)
end

local function findNamedInstance(parent: Instance, candidateNames: {string}): Instance?
	for _, candidateName in ipairs(candidateNames) do
		local directChild = parent:FindFirstChild(candidateName)
		if directChild then
			return directChild
		end
	end

	for _, candidateName in ipairs(candidateNames) do
		local descendant = parent:FindFirstChild(candidateName, true)
		if descendant then
			return descendant
		end
	end

	return nil
end

local function findHudButtonsContainer(): GuiObject?
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end

	local gui = playerGui:FindFirstChild("GUI")
	if not gui then
		return nil
	end

	local hud = gui:FindFirstChild("HUD")
	if not hud then
		return nil
	end

	local leftPanel = hud:FindFirstChild("Left")
	if not leftPanel then
		return nil
	end

	local buttons1 = leftPanel:FindFirstChild("Buttons1")
	if buttons1 and buttons1:IsA("GuiObject") then
		return buttons1
	end

	return nil
end

local function resolveHudBooster(definition: HudBoosterDefinition): (GuiObject?, GuiButton?)
	local buttons1 = findHudButtonsContainer()
	if not buttons1 then
		return nil, nil
	end

	local target = findNamedInstance(buttons1, definition.CandidateNames)
	if not target then
		return nil, nil
	end

	local visibilityTarget = if target:IsA("GuiObject") then target else nil
	local actionButton: GuiButton? = nil

	if target:IsA("GuiButton") then
		actionButton = target
	else
		local nestedButton = target:FindFirstChildWhichIsA("GuiButton", true)
		if nestedButton then
			actionButton = nestedButton
		end
	end

	if not visibilityTarget and actionButton then
		visibilityTarget = actionButton
	end

	return visibilityTarget, actionButton
end

local function reportStoreOpened(surface: string)
	reportAnalyticsIntent:FireServer("StoreOpened", {
		surface = surface,
		section = "boosters",
		entrypoint = "frame_open",
	})
end

local function reportStorePromptFailed(
	surface: string,
	section: string,
	entrypoint: string,
	productName: string,
	purchaseKind: string,
	purchaseId: number?,
	reason: string
)
	local payload = {
		surface = surface,
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

local function promptBoosterProduct(surface: string, section: string, entrypoint: string, productName: string)
	local productId = ProductConfigurations.Products[productName]
	if type(productId) ~= "number" or productId <= 0 then
		reportStorePromptFailed(surface, section, entrypoint, productName, "product", productId, "missing_product_id")
		return
	end

	reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
		surface = surface,
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
		warn("[BoostersController] Failed to prompt product:", productName, err)
		reportStorePromptFailed(surface, section, entrypoint, productName, "product", productId, "prompt_failed")
	end
end

local function promptBoosterGamePass(surface: string, section: string, entrypoint: string, productName: string)
	local passId = ProductConfigurations.GamePasses[productName]
	if type(passId) ~= "number" or passId <= 0 then
		reportStorePromptFailed(surface, section, entrypoint, productName, "gamepass", passId, "missing_pass_id")
		return
	end

	reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
		surface = surface,
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
		warn("[BoostersController] Failed to prompt gamepass:", productName, err)
		reportStorePromptFailed(surface, section, entrypoint, productName, "gamepass", passId, "prompt_failed")
	end
end

local function getBoosterChargeAttribute(productName: string): string?
	if productName == "MegaExplosion" then
		return "MegaExplosionCharges"
	end
	if productName == "Shield" then
		return "ShieldCharges"
	end
	if productName == "NukeBooster" then
		return "NukeBoosterCharges"
	end
	return nil
end

local function getBoosterChargeCount(productName: string): number
	local attributeName = getBoosterChargeAttribute(productName)
	if not attributeName then
		return 0
	end

	return math.max(0, math.floor(tonumber(player:GetAttribute(attributeName)) or 0))
end

local function isTimedBoosterActive(productName: string): boolean
	if productName == "MegaExplosion" then
		return math.max(0, tonumber(player:GetAttribute("MegaExplosionEndsAt")) or 0) > os.time()
	end
	if productName == "Shield" then
		return math.max(0, tonumber(player:GetAttribute("ShieldEndsAt")) or 0) > os.time()
	end
	return false
end

local function useBoosterChargeOrPrompt(surface: string, section: string, entrypoint: string, productName: string)
	if isTimedBoosterActive(productName) then
		return
	end

	if getBoosterChargeCount(productName) > 0 then
		requestUseBoosterCharge:FireServer(productName)
		return
	end

	promptBoosterProduct(surface, section, entrypoint, productName)
end

local function shouldShowHudBoosterButtons(): boolean
	return ClientZoneService.IsInMineZone() and not FrameManager.isAnyFrameOpen()
end

local function syncHudBoosterButtons()
	local shouldShow = shouldShowHudBoosterButtons()

	for _, definition in ipairs(HUD_BOOSTER_DEFINITIONS) do
		local visibilityTarget, actionButton = resolveHudBooster(definition)
		if actionButton then
			bindButtonOnce(actionButton, "BoostersHudBound", function()
				useBoosterChargeOrPrompt("boosters_hud", "boosters_hud", "button", definition.ProductName)
			end)
			actionButton.Active = shouldShow
			actionButton.AutoButtonColor = shouldShow
		end

		if visibilityTarget then
			visibilityTarget.Visible = shouldShow
			setHudChargeBadge(visibilityTarget, definition.ProductName)
		elseif actionButton then
			setHudChargeBadge(actionButton, definition.ProductName)
		end
	end
end

local function setupCardActions(boostersFrame: Frame)
	local megaCard = safeFindCard(boostersFrame, "MegaExplosion")
	local shieldCard = safeFindCard(boostersFrame, "Shield")
	local nukeCard = safeFindCard(boostersFrame, "NukeBooster")
	local autoCard = safeFindCard(boostersFrame, "AutoBomb")

	local function bindProductCard(card: Frame?, productName: string)
		if not card then
			return
		end

		local buyButton = card:FindFirstChild("Buy")
		if not buyButton or not buyButton:IsA("GuiButton") then
			return
		end

		bindButtonOnce(buyButton, "BoostersCardBound", function()
			useBoosterChargeOrPrompt("boosters", "boosters", "button", productName)
		end)
	end

	bindProductCard(megaCard, "MegaExplosion")
	bindProductCard(shieldCard, "Shield")
	bindProductCard(nukeCard, "NukeBooster")

	if autoCard then
		local autoButton = autoCard:FindFirstChild("Buy")
		if autoButton and autoButton:IsA("GuiButton") then
			bindButtonOnce(autoButton, "BoostersCardBound", function()
				if player:GetAttribute("HasAutoBomb") == true then
					local nextState = not (player:GetAttribute("AutoBombEnabled") == true)
					reportAnalyticsIntent:FireServer("AutoBombToggleRequested", {
						surface = "boosters",
						enabled = nextState,
					})
					requestAutoBombState:FireServer(nextState)
					return
				end

				promptBoosterGamePass("boosters", "boosters", "button", "AutoBomb")
			end)
		end
	end
end

local function updateBoostersUI(boostersFrame: Frame)
	local megaCard = safeFindCard(boostersFrame, "MegaExplosion")
	local shieldCard = safeFindCard(boostersFrame, "Shield")
	local nukeCard = safeFindCard(boostersFrame, "NukeBooster")
	local autoCard = safeFindCard(boostersFrame, "AutoBomb")

	local megaEndsAt = math.max(0, tonumber(player:GetAttribute("MegaExplosionEndsAt")) or 0)
	local shieldEndsAt = math.max(0, tonumber(player:GetAttribute("ShieldEndsAt")) or 0)
	local megaCharges = getBoosterChargeCount("MegaExplosion")
	local shieldCharges = getBoosterChargeCount("Shield")
	local nukeCharges = getBoosterChargeCount("NukeBooster")
	local hasAutoBomb = player:GetAttribute("HasAutoBomb") == true
	local autoBombEnabled = player:GetAttribute("AutoBombEnabled") == true

	if nukeCard and nukeCharges > 0 then
		local button = nukeCard:FindFirstChild("Buy") :: GuiButton?
		setButtonText(button, "Use x" .. tostring(nukeCharges))
		nukeCard = nil
	end

	if megaCard then
		local button = megaCard:FindFirstChild("Buy") :: GuiButton?
		if megaEndsAt > os.time() then
			setButtonText(button, "Active " .. formatRemainingTime(megaEndsAt))
		elseif megaCharges > 0 then
			setButtonText(button, "Use x" .. tostring(megaCharges))
		else
			setButtonText(button, "Buy  39")
		end
	end

	if shieldCard then
		local button = shieldCard:FindFirstChild("Buy") :: GuiButton?
		if shieldEndsAt > os.time() then
			setButtonText(button, "Active " .. formatRemainingTime(shieldEndsAt))
		elseif shieldCharges > 0 then
			setButtonText(button, "Use x" .. tostring(shieldCharges))
		else
			setButtonText(button, "Buy  39")
		end
	end

	if nukeCard then
		local button = nukeCard:FindFirstChild("Buy") :: GuiButton?
		setButtonText(button, "Buy  79")
	end

	if autoCard then
		local button = autoCard:FindFirstChild("Buy") :: GuiButton?
		if hasAutoBomb then
			setButtonText(button, if autoBombEnabled then "Owned - On" else "Owned - Off")
		else
			setButtonText(button, "Buy  299")
		end
	end
end

local function shouldRefreshForHudDescendant(descendant: Instance): boolean
	if WATCHED_HUD_DESCENDANTS[descendant.Name] then
		return true
	end

	if descendant:IsA("GuiButton") and descendant:FindFirstAncestor("Buttons1") ~= nil then
		return true
	end

	return false
end

local function init()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI")
	local frames = gui:WaitForChild("Frames")
	local boostersFrame = frames:WaitForChild("Boosters") :: Frame

	setupCardActions(boostersFrame)
	boostersFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if boostersFrame.Visible then
			reportStoreOpened("boosters")
		end
	end)
	if boostersFrame.Visible then
		reportStoreOpened("boosters")
	end

	local function refresh()
		updateBoostersUI(boostersFrame)
		syncHudBoosterButtons()
	end

	player:GetAttributeChangedSignal("MegaExplosionEndsAt"):Connect(refresh)
	player:GetAttributeChangedSignal("ShieldEndsAt"):Connect(refresh)
	player:GetAttributeChangedSignal("MegaExplosionCharges"):Connect(refresh)
	player:GetAttributeChangedSignal("ShieldCharges"):Connect(refresh)
	player:GetAttributeChangedSignal("NukeBoosterCharges"):Connect(refresh)
	player:GetAttributeChangedSignal("HasAutoBomb"):Connect(refresh)
	player:GetAttributeChangedSignal("AutoBombEnabled"):Connect(refresh)

	FrameManager.Changed:Connect(function()
		syncHudBoosterButtons()
	end)

	ClientZoneService.Changed:Connect(function()
		syncHudBoosterButtons()
	end)

	player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
		task.defer(syncHudBoosterButtons)
	end)

	player.CharacterAdded:Connect(function()
		task.defer(syncHudBoosterButtons)
	end)

	player.CharacterRemoving:Connect(function()
		task.defer(syncHudBoosterButtons)
	end)

	playerGui.DescendantAdded:Connect(function(descendant)
		if shouldRefreshForHudDescendant(descendant) then
			task.defer(syncHudBoosterButtons)
		end
	end)

	playerGui.DescendantRemoving:Connect(function(descendant)
		if WATCHED_HUD_DESCENDANTS[descendant.Name] then
			task.defer(syncHudBoosterButtons)
		end
	end)

	task.spawn(function()
		while true do
			updateBoostersUI(boostersFrame)
			task.wait(1)
		end
	end)

	refresh()
end

init()
