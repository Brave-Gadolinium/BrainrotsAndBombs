--!strict
-- LOCATION: StarterPlayerScripts/PlaytimeRewardUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")
local frames = gui:WaitForChild("Frames")

local openButton = hud:WaitForChild("Left"):WaitForChild("Buttons1"):WaitForChild("PlaytimeRewards") :: TextButton
local alert = openButton:WaitForChild("Alert") :: ImageLabel
local alertLabel = alert:WaitForChild("TimerLabel") :: TextLabel
local timerLabel = openButton:WaitForChild("Timer") :: TextLabel

local playtimeRewardsFrame = frames:WaitForChild("PlaytimeRewards") :: Frame
local mainFrame = playtimeRewardsFrame:WaitForChild("MainFrame") :: Frame
local rewardsGrid = mainFrame:WaitForChild("RewardsGrid") :: ScrollingFrame
local template = rewardsGrid:WaitForChild("Template") :: ImageButton
local openAllButton = mainFrame:WaitForChild("OpenAll") :: ImageButton
local speedX2Button = mainFrame:WaitForChild("Speedx2") :: ImageButton
local speedX5Button = mainFrame:WaitForChild("Speedx5") :: ImageButton

local playtimeRewardsRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlaytimeRewards")
local getStatusRemote = playtimeRewardsRemotes:WaitForChild("GetStatus") :: RemoteFunction
local claimRewardRemote = playtimeRewardsRemotes:WaitForChild("ClaimReward") :: RemoteFunction
local statusUpdatedRemote = playtimeRewardsRemotes:WaitForChild("StatusUpdated") :: RemoteEvent

local rewardButtons: { [number]: ImageButton } = {}
local rewardCountdowns: { [number]: number } = {}
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

local function formatTime(totalSeconds: number): string
	totalSeconds = math.max(0, math.floor(totalSeconds))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("%02d:%02d", minutes, seconds)
end

local function getRewardAmountText(reward): string
	if reward.Type == "Money" then
		return "$" .. NumberFormatter.Format(reward.Amount or 0)
	end

	if reward.Type == "LuckyBlock" then
		return reward.DisplayName or "Lucky Block"
	end

	return reward.DisplayName or reward.Type or "Reward"
end

local function isClaimableReward(rewardId: number, status): boolean
	for _, claimableRewardId in ipairs(status.ClaimableRewardIds or {}) do
		if claimableRewardId == rewardId then
			return true
		end
	end
	return false
end

local function getButtonState(rewardId: number, status): string
	if status.ClaimedRewards and status.ClaimedRewards[rewardId] then
		return "Collected"
	end

	if isClaimableReward(rewardId, status) then
		return "Claim"
	end

	return "Locked"
end

local function updateHeader(status)
	if not status then
		alert.Visible = false
		alertLabel.Text = ""
		timerLabel.Text = "00:00"
		return
	end

	local claimableCount = #(status.ClaimableRewardIds or {})
	if claimableCount > 0 then
		alert.Visible = true
		alertLabel.Text = "Claim!"
		timerLabel.Text = "Claim!"
		return
	end

	alert.Visible = false
	alertLabel.Text = ""

	if status.NextRewardId then
		timerLabel.Text = formatTime(status.SecondsUntilNextReward or 0)
	else
		timerLabel.Text = "Completed"
	end
end

local function getCurrentSpeedMultiplier(): number
	if currentStatus and type(currentStatus.SpeedMultiplier) == "number" then
		return math.max(1, currentStatus.SpeedMultiplier)
	end

	local attributeMultiplier = player:GetAttribute("PlaytimeRewardSpeedMultiplier")
	if type(attributeMultiplier) == "number" then
		return math.max(1, attributeMultiplier)
	end

	return 1
end

local function updateSpeedButtons()
	local hasSpeedX2 = player:GetAttribute("PlaytimeRewardHasSpeedX2") == true
	local hasSpeedX5 = player:GetAttribute("PlaytimeRewardHasSpeedX5") == true

	speedX2Button.Visible = not hasSpeedX2
	speedX5Button.Visible = not hasSpeedX5
end

local function updateButtonVisual(button: ImageButton, reward, status)
	local state = getButtonState(reward.Id, status)
	local frame = button:WaitForChild("Frame") :: Frame
	local stroke = frame:FindFirstChild("UIStroke") :: UIStroke?
	local rewardAmount = frame:WaitForChild("RewardAmount") :: TextLabel
	local rewardImage = frame:WaitForChild("ImageLabel") :: ImageLabel
	local rewardTime = frame:WaitForChild("RewardTime") :: TextLabel
	local checkmark = frame:WaitForChild("Checkmark") :: ImageLabel
	local questionMark = frame:WaitForChild("QuestionMark") :: ImageLabel
	local colors = STATE_COLORS[state]

	rewardAmount.Text = getRewardAmountText(reward)
	rewardImage.Image = reward.Image or ""
	checkmark.Visible = state == "Collected"
	questionMark.Visible = false
	button.AutoButtonColor = state == "Claim"

	frame.BackgroundColor3 = colors.Background
	if stroke then
		stroke.Color = colors.Stroke
	end

	rewardAmount.TextColor3 = colors.Text
	rewardTime.TextColor3 = colors.Text

	if state == "Collected" then
		rewardTime.Text = "Collected"
		rewardCountdowns[reward.Id] = 0
	elseif state == "Claim" then
		rewardTime.Text = "Claim!"
		rewardCountdowns[reward.Id] = 0
	else
		local remaining = math.max(0, reward.RequiredSeconds - (status.PlaytimeSeconds or 0))
		rewardTime.Text = formatTime(remaining)
		rewardCountdowns[reward.Id] = remaining
	end
end

local function renderRewards(status)
	if not status then
		return
	end

	currentStatus = status
	updateHeader(status)

	for _, reward in ipairs(status.Rewards) do
		local button = rewardButtons[reward.Id]
		if not button then
			button = template:Clone()
			button.Name = tostring(reward.Id)
			button.Visible = true
			button.LayoutOrder = reward.Id
			button.Parent = rewardsGrid
			rewardButtons[reward.Id] = button

			button.MouseButton1Click:Connect(function()
				if isClaiming or not currentStatus then
					return
				end

				if getButtonState(reward.Id, currentStatus) ~= "Claim" then
					return
				end

				isClaiming = true
				local result = claimRewardRemote:InvokeServer(reward.Id)
				isClaiming = false

				if result and result.Success and result.Status then
					renderRewards(result.Status)
				elseif result and result.Status then
					renderRewards(result.Status)
					NotificationManager.show("Playtime reward is not available right now.", "Error")
				else
					NotificationManager.show("Playtime reward is not available right now.", "Error")
				end
			end)
		end

		updateButtonVisual(button, reward, status)
	end
end

local function requestInitialStatus()
	local result = getStatusRemote:InvokeServer()
	if result and result.Success and result.Status then
		renderRewards(result.Status)
	else
		updateHeader(nil)
	end
end

openAllButton.MouseButton1Click:Connect(function()
	local productId = ProductConfigurations.Products["PlaytimeRewardsSkipAll"]
	if type(productId) ~= "number" or productId <= 0 then
		NotificationManager.show("Playtime Skip All product ID is not configured yet.", "Error")
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end)

speedX2Button.MouseButton1Click:Connect(function()
	local productId = ProductConfigurations.Products["PlaytimeRewardsSpeedX2"]
	if type(productId) ~= "number" or productId <= 0 then
		NotificationManager.show("Playtime x2 Speed product ID is not configured yet.", "Error")
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end)

speedX5Button.MouseButton1Click:Connect(function()
	local productId = ProductConfigurations.Products["PlaytimeRewardsSpeedX5"]
	if type(productId) ~= "number" or productId <= 0 then
		NotificationManager.show("Playtime x5 Speed product ID is not configured yet.", "Error")
		return
	end

	MarketplaceService:PromptProductPurchase(player, productId)
end)

template.Visible = false
updateHeader(nil)
updateSpeedButtons()
requestInitialStatus()

statusUpdatedRemote.OnClientEvent:Connect(function(status)
	renderRewards(status)
	updateSpeedButtons()
end)

player:GetAttributeChangedSignal("PlaytimeRewardHasSpeedX2"):Connect(updateSpeedButtons)
player:GetAttributeChangedSignal("PlaytimeRewardHasSpeedX5"):Connect(updateSpeedButtons)

task.spawn(function()
	while true do
		task.wait(1)
		local speedMultiplier = getCurrentSpeedMultiplier()

		if currentStatus then
			if #(currentStatus.ClaimableRewardIds or {}) == 0 and currentStatus.NextRewardId then
				currentStatus.SecondsUntilNextReward = math.max(0, (currentStatus.SecondsUntilNextReward or 0) - speedMultiplier)
			end
			updateHeader(currentStatus)
		end

		for rewardId, remaining in pairs(rewardCountdowns) do
			if remaining > 0 then
				rewardCountdowns[rewardId] = math.max(0, remaining - speedMultiplier)
				local button = rewardButtons[rewardId]
				if button and currentStatus and getButtonState(rewardId, currentStatus) == "Locked" then
					local rewardTime = (button:WaitForChild("Frame") :: Frame):WaitForChild("RewardTime") :: TextLabel
					rewardTime.Text = formatTime(rewardCountdowns[rewardId])
				end
			end
		end
	end
end)
