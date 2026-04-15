--!strict
-- LOCATION: StarterPlayerScripts/DailyRewardUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)
local LuckyBlockConfiguration = require(ReplicatedStorage.Modules.LuckyBlockConfiguration)
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")
local frames = gui:WaitForChild("Frames")

local openButton = hud:WaitForChild("Left"):WaitForChild("Buttons1"):WaitForChild("DailyRewards") :: TextButton
local alert = openButton:WaitForChild("Alert") :: ImageLabel
local alertLabel = alert:WaitForChild("TimerLabel") :: TextLabel

local dailyRewardsFrame = frames:WaitForChild("DailyRewards") :: Frame
local mainFrame = dailyRewardsFrame:WaitForChild("MainFrame") :: Frame
local titleFrame = dailyRewardsFrame:WaitForChild("Title") :: Frame
local closeButton = titleFrame:WaitForChild("Close") :: ImageButton
local day1To3Frame = mainFrame:WaitForChild("1-3Days") :: Frame
local day4To6Frame = mainFrame:WaitForChild("4-6Days") :: Frame
local day7Frame = mainFrame:WaitForChild("7Day") :: Frame
local openAllButton = mainFrame:WaitForChild("OpenAll") :: ImageButton
local buttonsFrame = mainFrame:WaitForChild("Buttons") :: Frame
local skipAllButton = buttonsFrame:WaitForChild("SkipAll") :: ImageButton
local skip1Button = buttonsFrame:WaitForChild("Skip1") :: ImageButton

local dailyRewardsRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DailyRewards")
local getStatusRemote = dailyRewardsRemotes:WaitForChild("GetStatus") :: RemoteFunction
local claimRewardRemote = dailyRewardsRemotes:WaitForChild("ClaimReward") :: RemoteFunction
local statusUpdatedRemote = dailyRewardsRemotes:WaitForChild("StatusUpdated") :: RemoteEvent
local reportAnalyticsIntent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

type RewardSlot = Frame

local MONEY_IMAGE = "rbxassetid://18209585783"

local rewardSlots: { [number]: RewardSlot } = {}
local currentStatus = nil
local isClaiming = false

local function reportStoreOpened(surface: string)
	reportAnalyticsIntent:FireServer("StoreOpened", {
		surface = surface,
		section = "daily_rewards",
		entrypoint = "frame_open",
	})
end

local function reportStorePromptFailed(productName: string, productId: number?, reason: string)
	reportAnalyticsIntent:FireServer("StorePromptFailed", {
		surface = "daily_rewards",
		section = "daily_rewards",
		entrypoint = "purchase_button",
		productName = productName,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
		reason = reason,
	})
end

local function hasDay(dayMap, day: number): boolean
	if type(dayMap) ~= "table" then
		return false
	end

	return dayMap[day] == true or dayMap[tostring(day)] == true
end

local function getButtonState(day: number, status)
	if hasDay(status.ClaimedRewardDays, day) then
		return "Collected"
	end

	if hasDay(status.AvailableClaimDays, day) then
		return "Claim"
	end

	return "Locked"
end

local function updateAlert(status)
	local canClaim = status and status.CanClaim == true
	alert.Visible = canClaim
	alertLabel.Text = canClaim and "Claim!" or ""
end

local function getOrderedItems(container: Frame): { Frame }
	local indexedItems = {}

	for index, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") and child.Name == "Item" then
			table.insert(indexedItems, {
				Item = child,
				Index = index,
			})
		end
	end

	table.sort(indexedItems, function(a, b)
		if a.Item.LayoutOrder == b.Item.LayoutOrder then
			return a.Index < b.Index
		end

		return a.Item.LayoutOrder < b.Item.LayoutOrder
	end)

	local items = {}
	for _, entry in ipairs(indexedItems) do
		table.insert(items, entry.Item)
	end

	return items
end

local function getRarityStyle(rarity: string?): (string?, Color3?)
	if type(rarity) ~= "string" or rarity == "" then
		return nil, nil
	end

	local rarityKey = rarity
	if rarityKey == "Mythic" then
		rarityKey = "Mythical"
	end

	if rarityKey == "Brainrotgod" then
		return "Brainrot God", Color3.fromRGB(255, 170, 0)
	end

	local rarityConfig = (RarityConfigurations :: any)[rarityKey]
	if rarityConfig then
		return rarityConfig.DisplayName or rarity, rarityConfig.TextColor
	end

	return rarity, Color3.fromRGB(255, 255, 255)
end

local function getRewardDisplay(reward)
	if reward.Type == "Money" then
		return {
			name = "$" .. NumberFormatter.Format(reward.Amount or 0),
			image = MONEY_IMAGE,
			rarityText = nil,
			rarityColor = nil,
		}
	end

	if reward.Type == "RandomItemByRarity" then
		local rarityText, rarityColor = getRarityStyle(reward.Rarity)
		return {
			name = "Brainrot",
			image = reward.Image or "",
			rarityText = rarityText,
			rarityColor = rarityColor,
		}
	end

	if reward.Type == "LuckyBlock" then
		local blockConfig = reward.LuckyBlockId and LuckyBlockConfiguration.GetBlockConfig(reward.LuckyBlockId) or nil
		local rarityText, rarityColor = getRarityStyle(blockConfig and blockConfig.Rarity or reward.Rarity)
		return {
			name = blockConfig and blockConfig.DisplayName or reward.DisplayName or "Lucky Block",
			image = reward.Image or (blockConfig and blockConfig.Image) or "",
			rarityText = rarityText,
			rarityColor = rarityColor,
		}
	end

	if reward.Type == "Pickaxe" then
		local bombConfig = reward.PickaxeName and BombsConfigurations.Bombs[reward.PickaxeName] or nil
		return {
			name = (bombConfig and bombConfig.DisplayName) or reward.PickaxeName or "Bomb",
			image = reward.Image or (bombConfig and bombConfig.ImageId) or "",
			rarityText = nil,
			rarityColor = nil,
		}
	end

	return {
		name = reward.DisplayName or reward.Type or "Unknown",
		image = reward.Image or "",
		rarityText = nil,
		rarityColor = nil,
	}
end

local function updateRewardVisual(item: RewardSlot, reward, state: string)
	local dayLabel = item:WaitForChild("DayLabel") :: TextLabel
	local imageLabel = item:WaitForChild("ImageLabel") :: ImageLabel
	local rewardName = imageLabel:WaitForChild("Name") :: TextLabel
	local rareLabel = item:WaitForChild("Rare") :: TextLabel
	local checkmark = item:WaitForChild("Checkmark") :: Frame
	local claimmark = item:WaitForChild("Claimmark") :: Frame
	local readymark = item:WaitForChild("Readymark") :: Frame
	local display = getRewardDisplay(reward)
	local shouldHideImage = reward.HiddenUntilClaimed == true and state ~= "Collected"

	dayLabel.Text = "Day " .. tostring(reward.Day)
	imageLabel.Image = display.image
	imageLabel.ImageColor3 = if shouldHideImage then Color3.fromRGB(0, 0, 0) else Color3.fromRGB(255, 255, 255)
	rewardName.Text = display.name

	checkmark.Visible = state == "Collected"
	claimmark.Visible = state == "Claim"
	readymark.Visible = state == "Locked"

	if display.rarityText then
		rareLabel.Visible = true
		rareLabel.Text = display.rarityText
		rareLabel.TextColor3 = display.rarityColor or Color3.fromRGB(255, 255, 255)
	else
		rareLabel.Visible = false
	end
end

local function claimReward(day: number)
	if isClaiming or not currentStatus then
		return
	end

	if getButtonState(day, currentStatus) ~= "Claim" then
		return
	end

	isClaiming = true
	local result = claimRewardRemote:InvokeServer(day)
	isClaiming = false

	if result and result.Status then
		currentStatus = result.Status
	end

	if result and result.Success and result.Status then
		return result.Status
	end

	if result and result.Status then
		NotificationManager.show("Daily reward is not available right now.", "Error")
		return result.Status
	end

	NotificationManager.show("Daily reward is not available right now.", "Error")
	return nil
end

local function claimAllAvailableRewards()
	if not currentStatus or isClaiming then
		return
	end

	local availableDays = {}
	for _, reward in ipairs(currentStatus.Rewards or {}) do
		if getButtonState(reward.Day, currentStatus) == "Claim" then
			table.insert(availableDays, reward.Day)
		end
	end

	table.sort(availableDays)

	local latestStatus = currentStatus
	for _, day in ipairs(availableDays) do
		local status = claimReward(day)
		if status then
			latestStatus = status
		else
			break
		end
	end

	if latestStatus then
		currentStatus = latestStatus
	end
end

local function renderRewards(status)
	if not status then
		return
	end

	currentStatus = status
	updateAlert(status)

	for _, reward in ipairs(status.Rewards or {}) do
		local item = rewardSlots[reward.Day]
		if item then
			updateRewardVisual(item, reward, getButtonState(reward.Day, status))
		end
	end
end

local function requestInitialStatus()
	local result = getStatusRemote:InvokeServer()
	if result and result.Success and result.Status then
		renderRewards(result.Status)
	else
		updateAlert(nil)
	end
end

local function promptDailyRewardProduct(productKey: string, missingMessage: string)
	local productId = ProductConfigurations.Products[productKey]
	if type(productId) ~= "number" or productId <= 0 then
		NotificationManager.show(missingMessage, "Error")
		reportStorePromptFailed(productKey, productId, "missing_product_id")
		return
	end

	reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
		surface = "daily_rewards",
		section = "daily_rewards",
		entrypoint = "purchase_button",
		productName = productKey,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
	})
	local success, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not success then
		warn("[DailyRewardUIController] Failed to prompt product:", productKey, err)
		reportStorePromptFailed(productKey, productId, "prompt_failed")
		NotificationManager.show("Purchase prompt is unavailable right now.", "Error")
	end
end

local function connectRewardSlot(day: number, item: RewardSlot)
	rewardSlots[day] = item
	item.Active = true

	item.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local status = claimReward(day)
			if status then
				renderRewards(status)
			end
		end
	end)
end

local day1To3Items = getOrderedItems(day1To3Frame)
for index, item in ipairs(day1To3Items) do
	connectRewardSlot(index, item)
end

local day4To6Items = getOrderedItems(day4To6Frame)
for index, item in ipairs(day4To6Items) do
	connectRewardSlot(index + 3, item)
end

local day7Item = day7Frame:WaitForChild("Item") :: Frame
connectRewardSlot(7, day7Item)

openAllButton.MouseButton1Click:Connect(function()
	reportAnalyticsIntent:FireServer("RewardBulkClaimClicked", {
		surface = "daily_rewards",
	})
	claimAllAvailableRewards()
	if currentStatus then
		renderRewards(currentStatus)
	end
end)

closeButton.MouseButton1Click:Connect(function()
	dailyRewardsFrame.Visible = false
end)

skipAllButton.MouseButton1Click:Connect(function()
	promptDailyRewardProduct("DailyRewardsSkipAll", "Daily Rewards Skip All product ID is not configured yet.")
end)

skip1Button.MouseButton1Click:Connect(function()
	promptDailyRewardProduct("DailyRewardsSkip1", "Daily Rewards Skip 1 product ID is not configured yet.")
end)

updateAlert(nil)
requestInitialStatus()

statusUpdatedRemote.OnClientEvent:Connect(function(status)
	renderRewards(status)
end)

dailyRewardsFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if dailyRewardsFrame.Visible then
		reportAnalyticsIntent:FireServer("DailyRewardsOpened")
		reportStoreOpened("daily_rewards")
	end
end)
