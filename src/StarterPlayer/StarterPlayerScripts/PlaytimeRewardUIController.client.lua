--!strict
-- LOCATION: StarterPlayerScripts/PlaytimeRewardUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local PlaytimeRewardConfiguration = require(ReplicatedStorage.Modules.PlaytimeRewardConfiguration)
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
local reportAnalyticsIntent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local rewardDefinitions = PlaytimeRewardConfiguration.Rewards
local rewardButtons: { [number]: ImageButton } = {}
local rewardCountdowns: { [number]: number } = {}
local currentStatus = nil
local hasAuthoritativeStatus = false
local isClaiming = false
local statusRequestGeneration = 0
local rewardsGridLayout: UIGridLayout | UIListLayout? = nil
local loggedMissingRewardCardView = false

local INITIAL_STATUS_RETRY_DELAYS = {0, 0.5, 1, 2}
local REOPEN_STATUS_RETRY_DELAYS = {0, 0.25, 0.75}
local CLAIM_STATUS_RETRY_DELAYS = {0, 0.5, 1}

type RewardCardView = {
	Container: GuiObject,
	RewardAmount: TextLabel?,
	RewardImage: ImageLabel?,
	RewardTime: TextLabel?,
	Checkmark: GuiObject?,
	QuestionMark: GuiObject?,
	Stroke: UIStroke?,
}

local function reportStoreOpened(surface: string)
	reportAnalyticsIntent:FireServer("StoreOpened", {
		surface = surface,
		section = "playtime_rewards",
		entrypoint = "frame_open",
	})
end

local function reportStorePromptFailed(productName: string, productId: number?, reason: string)
	reportAnalyticsIntent:FireServer("StorePromptFailed", {
		surface = "playtime_rewards",
		section = "playtime_rewards",
		entrypoint = "purchase_button",
		productName = productName,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
		reason = reason,
	})
end

local function promptPlaytimeProduct(productName: string, missingMessage: string)
	local productId = ProductConfigurations.Products[productName]
	if type(productId) ~= "number" or productId <= 0 then
		NotificationManager.show(missingMessage, "Error")
		reportStorePromptFailed(productName, productId, "missing_product_id")
		return
	end

	reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
		surface = "playtime_rewards",
		section = "playtime_rewards",
		entrypoint = "purchase_button",
		productName = productName,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
	})
	local success, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not success then
		warn("[PlaytimeRewardUIController] Failed to prompt product:", productName, err)
		reportStorePromptFailed(productName, productId, "prompt_failed")
		NotificationManager.show("Purchase prompt is unavailable right now.", "Error")
	end
end

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

local function findFirstDescendantByClass(root: Instance, className: string): Instance?
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.ClassName == className then
			return descendant
		end
	end

	return nil
end

local function ensureRewardsGridLayout(): UIGridLayout | UIListLayout
	if rewardsGridLayout and rewardsGridLayout.Parent == rewardsGrid then
		return rewardsGridLayout
	end

	local existingGrid = rewardsGrid:FindFirstChildWhichIsA("UIGridLayout")
	if existingGrid then
		rewardsGridLayout = existingGrid
		return existingGrid
	end

	local existingList = rewardsGrid:FindFirstChildWhichIsA("UIListLayout")
	if existingList then
		rewardsGridLayout = existingList
		return existingList
	end

	local fallbackLayout = Instance.new("UIListLayout")
	fallbackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	fallbackLayout.FillDirection = Enum.FillDirection.Horizontal
	fallbackLayout.Padding = UDim.new(0, 12)
	fallbackLayout.Parent = rewardsGrid
	rewardsGridLayout = fallbackLayout
	return fallbackLayout
end

local function updateRewardsGridCanvas()
	local layout = ensureRewardsGridLayout()
	local contentSize = layout.AbsoluteContentSize
	rewardsGrid.AutomaticCanvasSize = Enum.AutomaticSize.None
	rewardsGrid.CanvasSize = UDim2.fromOffset(
		math.max(contentSize.X + 12, rewardsGrid.AbsoluteSize.X),
		math.max(contentSize.Y + 12, rewardsGrid.AbsoluteSize.Y)
	)
end

local function bindRewardsGridCanvas()
	local layout = ensureRewardsGridLayout()
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateRewardsGridCanvas)
	rewardsGrid:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateRewardsGridCanvas)
	updateRewardsGridCanvas()
end

local function resolveRewardCardView(button: ImageButton): RewardCardView?
	local container = button:FindFirstChild("Frame")
	if not container or not container:IsA("GuiObject") then
		container = button
	end

	local rewardAmount = container:FindFirstChild("RewardAmount", true)
	local rewardImage = container:FindFirstChild("ImageLabel", true)
	local rewardTime = container:FindFirstChild("RewardTime", true)
	local checkmark = container:FindFirstChild("Checkmark", true)
	local questionMark = container:FindFirstChild("QuestionMark", true)
	local stroke = findFirstDescendantByClass(container, "UIStroke")

	if not rewardAmount or not rewardAmount:IsA("TextLabel")
		or not rewardImage or not rewardImage:IsA("ImageLabel")
		or not rewardTime or not rewardTime:IsA("TextLabel")
	then
		if not loggedMissingRewardCardView then
			loggedMissingRewardCardView = true
			warn("[PlaytimeRewardUIController] Reward card template is missing expected descendants; using partial rendering fallback.")
		end
	end

	return {
		Container = container,
		RewardAmount = if rewardAmount and rewardAmount:IsA("TextLabel") then rewardAmount else nil,
		RewardImage = if rewardImage and rewardImage:IsA("ImageLabel") then rewardImage else nil,
		RewardTime = if rewardTime and rewardTime:IsA("TextLabel") then rewardTime else nil,
		Checkmark = if checkmark and checkmark:IsA("GuiObject") then checkmark else nil,
		QuestionMark = if questionMark and questionMark:IsA("GuiObject") then questionMark else nil,
		Stroke = if stroke and stroke:IsA("UIStroke") then stroke else nil,
	}
end

local function getRewardAmountText(reward): string
	if reward.Type == "Money" then
		return "$" .. NumberFormatter.Format(reward.Amount or 0)
	end

	if reward.Type == "LuckyBlock" then
		return ""
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

local function buildFallbackStatus()
	local playtimeSeconds = math.max(0, tonumber(player:GetAttribute("PlaytimeRewardSeconds")) or 0)
	local claimableCountHint = math.max(0, tonumber(player:GetAttribute("PlaytimeRewardClaimableCount")) or 0)
	local claimableRewardIds = {}
	local nextRewardId = nil
	local secondsUntilNextReward = 0

	for _, reward in ipairs(rewardDefinitions) do
		if playtimeSeconds >= reward.RequiredSeconds then
			if claimableCountHint > 0 then
				table.insert(claimableRewardIds, reward.Id)
			end
		elseif nextRewardId == nil then
			nextRewardId = reward.Id
			secondsUntilNextReward = reward.RequiredSeconds - playtimeSeconds
		end
	end

	return {
		DayKey = tonumber(player:GetAttribute("PlaytimeRewardDayKey")) or 0,
		PlaytimeSeconds = playtimeSeconds,
		ClaimedRewards = {},
		ClaimableRewardIds = claimableRewardIds,
		NextRewardId = nextRewardId,
		SecondsUntilNextReward = math.max(0, secondsUntilNextReward),
		Rewards = rewardDefinitions,
		HasSpeedX2 = player:GetAttribute("PlaytimeRewardHasSpeedX2") == true,
		HasSpeedX5 = player:GetAttribute("PlaytimeRewardHasSpeedX5") == true,
		SpeedMultiplier = getCurrentSpeedMultiplier(),
	}
end

local function invalidatePendingStatusRequests()
	statusRequestGeneration += 1
end

local function updateSpeedButtons()
	local hasSpeedX2 = player:GetAttribute("PlaytimeRewardHasSpeedX2") == true
	local hasSpeedX5 = player:GetAttribute("PlaytimeRewardHasSpeedX5") == true

	speedX2Button.Visible = not hasSpeedX2
	speedX5Button.Visible = not hasSpeedX5
end

local renderRewards

local function fetchStatus()
	local ok, result = pcall(function()
		return getStatusRemote:InvokeServer()
	end)
	if not ok then
		warn("[PlaytimeRewardUIController] Failed to request status:", result)
		return nil
	end

	if result and result.Success and result.Status then
		return result.Status
	end

	if result then
		warn("[PlaytimeRewardUIController] Status request returned an invalid payload:", result.Error or "Unknown")
	end

	return nil
end

local function requestStatusWithRetry(retryDelays: {number})
	invalidatePendingStatusRequests()
	local generation = statusRequestGeneration

	task.spawn(function()
		for _, delaySeconds in ipairs(retryDelays) do
			if delaySeconds > 0 then
				task.wait(delaySeconds)
			end

			if generation ~= statusRequestGeneration then
				return
			end

			local status = fetchStatus()
			if status then
				if generation == statusRequestGeneration then
					renderRewards(status, true)
					updateSpeedButtons()
				end
				return
			end
		end

		if generation == statusRequestGeneration then
			renderRewards(nil, false)
			updateSpeedButtons()
		end
	end)
end

local function updateButtonVisual(button: ImageButton, reward, status)
	local state = getButtonState(reward.Id, status)
	local cardView = resolveRewardCardView(button)
	local colors = STATE_COLORS[state]

	if not cardView then
		return
	end

	if cardView.RewardAmount then
		cardView.RewardAmount.Text = getRewardAmountText(reward)
		cardView.RewardAmount.TextColor3 = colors.Text
	end

	if cardView.RewardImage then
		cardView.RewardImage.Image = reward.Image or ""
	end

	if cardView.Checkmark then
		cardView.Checkmark.Visible = state == "Collected"
	end
	if cardView.QuestionMark then
		cardView.QuestionMark.Visible = false
	end

	button.AutoButtonColor = state == "Claim"

	cardView.Container.BackgroundColor3 = colors.Background
	if cardView.Stroke then
		cardView.Stroke.Color = colors.Stroke
	end

	if state == "Collected" then
		if cardView.RewardTime then
			cardView.RewardTime.Text = "Collected"
			cardView.RewardTime.TextColor3 = colors.Text
		end
		rewardCountdowns[reward.Id] = 0
	elseif state == "Claim" then
		if cardView.RewardTime then
			cardView.RewardTime.Text = "Claim!"
			cardView.RewardTime.TextColor3 = colors.Text
		end
		rewardCountdowns[reward.Id] = 0
	else
		local remaining = math.max(0, reward.RequiredSeconds - (status.PlaytimeSeconds or 0))
		if cardView.RewardTime then
			cardView.RewardTime.Text = formatTime(remaining)
			cardView.RewardTime.TextColor3 = colors.Text
		end
		rewardCountdowns[reward.Id] = remaining
	end
end

renderRewards = function(status, isAuthoritative: boolean?)
	if not status and hasAuthoritativeStatus then
		return
	end

	if status then
		hasAuthoritativeStatus = isAuthoritative ~= false
	end

	local resolvedStatus = status or buildFallbackStatus()
	currentStatus = resolvedStatus
	updateHeader(resolvedStatus)

	for _, reward in ipairs(rewardDefinitions) do
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
				local ok, result = pcall(function()
					return claimRewardRemote:InvokeServer(reward.Id)
				end)
				isClaiming = false

				if not ok then
					warn("[PlaytimeRewardUIController] Claim request failed:", result)
					NotificationManager.show("Playtime reward is not available right now.", "Error")
					requestStatusWithRetry(CLAIM_STATUS_RETRY_DELAYS)
					return
				end

				if result and result.Status then
					renderRewards(result.Status, true)
				end

				if result and result.Success and result.Status then
					return
				end

				NotificationManager.show("Playtime reward is not available right now.", "Error")
				if not result or not result.Status then
					requestStatusWithRetry(CLAIM_STATUS_RETRY_DELAYS)
				end
			end)
		end

		updateButtonVisual(button, reward, resolvedStatus)
	end

	updateRewardsGridCanvas()
end

template.Visible = false
bindRewardsGridCanvas()
updateSpeedButtons()
renderRewards(nil, false)
requestStatusWithRetry(INITIAL_STATUS_RETRY_DELAYS)

openAllButton.MouseButton1Click:Connect(function()
	reportAnalyticsIntent:FireServer("RewardBulkClaimClicked", {
		surface = "playtime_rewards",
	})
	promptPlaytimeProduct("PlaytimeRewardsSkipAll", "Playtime Skip All product ID is not configured yet.")
end)

speedX2Button.MouseButton1Click:Connect(function()
	promptPlaytimeProduct("PlaytimeRewardsSpeedX2", "Playtime x2 Speed product ID is not configured yet.")
end)

speedX5Button.MouseButton1Click:Connect(function()
	promptPlaytimeProduct("PlaytimeRewardsSpeedX5", "Playtime x5 Speed product ID is not configured yet.")
end)

statusUpdatedRemote.OnClientEvent:Connect(function(status)
	invalidatePendingStatusRequests()
	renderRewards(status, true)
	updateSpeedButtons()
end)

player:GetAttributeChangedSignal("PlaytimeRewardHasSpeedX2"):Connect(updateSpeedButtons)
player:GetAttributeChangedSignal("PlaytimeRewardHasSpeedX5"):Connect(updateSpeedButtons)

for _, attributeName in ipairs({
	"PlaytimeRewardDayKey",
	"PlaytimeRewardSeconds",
	"PlaytimeRewardNextId",
	"PlaytimeRewardSecondsUntilNext",
	"PlaytimeRewardClaimableCount",
	"PlaytimeRewardSpeedMultiplier",
}) do
	player:GetAttributeChangedSignal(attributeName):Connect(function()
		if not hasAuthoritativeStatus then
			renderRewards(nil, false)
		end
	end)
end

playtimeRewardsFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if playtimeRewardsFrame.Visible then
		reportAnalyticsIntent:FireServer("PlaytimeRewardsOpened")
		reportStoreOpened("playtime_rewards")
		requestStatusWithRetry(REOPEN_STATUS_RETRY_DELAYS)
	end
end)

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
					local cardView = resolveRewardCardView(button)
					if cardView and cardView.RewardTime then
						cardView.RewardTime.Text = formatTime(rewardCountdowns[rewardId])
					end
				end
			end
		end
	end
end)
