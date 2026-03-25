--!strict
-- LOCATION: StarterPlayerScripts/DailyRewardUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

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
local rewardsGrid = mainFrame:WaitForChild("RewardsGrid") :: ScrollingFrame
local template = rewardsGrid:WaitForChild("Template") :: ImageButton
local buttonsFrame = mainFrame:WaitForChild("Buttons") :: Frame
local skipAllButton = buttonsFrame:WaitForChild("SkipAll") :: ImageButton
local skip1Button = buttonsFrame:WaitForChild("Skip1") :: ImageButton

local dailyRewardsRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DailyRewards")
local getStatusRemote = dailyRewardsRemotes:WaitForChild("GetStatus") :: RemoteFunction
local claimRewardRemote = dailyRewardsRemotes:WaitForChild("ClaimReward") :: RemoteFunction
local statusUpdatedRemote = dailyRewardsRemotes:WaitForChild("StatusUpdated") :: RemoteEvent

local rewardButtons: { [number]: ImageButton } = {}
local currentStatus = nil
local isClaiming = false

local STATE_COLORS = {
	Claim = {
		Background = Color3.fromRGB(0, 200, 0),
		Stroke = Color3.fromRGB(25, 120, 25),
		Text = Color3.fromRGB(255, 255, 255),
	},
	Collected = {
		Background = Color3.fromRGB(100, 100, 100),
		Stroke = Color3.fromRGB(70, 70, 70),
		Text = Color3.fromRGB(255, 255, 255),
	},
	Locked = {
		Background = Color3.fromRGB(255, 255, 255),
		Stroke = Color3.fromRGB(190, 190, 190),
		Text = Color3.fromRGB(255, 255, 255),
	},
}

local STATE_TEXT = {
	Claim = "Claim!",
	Collected = "Collected",
	Locked = "Locked",
}

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

local function getRewardDisplay(reward)
	if reward.Type == "Money" then
		return "$" .. NumberFormatter.Format(reward.Amount), reward.Image or "", false
	end

	if reward.Type == "RandomItemByRarity" then
		local rarity = reward.Rarity or "Unknown"
		return rarity .. " Brainrot", reward.Image or "", true
	end

	if reward.Type == "Pickaxe" then
		return reward.PickaxeName or "Bomb", reward.Image or "", false
	end

	return "Unknown", reward.Image or "", false
end

local function updateButtonVisual(button: ImageButton, reward, state: string)
	local frame = button:WaitForChild("Frame") :: Frame
	local stroke = frame:FindFirstChild("UIStroke") :: UIStroke?
	local rewardAmount = frame:WaitForChild("RewardAmount") :: TextLabel
	local rewardImage = frame:WaitForChild("RewardImage") :: ImageLabel
	local rewardTime = frame:WaitForChild("RewardTime") :: TextLabel
	local claimLabel = frame:WaitForChild("Claim") :: TextLabel
	local checkmark = frame:WaitForChild("Checkmark") :: ImageLabel
	local questionMark = frame:WaitForChild("QuestionMark") :: ImageLabel
	local colors = STATE_COLORS[state]
	local amountText, image, showQuestionMark = getRewardDisplay(reward)

	rewardAmount.Text = amountText
	rewardImage.Image = image
	rewardTime.Text = "Day " .. tostring(reward.Day)
	claimLabel.Text = STATE_TEXT[state]
	checkmark.Visible = state == "Collected"
	questionMark.Visible = showQuestionMark and state ~= "Collected"
	button.AutoButtonColor = state == "Claim"

	frame.BackgroundColor3 = colors.Background
	if stroke then
		stroke.Color = colors.Stroke
	end

	rewardAmount.TextColor3 = colors.Text
	rewardTime.TextColor3 = colors.Text
	claimLabel.TextColor3 = colors.Text
end

local function renderRewards(status)
	if not status then
		return
	end

	currentStatus = status
	updateAlert(status)

	for day, reward in ipairs(status.Rewards) do
		local button = rewardButtons[day]
		if not button then
			button = template:Clone()
			button.Name = tostring(day)
			button.Visible = true
			button.Parent = rewardsGrid
			rewardButtons[day] = button

			button.MouseButton1Click:Connect(function()
				if isClaiming or not currentStatus then
					return
				end

				local state = getButtonState(day, currentStatus)
				if state ~= "Claim" then
					return
				end

				isClaiming = true
				local result = claimRewardRemote:InvokeServer(day)
				isClaiming = false

				if result and result.Status then
					renderRewards(result.Status)
				end

				if not (result and result.Success) then
					NotificationManager.show("Daily reward is not available right now.", "Error")
				end
			end)
		end

		updateButtonVisual(button, reward, getButtonState(day, status))
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
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end

skipAllButton.MouseButton1Click:Connect(function()
	promptDailyRewardProduct("DailyRewardsSkipAll", "Daily Rewards Skip All product ID is not configured yet.")
end)

skip1Button.MouseButton1Click:Connect(function()
	promptDailyRewardProduct("DailyRewardsSkip1", "Daily Rewards Skip 1 product ID is not configured yet.")
end)

template.Visible = false
updateAlert(nil)
requestInitialStatus()
statusUpdatedRemote.OnClientEvent:Connect(function(status)
	renderRewards(status)
end)
