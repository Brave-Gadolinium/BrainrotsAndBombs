--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")

local function createStroke(parent: Instance, color: Color3, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function createCorner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function ensureQuestFrame(): Frame
	local existing = hud:FindFirstChild("ChainQuests")
	if existing and existing:IsA("Frame") then
		return existing
	end

	local frame = Instance.new("Frame")
	frame.Name = "Quests"
	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.fromScale(0.02, 0.34)
	frame.Size = UDim2.fromScale(0.2, 0.3)
	frame.BackgroundColor3 = Color3.fromRGB(24, 30, 43)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = hud
	createCorner(frame, 16)
	createStroke(frame, Color3.fromRGB(112, 168, 255), 0.2)

	local title = Instance.new("Frame")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 44)
	title.Position = UDim2.fromOffset(8, 8)
	title.BackgroundTransparency = 1
	title.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TextLabel"
	titleLabel.Size = UDim2.fromScale(1, 1)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Complete quests & claim rewards"
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextScaled = true
	titleLabel.Parent = title

	local list = Instance.new("Frame")
	list.Name = "QuestList"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(8, 56)
	list.Size = UDim2.new(1, -16, 1, -64)
	list.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local template = Instance.new("Frame")
	template.Name = "Template"
	template.Visible = false
	template.Size = UDim2.new(1, 0, 0, 56)
	template.BackgroundColor3 = Color3.fromRGB(35, 43, 60)
	template.BorderSizePixel = 0
	template.Parent = list
	createCorner(template, 12)
	createStroke(template, Color3.fromRGB(84, 98, 130), 0.35)

	local text = Instance.new("TextLabel")
	text.Name = "QuestText"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(12, 0)
	text.Size = UDim2.new(1, -140, 1, 0)
	text.Font = Enum.Font.GothamMedium
	text.Text = "Quest"
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextSize = 16
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = template

	local claimFrame = Instance.new("Frame")
	claimFrame.Name = "ClaimFrame"
	claimFrame.BackgroundTransparency = 1
	claimFrame.AnchorPoint = Vector2.new(1, 0.5)
	claimFrame.Position = UDim2.new(1, -8, 0.5, 0)
	claimFrame.Size = UDim2.fromOffset(112, 40)
	claimFrame.Parent = template

	local collect = Instance.new("TextButton")
	collect.Name = "Collect"
	collect.Size = UDim2.fromScale(1, 1)
	collect.BackgroundColor3 = Color3.fromRGB(66, 191, 110)
	collect.BorderSizePixel = 0
	collect.Text = ""
	collect.Parent = claimFrame
	createCorner(collect, 10)
	createStroke(collect, Color3.fromRGB(39, 116, 67), 0.2)

	local claimText = Instance.new("TextLabel")
	claimText.Name = "TextClaim"
	claimText.BackgroundTransparency = 1
	claimText.Position = UDim2.fromOffset(10, 0)
	claimText.Size = UDim2.new(0.45, 0, 1, 0)
	claimText.Font = Enum.Font.GothamBold
	claimText.Text = "Claim"
	claimText.TextColor3 = Color3.fromRGB(255, 255, 255)
	claimText.TextSize = 14
	claimText.TextXAlignment = Enum.TextXAlignment.Left
	claimText.Parent = collect

	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.BackgroundTransparency = 1
	coin.AnchorPoint = Vector2.new(1, 0.5)
	coin.Position = UDim2.new(1, -8, 0.5, 0)
	coin.Size = UDim2.fromOffset(54, 22)
	coin.Parent = collect

	local rewardAmount = Instance.new("TextLabel")
	rewardAmount.Name = "RewardAmount"
	rewardAmount.BackgroundTransparency = 1
	rewardAmount.Size = UDim2.fromScale(1, 1)
	rewardAmount.Font = Enum.Font.GothamBold
	rewardAmount.Text = "0"
	rewardAmount.TextColor3 = Color3.fromRGB(255, 245, 161)
	rewardAmount.TextSize = 13
	rewardAmount.TextXAlignment = Enum.TextXAlignment.Right
	rewardAmount.Parent = coin

	return frame
end

local questsFrame = ensureQuestFrame()

local remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("QuestChain")
local getStateRemote = remotes:WaitForChild("GetState") :: RemoteFunction
local claimQuestRemote = remotes:WaitForChild("ClaimQuest") :: RemoteFunction
local stateUpdatedRemote = remotes:WaitForChild("StateUpdated") :: RemoteEvent

local questList = questsFrame:WaitForChild("QuestList") :: Frame
local template = questList:WaitForChild("Template") :: Frame

local HOVER_SCALE = 1.03
local CLICK_SCALE = 0.97
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setupButtonAnimation(button: GuiButton)
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "AnimationScale"
		uiScale.Parent = button
	end

	button.MouseEnter:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, {Scale = 1}):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, {Scale = CLICK_SCALE}):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play()
	end)
end

local function clearQuestItems()
	for _, child in ipairs(questList:GetChildren()) do
		if child == template or child:IsA("UIListLayout") then
			continue
		end

		child:Destroy()
	end
end

local renderState

local function formatQuestText(questState): string
	return string.format(
		"%s (%d/%d)",
		questState.uiText or questState.id or "Quest",
		questState.currentProgress or 0,
		questState.targetValue or 0
	)
end

local function renderQuest(questState)
	local questItem = template:Clone()
	questItem.Name = questState.id or "Quest"
	questItem.Visible = true
	questItem.LayoutOrder = questState.order or 0
	questItem.Parent = questList

	local questText = questItem:FindFirstChild("QuestText") :: TextLabel?
	if questText then
		questText.Text = formatQuestText(questState)
	end

	local claimFrame = questItem:FindFirstChild("ClaimFrame") :: Frame?
	local collectButton = claimFrame and claimFrame:FindFirstChild("Collect") :: TextButton?
	local rewardAmount: TextLabel? = nil
	if collectButton then
		local coin = collectButton:FindFirstChild("Coin")
		if coin then
			local rewardAmountLabel = coin:FindFirstChild("RewardAmount")
			if rewardAmountLabel and rewardAmountLabel:IsA("TextLabel") then
				rewardAmount = rewardAmountLabel
			end
		end
	end

	local canClaim = questState.isCompleted == true and questState.isClaimed ~= true
	if claimFrame then
		claimFrame.Visible = canClaim
	end

	if rewardAmount then
		rewardAmount.Text = NumberFormatter.Format(tonumber(questState.rewardValue) or 0)
	end

	if not collectButton then
		return
	end

	collectButton.Visible = canClaim
	collectButton.Active = canClaim
	collectButton.AutoButtonColor = canClaim

	if not canClaim then
		return
	end

	setupButtonAnimation(collectButton)

	collectButton.MouseButton1Click:Connect(function()
		collectButton.Active = false

		local ok, result = pcall(function()
			return claimQuestRemote:InvokeServer(questState.id)
		end)

		if not ok then
			collectButton.Active = true
			NotificationManager.show("Failed to claim quest reward.", "Error")
			return
		end

		if not result or result.Success ~= true then
			collectButton.Active = true
			NotificationManager.show("Quest reward is not available yet.", "Error")
			if result and result.State then
				renderState(result.State)
			end
			return
		end

		if result.State then
			renderState(result.State)
		end
	end)
end

renderState = function(state)
	clearQuestItems()

	if not state or state.enabled == false or not state.active or #state.active == 0 then
		questsFrame.Visible = false
		return
	end

	questsFrame.Visible = true

	for _, questState in ipairs(state.active) do
		renderQuest(questState)
	end
end

template.Visible = false

stateUpdatedRemote.OnClientEvent:Connect(function(state)
	renderState(state)
end)

local ok, initialState = pcall(function()
	return getStateRemote:InvokeServer()
end)

if ok then
	renderState(initialState)
else
	warn("[QuestChainUIController] Failed to fetch initial quest state")
end
