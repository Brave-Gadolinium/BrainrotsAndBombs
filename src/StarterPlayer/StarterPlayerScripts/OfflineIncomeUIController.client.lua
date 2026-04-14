--!strict
-- LOCATION: StarterPlayerScripts/OfflineIncomeUIController

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local LimitedTimeOfferConfiguration = require(ReplicatedStorage.Modules.LimitedTimeOfferConfiguration)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local OfflineIncomeConfiguration = require(ReplicatedStorage.Modules.OfflineIncomeConfiguration)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OfflineIncome")
local getStatusRemote = remotesFolder:WaitForChild("GetStatus") :: RemoteFunction
local claimRemote = remotesFolder:WaitForChild("Claim") :: RemoteFunction
local startPlay15Remote = remotesFolder:WaitForChild("StartPlay15") :: RemoteFunction
local statusUpdatedRemote = remotesFolder:WaitForChild("StatusUpdated") :: RemoteEvent

type UiReferences = {
	Frame: GuiObject,
	EarnedSection: GuiObject,
	ClaimButton: GuiButton,
	ClaimButtonText: Instance?,
	MainEarnedText: Instance?,
	RobuxButton: GuiButton,
	RobuxRewardText: Instance?,
	RobuxPriceText: Instance?,
	Play15Button: GuiButton,
	Play15RewardText: Instance?,
}

local uiReferences: UiReferences? = nil
local currentStatus: any = nil
local purchasePromptActive = false
local requestInFlight = false
local productPriceLoaded = false
local limitedOfferPresentedThisSession = false
local ROBUX_ICON = utf8.char(0xE002)

local function warnMissing(pathDescription: string)
	warn("[OfflineIncomeUIController] Missing UI path:", pathDescription)
end

local function waitForPath(root: Instance, path: {string}, timeoutPerStep: number?): Instance?
	local current: Instance? = root
	for _, name in ipairs(path) do
		if not current then
			return nil
		end

		current = current:WaitForChild(name, timeoutPerStep or 5)
	end

	return current
end

local function isTextObject(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("TextLabel") or instance:IsA("TextButton"))
end

local function setText(instance: Instance?, text: string)
	if instance and instance:IsA("TextLabel") then
		instance.Text = text
	elseif instance and instance:IsA("TextButton") then
		instance.Text = text
	end
end

local function disableModalCloseButtons(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiButton") and (descendant.Name == "Close" or descendant.Name == "CloseButton") then
			descendant.Visible = false
			descendant.Active = false
			descendant.AutoButtonColor = false
		end
	end
end

local function isExcludedDescendant(instance: Instance, excludedRoots: {Instance?}): boolean
	for _, root in ipairs(excludedRoots) do
		if root and instance:IsDescendantOf(root) then
			return true
		end
	end

	return false
end

local function findNamedTextDescendant(root: Instance?, targetName: string, excludedRoots: {Instance?}?): Instance?
	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == targetName and isTextObject(descendant) then
			if not excludedRoots or not isExcludedDescendant(descendant, excludedRoots) then
				return descendant
			end
		end
	end

	return nil
end

local function findFirstButton(root: Instance?): GuiButton?
	if not root then
		return nil
	end

	if root:IsA("GuiButton") then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			return descendant
		end
	end

	return nil
end

local function normalizeToken(value: string?): string
	if type(value) ~= "string" then
		return ""
	end

	return string.lower(string.gsub(value, "[%W_]+", ""))
end

local function nameMatchesToken(instance: Instance?, token: string): boolean
	if not instance then
		return false
	end

	local normalizedName = normalizeToken(instance.Name)
	local normalizedToken = normalizeToken(token)
	return normalizedName ~= "" and normalizedToken ~= "" and string.find(normalizedName, normalizedToken, 1, true) ~= nil
end

local function findButtonContainerByPredicate(root: Instance?, predicate: (Instance) -> boolean): Instance?
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("GuiObject") and predicate(child) then
			return child
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") and predicate(descendant) then
			return descendant
		end
	end

	return nil
end

local function resolveRightActionRoots(rightButtons: Instance?): (Instance?, Instance?)
	if not rightButtons then
		return nil, nil
	end

	local play15Root = rightButtons:FindFirstChild("Play15")
	if not play15Root then
		play15Root = findButtonContainerByPredicate(rightButtons, function(instance)
			return nameMatchesToken(instance, "Play15")
				or findNamedTextDescendant(instance, "YouEarned15min") ~= nil
		end)
	end

	local robuxRoot = rightButtons:FindFirstChild("ClaimButtonx2")
		or rightButtons:FindFirstChild("ClaimButtonx5")
		or rightButtons:FindFirstChild("Robux")
	if not robuxRoot then
		robuxRoot = findButtonContainerByPredicate(rightButtons, function(instance)
			if instance == play15Root then
				return false
			end

			return nameMatchesToken(instance, "ClaimButtonx2")
				or nameMatchesToken(instance, "ClaimButtonx5")
				or nameMatchesToken(instance, "Robux")
				or findNamedTextDescendant(instance, "YouEarnedx2") ~= nil
		end)
	end

	if not robuxRoot and play15Root then
		for _, child in ipairs(rightButtons:GetChildren()) do
			if child:IsA("GuiObject") and child ~= play15Root and findFirstButton(child) then
				robuxRoot = child
				break
			end
		end
	end

	return robuxRoot, play15Root
end

local function setButtonEnabled(button: GuiButton?, enabled: boolean)
	if not button then
		return
	end

	button.Active = enabled
	button.AutoButtonColor = enabled

	if button:IsA("GuiObject") then
		button.Visible = true
	end
end

local function formatAmount(amount: number?): string
	return NumberFormatter.Format(math.max(0, math.floor(tonumber(amount) or 0)))
end

local function getConfiguredProductId(): number
	local productId = ProductConfigurations.Products[OfflineIncomeConfiguration.ProductKey]
	if type(productId) ~= "number" then
		return 0
	end

	return math.max(0, productId)
end

local function getPendingBaseAmount(status): number
	if type(status) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(status.PendingBaseAmount) or 0))
end

local function isPlay15Active(status): boolean
	return type(status) == "table" and status.Play15Active == true
end

local function isLimitedOfferTutorialBlocked(): boolean
	local onboardingStep = tonumber(localPlayer:GetAttribute("OnboardingStep")) or 0
	return onboardingStep > 0 and onboardingStep < TutorialConfiguration.FinalStep
end

local function isLimitedOfferAvailable(): boolean
	if LimitedTimeOfferConfiguration.Enabled ~= true then
		return false
	end

	if isLimitedOfferTutorialBlocked() then
		return false
	end

	if frames:FindFirstChild(LimitedTimeOfferConfiguration.FrameName) == nil then
		return false
	end

	if localPlayer:GetAttribute(LimitedTimeOfferConfiguration.ReadyAttribute) ~= true then
		return false
	end

	if localPlayer:GetAttribute(LimitedTimeOfferConfiguration.PurchaseAttribute) == true then
		return false
	end

	local endTime = math.max(0, tonumber(localPlayer:GetAttribute(LimitedTimeOfferConfiguration.EndAttribute)) or 0)
	if endTime <= 0 or Workspace:GetServerTimeNow() >= endTime then
		return false
	end

	return tonumber(localPlayer:GetAttribute(LimitedTimeOfferConfiguration.StartAttribute)) ~= nil
end

local function shouldDelayForLimitedOffer(): boolean
	return isLimitedOfferAvailable() and not limitedOfferPresentedThisSession
end

local function updateButtons()
	if not uiReferences then
		return
	end

	local pendingBaseAmount = getPendingBaseAmount(currentStatus)
	local hasPendingReward = pendingBaseAmount > 0
	local play15Active = isPlay15Active(currentStatus)
	local buttonsEnabled = hasPendingReward and not requestInFlight and not purchasePromptActive

	setButtonEnabled(uiReferences.ClaimButton, buttonsEnabled)
	setButtonEnabled(uiReferences.RobuxButton, buttonsEnabled)
	setButtonEnabled(uiReferences.Play15Button, buttonsEnabled and not play15Active)
end

local function syncModalVisibility()
	if not uiReferences then
		return
	end

	local pendingBaseAmount = getPendingBaseAmount(currentStatus)
	local play15Active = isPlay15Active(currentStatus)
	local currentFrameName = FrameManager.getCurrentFrameName()
	local canOpenOffline = pendingBaseAmount > 0
		and not play15Active
		and not shouldDelayForLimitedOffer()
		and currentFrameName ~= LimitedTimeOfferConfiguration.FrameName

	if canOpenOffline then
		FrameManager.open(uiReferences.Frame.Name)
	else
		FrameManager.close(uiReferences.Frame.Name)
	end
end

local function updateProductPrice()
	if not uiReferences or productPriceLoaded then
		return
	end

	local priceLabel = uiReferences.RobuxPriceText
	if not isTextObject(priceLabel) then
		return
	end

	local productId = getConfiguredProductId()
	if productId <= 0 then
		setText(priceLabel, ROBUX_ICON .. "?")
		productPriceLoaded = true
		return
	end

	productPriceLoaded = true
	task.spawn(function()
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)

		if success and info and info.PriceInRobux then
			setText(priceLabel, ROBUX_ICON .. tostring(info.PriceInRobux))
		else
			setText(priceLabel, ROBUX_ICON .. "?")
		end
	end)
end

local function renderStatus(status)
	currentStatus = status
	if not uiReferences then
		return
	end

	local pendingBaseAmount = getPendingBaseAmount(status)
	local boostedAmount = pendingBaseAmount * OfflineIncomeConfiguration.RobuxMultiplier

	setText(uiReferences.MainEarnedText, "+" .. formatAmount(pendingBaseAmount))
	setText(uiReferences.ClaimButtonText, "CLAIM " .. formatAmount(pendingBaseAmount))
	setText(uiReferences.Play15RewardText, "+" .. formatAmount(boostedAmount))
	setText(uiReferences.RobuxRewardText, "+" .. formatAmount(boostedAmount))

	updateProductPrice()
	updateButtons()
	syncModalVisibility()
end

local function requestStatus()
	local success, result = pcall(function()
		return getStatusRemote:InvokeServer()
	end)

	if not success then
		warn("[OfflineIncomeUIController] Failed to request status:", result)
		return
	end

	if type(result) == "table" and result.Success == true then
		renderStatus(result.Status)
	end
end

local function initializeUiReferences(frame: GuiObject): UiReferences?
	local earnedSection = waitForPath(frame, {"MainFrame", "Content", "Earned"}, 5)
	if not earnedSection or not earnedSection:IsA("GuiObject") then
		warnMissing("GUI.Frames.Offline.MainFrame.Content.Earned")
		return nil
	end

	local contentSection = waitForPath(frame, {"MainFrame", "Content"}, 5)
	if not contentSection or not contentSection:IsA("GuiObject") then
		warnMissing("GUI.Frames.Offline.MainFrame.Content")
		return nil
	end

	local claimButtonRoot = waitForPath(earnedSection, {"ClaimButton"}, 5)
	local claimButton = findFirstButton(claimButtonRoot)
	if not claimButton then
		warnMissing("GUI.Frames.Offline.MainFrame.Content.Earned.ClaimButton")
		return nil
	end

	local rightButtons = waitForPath(contentSection, {"right", "Buttons"}, 5)
	if not rightButtons then
		rightButtons = waitForPath(earnedSection, {"right", "Buttons"}, 1)
	end

	local robuxButtonRoot, play15ButtonRoot = resolveRightActionRoots(rightButtons)
	local robuxButton = findFirstButton(robuxButtonRoot)
	local play15Button = findFirstButton(play15ButtonRoot)

	if not robuxButton then
		warnMissing("GUI.Frames.Offline.MainFrame.Content.right.Buttons.(robux claim button)")
		return nil
	end

	if not play15Button then
		warnMissing("GUI.Frames.Offline.MainFrame.Content.right.Buttons.(play15 button)")
		return nil
	end

	disableModalCloseButtons(frame)

	local claimButtonText = findNamedTextDescendant(claimButton, "YouEarned")
	local mainEarnedText = findNamedTextDescendant(earnedSection, "YouEarned", {claimButton, robuxButton, play15Button})
	local robuxRewardText = waitForPath(robuxButton, {"Frame1", "YouEarnedx2"}, 1)
		or findNamedTextDescendant(robuxButton, "YouEarnedx2", {waitForPath(robuxButton, {"Frame2"}, 1)})
	local robuxPriceText = waitForPath(robuxButton, {"Frame2", "YouEarnedx2"}, 1)
		or findNamedTextDescendant(robuxButton, "YouEarnedx2", {waitForPath(robuxButton, {"Frame1"}, 1)})
	local play15RewardText = waitForPath(play15Button, {"YouEarned15min"}, 1)
		or findNamedTextDescendant(play15Button, "YouEarned15min")

	return {
		Frame = frame,
		EarnedSection = earnedSection,
		ClaimButton = claimButton,
		ClaimButtonText = claimButtonText,
		MainEarnedText = mainEarnedText,
		RobuxButton = robuxButton,
		RobuxRewardText = robuxRewardText,
		RobuxPriceText = robuxPriceText,
		Play15Button = play15Button,
		Play15RewardText = play15RewardText,
	}
end

local function bindUi()
	local offlineFrame = frames:FindFirstChild("Offline")
	if not offlineFrame or not offlineFrame:IsA("GuiObject") then
		return false
	end

	if uiReferences then
		return true
	end

	uiReferences = initializeUiReferences(offlineFrame)
	if not uiReferences then
		return false
	end

	uiReferences.ClaimButton.MouseButton1Click:Connect(function()
		if requestInFlight or purchasePromptActive then
			return
		end

		if getPendingBaseAmount(currentStatus) <= 0 then
			return
		end

		requestInFlight = true
		updateButtons()

		local success, result = pcall(function()
			return claimRemote:InvokeServer()
		end)

		requestInFlight = false
		if not success then
			warn("[OfflineIncomeUIController] Claim request failed:", result)
			NotificationManager.show("Offline income is unavailable right now.", "Error")
			updateButtons()
			return
		end

		if type(result) == "table" and result.Status then
			renderStatus(result.Status)
		end

		if type(result) ~= "table" or result.Success ~= true then
			NotificationManager.show("Offline income is unavailable right now.", "Error")
		end
	end)

	uiReferences.Play15Button.MouseButton1Click:Connect(function()
		if requestInFlight or purchasePromptActive then
			return
		end

		if getPendingBaseAmount(currentStatus) <= 0 then
			return
		end

		requestInFlight = true
		updateButtons()

		local success, result = pcall(function()
			return startPlay15Remote:InvokeServer()
		end)

		requestInFlight = false
		if not success then
			warn("[OfflineIncomeUIController] StartPlay15 request failed:", result)
			NotificationManager.show("Play 15 reward is unavailable right now.", "Error")
			updateButtons()
			return
		end

		if type(result) == "table" and result.Status then
			renderStatus(result.Status)
		end

		if type(result) ~= "table" or result.Success ~= true then
			NotificationManager.show("Play 15 reward is unavailable right now.", "Error")
		end
	end)

	uiReferences.RobuxButton.MouseButton1Click:Connect(function()
		if requestInFlight or purchasePromptActive then
			return
		end

		if getPendingBaseAmount(currentStatus) <= 0 then
			return
		end

		local productId = getConfiguredProductId()
		if productId <= 0 then
			NotificationManager.show("Offline income x5 product ID is not configured yet.", "Error")
			return
		end

		purchasePromptActive = true
		updateButtons()

		local success, err = pcall(function()
			MarketplaceService:PromptProductPurchase(localPlayer, productId)
		end)

		if not success then
			purchasePromptActive = false
			updateButtons()
			warn("[OfflineIncomeUIController] Failed to prompt OfflineIncomeX5:", err)
			NotificationManager.show("Purchase prompt is unavailable right now.", "Error")
		end
	end)

	requestStatus()
	return true
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, _wasPurchased)
	if userId ~= localPlayer.UserId then
		return
	end

	if productId ~= getConfiguredProductId() then
		return
	end

	purchasePromptActive = false
	updateButtons()
	requestStatus()
end)

statusUpdatedRemote.OnClientEvent:Connect(function(status)
	purchasePromptActive = false
	requestInFlight = false
	renderStatus(status)
end)

FrameManager.Changed:Connect(function(_isAnyFrameOpen, frameName)
	if not uiReferences then
		return
	end

	if frameName == LimitedTimeOfferConfiguration.FrameName then
		limitedOfferPresentedThisSession = true
		return
	end

	if getPendingBaseAmount(currentStatus) <= 0 then
		return
	end

	if frameName ~= uiReferences.Frame.Name then
		task.defer(syncModalVisibility)
	end
end)

for _, attributeName in ipairs({
	LimitedTimeOfferConfiguration.ReadyAttribute,
	LimitedTimeOfferConfiguration.PurchaseAttribute,
	LimitedTimeOfferConfiguration.StartAttribute,
	LimitedTimeOfferConfiguration.EndAttribute,
	"OnboardingStep",
}) do
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(function()
		task.defer(syncModalVisibility)
	end)
end

frames.ChildAdded:Connect(function(child)
	if child.Name == "Offline" and child:IsA("GuiObject") then
		if bindUi() then
			requestStatus()
		end
	end
end)

if bindUi() then
	requestStatus()
end
