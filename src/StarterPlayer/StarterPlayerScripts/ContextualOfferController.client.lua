--!strict
-- LOCATION: StarterPlayerScripts/ContextualOfferController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local showContextualOffer = events:WaitForChild("ShowContextualOffer") :: RemoteEvent
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local GLOBAL_COOLDOWN = 60
local PER_OFFER_COOLDOWN = 180
local AUTO_HIDE_TIME = 8
local AUTO_BOMB_IDLE_TIME = 90
local CROWDED_ZONE_TIME = 60

local shownThisSession: {[string]: boolean} = {}
local lastShownByOffer: {[string]: number} = {}
local lastShownAt = 0
local purchasePromptActiveUntil = 0
local currentOfferKey: string? = nil
local ctaGui: ScreenGui? = nil
local ctaButton: TextButton? = nil
local ctaSwayTween: Tween? = nil

local moneyStat: NumberValue? = nil
local lastMoney = 0
local moneyUnchangedSince = os.clock()
local miningEnteredAt: number? = nil

local oneTimeSessionOffers = {
	EarlyGame = true,
	CrowdedServer = true,
}

local offerMeta: {[string]: {Title: string, Description: string}} = {
	Shield = {Title = "Shield", Description = "Protect your carried brainrots from bomb hits"},
	BombUpgrade = {Title = "Bomb Upgrade", Description = "Upgrade bomb depth and radius to blast deeper"},
	AutoBomb = {Title = "Auto Bomb", Description = "Hands-free farming with auto throws"},
	AutoCollect = {Title = "Collect All", Description = "Collect all base income with one touch"},
	NukeBooster = {Title = "Nuke Booster", Description = "Blast all players in mining zone"},
	StarterPack = {Title = "Starter Pack", Description = "Kickstart income with premium pack"},
	EarlyGame = {Title = "Starter Pack", Description = "Kickstart income with premium pack"},
	CrowdedServer = {Title = "Nuke Booster", Description = "Many players nearby - clear the zone now"},
	MegaExplosion = {Title = "Mega Explosion", Description = "Max explosion radius for 10 minutes"},
}

local function isInMiningZone(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local zones = workspace:FindFirstChild("Zones")
	if not zones then
		return false
	end

	for _, zonePart in ipairs(zones:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(root.Position)
			local size = zonePart.Size
			if math.abs(relativePos.X) <= size.X / 2 and math.abs(relativePos.Y) <= size.Y / 2 and math.abs(relativePos.Z) <= size.Z / 2 then
				return true
			end
		end
	end

	return false
end

local function shouldSuppressCta(): boolean
	if FrameManager.isAnyFrameOpen() then
		return true
	end
	if os.clock() < purchasePromptActiveUntil then
		return true
	end
	return false
end

local function stopSway()
	if ctaSwayTween then
		ctaSwayTween:Cancel()
		ctaSwayTween = nil
	end
end

local function hideCta()
	local button = ctaButton
	if not button or not button.Parent then
		currentOfferKey = nil
		return
	end

	stopSway()
	local tween = TweenService:Create(button, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Position = UDim2.new(0.66, 0, 0.58, 0),
	})
	tween:Play()
	tween.Completed:Wait()
	button.Visible = false
	currentOfferKey = nil
end

local function canShowOffer(offerKey: string): boolean
	local now = os.clock()
	if (now - lastShownAt) < GLOBAL_COOLDOWN then
		return false
	end
	if (now - (lastShownByOffer[offerKey] or 0)) < PER_OFFER_COOLDOWN then
		return false
	end
	if oneTimeSessionOffers[offerKey] and shownThisSession[offerKey] then
		return false
	end
	if currentOfferKey then
		return false
	end
	if shouldSuppressCta() then
		return false
	end
	return true
end

local function resolveOfferKey(rawOfferKey: string): string
	if rawOfferKey == "EarlyGame" then
		return "StarterPack"
	end
	if rawOfferKey == "CrowdedServer" then
		return "NukeBooster"
	end
	return rawOfferKey
end

local function reportStorePromptFailed(offerKey: string, productName: string, purchaseKind: string, purchaseId: number?, reason: string)
	local payload = {
		surface = "contextual_offer",
		section = "contextual_offer",
		entrypoint = "cta",
		productName = productName,
		purchaseKind = purchaseKind,
		paymentType = "robux",
		offerKey = offerKey,
		reason = reason,
	}
	if purchaseKind == "gamepass" then
		payload.passId = purchaseId
	else
		payload.productId = purchaseId
	end
	reportAnalyticsIntent:FireServer("StorePromptFailed", payload)
end

local function promptFromOffer(offerKey: string)
	local resolved = resolveOfferKey(offerKey)
	if resolved == "BombUpgrade" then
		FrameManager.open("Pickaxes")
		return
	end
	if resolved == "AutoCollect" then
		local passId = ProductConfigurations.GamePasses.CollectAll
		if type(passId) == "number" and passId > 0 then
			reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
				surface = "contextual_offer",
				section = "contextual_offer",
				entrypoint = "cta",
				productName = "CollectAll",
				passId = passId,
				purchaseKind = "gamepass",
				paymentType = "robux",
				offerKey = offerKey,
			})
			purchasePromptActiveUntil = os.clock() + 15
			local success, err = pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, passId)
			end)
			if not success then
				purchasePromptActiveUntil = 0
				warn("[ContextualOfferController] Failed to prompt CollectAll pass:", err)
				reportStorePromptFailed(offerKey, "CollectAll", "gamepass", passId, "prompt_failed")
			end
		else
			reportStorePromptFailed(offerKey, "CollectAll", "gamepass", passId, "missing_pass_id")
		end
		return
	end
	if resolved == "StarterPack" then
		FrameManager.open("Shop")
		return
	end
	if resolved == "Shield" or resolved == "MegaExplosion" or resolved == "NukeBooster" or resolved == "AutoBomb" then
		FrameManager.open("Boosters")
	end
end

local function ensureCtaUi()
	if ctaGui and ctaGui.Parent and ctaButton and ctaButton.Parent then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "ContextualOfferGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 98
	gui.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "OfferCTA"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(0.72, 0, 0.58, 0)
	button.Size = UDim2.fromOffset(280, 74)
	button.BackgroundColor3 = Color3.fromRGB(255, 167, 77)
	button.BackgroundTransparency = 1
	button.TextColor3 = Color3.fromRGB(22, 22, 22)
	button.TextTransparency = 1
	button.TextWrapped = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.Visible = false
	button.ZIndex = 10
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button

	button.MouseButton1Click:Connect(function()
		local offerKey = currentOfferKey
		if not offerKey then
			return
		end
		local resolvedOfferKey = resolveOfferKey(offerKey)
		local action = if resolvedOfferKey == "AutoCollect" then "prompt_collect_all"
			elseif resolvedOfferKey == "BombUpgrade" then "open_pickaxes"
			elseif resolvedOfferKey == "StarterPack" then "open_shop"
			else "open_boosters"
		reportAnalyticsIntent:FireServer("ContextualOfferClicked", {
			offerKey = offerKey,
			resolvedOfferKey = resolvedOfferKey,
			action = action,
		})
		promptFromOffer(offerKey)
		hideCta()
	end)

	ctaGui = gui
	ctaButton = button
end

local function showOffer(offerKey: string)
	if not canShowOffer(offerKey) then
		return
	end

	ensureCtaUi()
	local button = ctaButton
	if not button then
		return
	end

	local meta = offerMeta[offerKey] or {Title = offerKey, Description = "Tap to view offer"}
	button.Text = meta.Title .. "\n" .. meta.Description
	button.Visible = true
	button.Position = UDim2.new(0.66, 0, 0.58, 0)
	button.BackgroundTransparency = 1
	button.TextTransparency = 1

	lastShownAt = os.clock()
	lastShownByOffer[offerKey] = lastShownAt
	shownThisSession[offerKey] = true
	currentOfferKey = offerKey

	local tween = TweenService:Create(button, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.7, 0, 0.58, 0),
		BackgroundTransparency = 0.05,
		TextTransparency = 0,
	})
	tween:Play()

	stopSway()
	ctaSwayTween = TweenService:Create(button, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Rotation = 2,
	})
	ctaSwayTween:Play()

	task.delay(AUTO_HIDE_TIME, function()
		if currentOfferKey == offerKey then
			hideCta()
		end
	end)
end

local function updateMoneyTracking()
	if not moneyStat then
		return
	end
	local value = moneyStat.Value
	if value > lastMoney then
		lastMoney = value
		moneyUnchangedSince = os.clock()
	end
end

local function initMoneyTracking()
	local leaderstats = player:WaitForChild("leaderstats")
	local stat = leaderstats:WaitForChild("Money")
	if stat and stat:IsA("NumberValue") then
		moneyStat = stat
		lastMoney = stat.Value
		moneyUnchangedSince = os.clock()
		stat.Changed:Connect(updateMoneyTracking)
	end
end

local function setupPurchasePromptTracking()
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(finishedUserId)
		if finishedUserId == player.UserId then
			purchasePromptActiveUntil = 0
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(finishedPlayer)
		if finishedPlayer == player then
			purchasePromptActiveUntil = 0
		end
	end)
end

local function runLocalTriggerLoop()
	task.spawn(function()
		while true do
			if currentOfferKey and shouldSuppressCta() then
				hideCta()
			end

			local inZone = isInMiningZone()
			if inZone then
				if not miningEnteredAt then
					miningEnteredAt = os.clock()
				end
			else
				miningEnteredAt = nil
				moneyUnchangedSince = os.clock()
			end

			if inZone and (os.clock() - moneyUnchangedSince) >= AUTO_BOMB_IDLE_TIME and player:GetAttribute("HasAutoBomb") ~= true then
				showOffer("AutoBomb")
				moneyUnchangedSince = os.clock()
			end

			if inZone and miningEnteredAt and (os.clock() - miningEnteredAt) >= CROWDED_ZONE_TIME and #Players:GetPlayers() >= 4 then
				showOffer("CrowdedServer")
				miningEnteredAt = os.clock()
			end

			if not shownThisSession.EarlyGame then
				local rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
				local collected = tonumber(player:GetAttribute("TotalBrainrotsCollected")) or 0
				if rebirths == 0 and collected < 10 then
					showOffer("EarlyGame")
				end
			end

			task.wait(1)
		end
	end)
end

showContextualOffer.OnClientEvent:Connect(function(offerKey: string)
	if type(offerKey) ~= "string" or offerKey == "" then
		return
	end
	showOffer(offerKey)
end)

initMoneyTracking()
setupPurchasePromptTracking()
runLocalTriggerLoop()
