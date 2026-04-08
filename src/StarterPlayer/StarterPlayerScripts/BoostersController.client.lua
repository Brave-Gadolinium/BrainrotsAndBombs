--!strict
-- LOCATION: StarterPlayerScripts/BoostersController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestAutoBombState = events:WaitForChild("RequestAutoBombState") :: RemoteEvent
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

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
	else
		local label = button:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = text
		end
	end
end

local function reportStoreOpened(surface: string)
	reportAnalyticsIntent:FireServer("StoreOpened", {
		surface = surface,
		section = "boosters",
		entrypoint = "frame_open",
	})
end

local function reportStorePromptFailed(productName: string, purchaseKind: string, purchaseId: number?, reason: string)
	local payload = {
		surface = "boosters",
		section = "boosters",
		entrypoint = "button",
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

local function setupCardActions(boostersFrame: Frame)
	local megaCard = safeFindCard(boostersFrame, "MegaExplosion")
	local shieldCard = safeFindCard(boostersFrame, "Shield")
	local nukeCard = safeFindCard(boostersFrame, "NukeBooster")
	local autoCard = safeFindCard(boostersFrame, "AutoBomb")

	local function bindPrompt(card: Frame?, productName: string, infoType: Enum.InfoType)
		if not card then
			return
		end
		local buyButton = card:FindFirstChild("Buy")
		if not buyButton or not buyButton:IsA("GuiButton") then
			return
		end

		buyButton.MouseButton1Click:Connect(function()
			if infoType == Enum.InfoType.Product then
				local productId = ProductConfigurations.Products[productName]
				if type(productId) == "number" and productId > 0 then
					reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
						surface = "boosters",
						section = "boosters",
						entrypoint = "button",
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
						reportStorePromptFailed(productName, "product", productId, "prompt_failed")
					end
				else
					reportStorePromptFailed(productName, "product", productId, "missing_product_id")
				end
			else
				local passId = ProductConfigurations.GamePasses[productName]
				if type(passId) == "number" and passId > 0 then
					reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
						surface = "boosters",
						section = "boosters",
						entrypoint = "button",
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
						reportStorePromptFailed(productName, "gamepass", passId, "prompt_failed")
					end
				else
					reportStorePromptFailed(productName, "gamepass", passId, "missing_pass_id")
				end
			end
		end)
	end

	bindPrompt(megaCard, "MegaExplosion", Enum.InfoType.Product)
	bindPrompt(shieldCard, "Shield", Enum.InfoType.Product)
	bindPrompt(nukeCard, "NukeBooster", Enum.InfoType.Product)
	if autoCard then
		local autoButton = autoCard:FindFirstChild("Buy")
		if autoButton and autoButton:IsA("GuiButton") then
			autoButton.MouseButton1Click:Connect(function()
				if player:GetAttribute("HasAutoBomb") == true then
					local nextState = not (player:GetAttribute("AutoBombEnabled") == true)
					reportAnalyticsIntent:FireServer("AutoBombToggleRequested", {
						surface = "boosters",
						enabled = nextState,
					})
					requestAutoBombState:FireServer(nextState)
					return
				end

				local passId = ProductConfigurations.GamePasses.AutoBomb
				if type(passId) == "number" and passId > 0 then
					reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
						surface = "boosters",
						section = "boosters",
						entrypoint = "button",
						productName = "AutoBomb",
						passId = passId,
						purchaseKind = "gamepass",
						paymentType = "robux",
					})
					local success, err = pcall(function()
						MarketplaceService:PromptGamePassPurchase(player, passId)
					end)
					if not success then
						warn("[BoostersController] Failed to prompt AutoBomb pass:", err)
						reportStorePromptFailed("AutoBomb", "gamepass", passId, "prompt_failed")
					end
				else
					reportStorePromptFailed("AutoBomb", "gamepass", passId, "missing_pass_id")
				end
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
	local hasAutoBomb = player:GetAttribute("HasAutoBomb") == true
	local autoBombEnabled = player:GetAttribute("AutoBombEnabled") == true

	if megaCard then
		local button = megaCard:FindFirstChild("Buy") :: GuiButton?
		if megaEndsAt > os.time() then
			setButtonText(button, "Active " .. formatRemainingTime(megaEndsAt))
		else
			setButtonText(button, "Buy R$39")
		end
	end

	if shieldCard then
		local button = shieldCard:FindFirstChild("Buy") :: GuiButton?
		if shieldEndsAt > os.time() then
			setButtonText(button, "Active " .. formatRemainingTime(shieldEndsAt))
		else
			setButtonText(button, "Buy R$39")
		end
	end

	if nukeCard then
		local button = nukeCard:FindFirstChild("Buy") :: GuiButton?
		setButtonText(button, "Buy R$79")
	end

	if autoCard then
		local button = autoCard:FindFirstChild("Buy") :: GuiButton?
		if hasAutoBomb then
			setButtonText(button, if autoBombEnabled then "Owned - On" else "Owned - Off")
		else
			setButtonText(button, "Buy R$299")
		end
	end
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
	end

	player:GetAttributeChangedSignal("MegaExplosionEndsAt"):Connect(refresh)
	player:GetAttributeChangedSignal("ShieldEndsAt"):Connect(refresh)
	player:GetAttributeChangedSignal("HasAutoBomb"):Connect(refresh)
	player:GetAttributeChangedSignal("AutoBombEnabled"):Connect(refresh)

	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)

	refresh()
end

init()
