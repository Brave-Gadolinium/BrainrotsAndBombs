--!strict
-- LOCATION: StarterPlayerScripts/ManualTestUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("GUI")
local framesContainer = mainGui:WaitForChild("Frames")
local hud = mainGui:WaitForChild("HUD")
local events = ReplicatedStorage:WaitForChild("Events")
local testManagerFolder = events:WaitForChild("TestManager", 15)

if not testManagerFolder then
	return
end

local GetBootstrap = testManagerFolder:WaitForChild("GetBootstrap") :: RemoteFunction
local GetTargetSnapshot = testManagerFolder:WaitForChild("GetTargetSnapshot") :: RemoteFunction
local ExecuteAction = testManagerFolder:WaitForChild("ExecuteAction") :: RemoteFunction

local THEME = {
	background = Color3.fromRGB(18, 23, 28),
	panel = Color3.fromRGB(26, 33, 40),
	panelAlt = Color3.fromRGB(33, 41, 50),
	panelSoft = Color3.fromRGB(40, 49, 58),
	accent = Color3.fromRGB(255, 162, 58),
	accentDim = Color3.fromRGB(168, 106, 33),
	text = Color3.fromRGB(247, 249, 251),
	muted = Color3.fromRGB(169, 178, 189),
	danger = Color3.fromRGB(214, 92, 92),
	success = Color3.fromRGB(94, 196, 122),
	stroke = Color3.fromRGB(83, 94, 106),
}

local CATEGORY_ORDER = {
	["Economy"] = 1,
	["Inventory"] = 2,
	["Progression"] = 3,
	["Rewards"] = 4,
	["World / QA"] = 5,
	["Danger"] = 6,
}

local SNAPSHOT_FIELDS = {
	{ key = "Money", label = "Money" },
	{ key = "TotalMoneyEarned", label = "Total Money Earned" },
	{ key = "Spins", label = "Spins" },
	{ key = "FreeSpinRemaining", label = "Free Spin In" },
	{ key = "Rebirths", label = "Rebirths" },
	{ key = "UnlockedSlots", label = "Unlocked Slots" },
	{ key = "EquippedPickaxe", label = "Equipped Pickaxe" },
	{ key = "OwnedPickaxesCount", label = "Owned Pickaxes" },
	{ key = "InventoryCount", label = "Inventory Count" },
	{ key = "LuckyBlockCount", label = "Lucky Blocks" },
	{ key = "TotalBrainrotsCollected", label = "Brainrots Collected" },
	{ key = "TimePlayed", label = "Time Played" },
	{ key = "OnboardingStep", label = "Onboarding Step" },
	{ key = "PostTutorialStage", label = "Post Tutorial Stage" },
	{ key = "MaxDepthLevelReached", label = "Max Depth" },
	{ key = "GroupRewardClaimed", label = "Group Reward Claimed" },
	{ key = "DailyRewardClaimDay", label = "Daily Claim Day" },
	{ key = "DailyRewardCanClaim", label = "Daily Claim Ready" },
	{ key = "DailyRewardClaimedToday", label = "Daily Claimed Today" },
	{ key = "PlaytimeSeconds", label = "Playtime Seconds" },
	{ key = "PlaytimeClaimableCount", label = "Playtime Claimable" },
	{ key = "PlaytimeNextRewardId", label = "Playtime Next Reward" },
	{ key = "PlaytimeSpeedMultiplier", label = "Playtime Speed" },
}

local bootstrapData = nil
local actions = {}
local actionsById = {}
local targets = {}
local targetsByUserId = {}
local categories = {}
local selectedCategory = nil
local selectedTargetUserId = player.UserId
local accessLevel = "none"
local actionStates = {}
local latestSnapshot = nil
local pollToken = 0

local rootFrame: Frame? = nil
local headerFrame: Frame? = nil
local bodyFrame: Frame? = nil
local leftTabsScroll: ScrollingFrame? = nil
local leftTabsContent: Frame? = nil
local topTabsScroll: ScrollingFrame? = nil
local topTabsContent: Frame? = nil
local actionsPane: Frame? = nil
local actionsScroll: ScrollingFrame? = nil
local actionsContent: Frame? = nil
local snapshotPane: Frame? = nil
local snapshotScroll: ScrollingFrame? = nil
local snapshotContent: Frame? = nil
local accessBadge: TextLabel? = nil
local targetButton: TextButton? = nil
local targetDropdown: Frame? = nil
local targetDropdownScroll: ScrollingFrame? = nil
local targetDropdownContent: Frame? = nil
local refreshButton: TextButton? = nil
local closeButton: TextButton? = nil
local searchBox: TextBox? = nil
local hudToggleButton: TextButton? = nil

local renderActions
local renderSnapshot
local renderTargetDropdown
local renderTabs
local refreshAllUI

local function invokeRemote(remote: RemoteFunction, payload)
	local success, result = pcall(function()
		return remote:InvokeServer(payload)
	end)

	if not success then
		return nil, tostring(result)
	end

	return result, nil
end

local function createCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createStroke(parent: Instance, color: Color3, transparency: number?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

local function bindCanvasSize(scroll: ScrollingFrame, layout: UIListLayout | UIGridLayout, axis: "Y" | "X")
	local function updateCanvas()
		if axis == "X" then
			scroll.CanvasSize = UDim2.fromOffset(layout.AbsoluteContentSize.X + 8, 0)
		else
			scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
		end
	end

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
	updateCanvas()
end

local function clearContainer(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

local function createLabel(parent: Instance, text: string, size: number, color: Color3?, bold: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or THEME.text
	label.TextSize = size
	label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 0)
	label.Parent = parent
	return label
end

local function createTextButton(parent: Instance, text: string, backgroundColor: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = backgroundColor or THEME.panelSoft
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = THEME.text
	button.TextSize = 14
	button.Font = Enum.Font.GothamBold
	button.Parent = parent
	createCorner(button, 10)
	createStroke(button, THEME.stroke, 0.2, 1)
	return button
end

local function createTextBox(parent: Instance, placeholder: string): TextBox
	local textBox = Instance.new("TextBox")
	textBox.BackgroundColor3 = THEME.panelSoft
	textBox.BorderSizePixel = 0
	textBox.ClearTextOnFocus = false
	textBox.PlaceholderText = placeholder
	textBox.PlaceholderColor3 = THEME.muted
	textBox.TextColor3 = THEME.text
	textBox.TextSize = 14
	textBox.Font = Enum.Font.Gotham
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.Parent = parent
	createCorner(textBox, 10)
	createStroke(textBox, THEME.stroke, 0.2, 1)
	return textBox
end

local function getActionState(actionId: string)
	local state = actionStates[actionId]
	if state then
		return state
	end

	state = {}
	actionStates[actionId] = state
	return state
end

local function sortCategories(inputCategories)
	table.sort(inputCategories, function(a, b)
		local orderA = CATEGORY_ORDER[a] or math.huge
		local orderB = CATEGORY_ORDER[b] or math.huge
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a < b
	end)
	return inputCategories
end

local function formatValue(value)
	if type(value) == "boolean" then
		return value and "Yes" or "No"
	end
	if type(value) == "number" then
		if math.abs(value) >= 1000 then
			return tostring(math.floor(value))
		end
		return tostring(value)
	end
	if value == nil then
		return "-"
	end
	return tostring(value)
end

local function formatSeconds(seconds: number?): string
	local total = math.max(0, math.floor(seconds or 0))
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local secs = total % 60
	if hours > 0 then
		return string.format("%dh %dm %ds", hours, minutes, secs)
	end
	if minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

local function getOptionLabel(options, value)
	for _, option in ipairs(options or {}) do
		if option.value == value then
			return option.label
		end
	end
	return tostring(value)
end

local function applyBootstrap(result)
	bootstrapData = result
	actions = result.Actions or {}
	actionsById = {}
	for _, action in ipairs(actions) do
		actionsById[action.id] = action
	end

	targets = result.Targets or {}
	targetsByUserId = {}
	for _, target in ipairs(targets) do
		targetsByUserId[target.UserId] = target
	end

	accessLevel = result.AccessLevel or "none"
	local discoveredCategories = {}
	for _, action in ipairs(actions) do
		if type(action.category) == "string" then
			discoveredCategories[action.category] = true
		end
	end

	local nextCategories = {}
	for categoryName in pairs(discoveredCategories) do
		table.insert(nextCategories, categoryName)
	end
	categories = sortCategories(nextCategories)

	if not selectedCategory or not table.find(categories, selectedCategory) then
		selectedCategory = categories[1]
	end

	if not targetsByUserId[selectedTargetUserId] then
		selectedTargetUserId = targets[1] and targets[1].UserId or player.UserId
	end

	latestSnapshot = result.Snapshot
end

local function requestBootstrap()
	local result, err = invokeRemote(GetBootstrap, nil)
	if not result then
		NotificationManager.show(err or "Failed to load test manager bootstrap.", "Error")
		return false
	end

	if result.Allowed ~= true then
		return false
	end

	applyBootstrap(result)
	return true
end

local function requestSnapshot()
	if not rootFrame or not rootFrame.Visible then
		return
	end

	local result, err = invokeRemote(GetTargetSnapshot, selectedTargetUserId)
	if not result then
		NotificationManager.show(err or "Failed to refresh snapshot.", "Error")
		return
	end

	if result.Success ~= true then
		latestSnapshot = nil
		if renderSnapshot then
			renderSnapshot()
		end
		NotificationManager.show(result.Error or "Failed to refresh snapshot.", "Error")
		return
	end

	latestSnapshot = result.Snapshot
	if renderSnapshot then
		renderSnapshot()
	end
end

local function updateTargetButtonText()
	if not targetButton then
		return
	end

	local target = targetsByUserId[selectedTargetUserId]
	if target then
		targetButton.Text = `Target: {target.Name}`
	else
		targetButton.Text = "Target: Self"
	end
end

local function stopPolling()
	pollToken += 1
end

local function startPolling()
	stopPolling()
	pollToken += 1
	local token = pollToken

	task.spawn(function()
		while rootFrame and rootFrame.Visible and token == pollToken do
			requestSnapshot()
			task.wait(2)
		end
	end)
end

local function toggleFrame()
	if not rootFrame then
		return
	end

	if rootFrame.Visible then
		FrameManager.close("TestManager")
	else
		if requestBootstrap() then
			refreshAllUI()
			FrameManager.open("TestManager")
		end
	end
end

local function buildHudToggle()
	if hudToggleButton and hudToggleButton.Parent then
		return
	end

	local button = createTextButton(hud, "TEST", THEME.accentDim)
	button.Name = "ManualTestToggle"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -18, 0, 18)
	button.Size = UDim2.fromOffset(76, 34)
	button.BackgroundColor3 = Color3.fromRGB(89, 58, 18)
	button.TextColor3 = THEME.accent
	button.MouseButton1Click:Connect(toggleFrame)

	hudToggleButton = button
end

local function updateLayout()
	if not rootFrame
		or not headerFrame
		or not bodyFrame
		or not leftTabsScroll
		or not topTabsScroll
		or not actionsPane
		or not snapshotPane
		or not accessBadge
		or not targetButton
		or not refreshButton
		or not closeButton
		or not searchBox
	then
		return
	end

	local width = rootFrame.AbsoluteSize.X

	if width >= 1200 then
		headerFrame.Size = UDim2.new(1, -24, 0, 60)
		bodyFrame.Position = UDim2.new(0, 0, 0, 72)
		bodyFrame.Size = UDim2.new(1, 0, 1, -72)

		accessBadge.Position = UDim2.new(0, 0, 0, 0)
		accessBadge.Size = UDim2.fromOffset(110, 40)

		targetButton.Position = UDim2.new(0, 122, 0, 0)
		targetButton.Size = UDim2.fromOffset(180, 40)

		searchBox.Position = UDim2.new(0, 314, 0, 0)
		searchBox.Size = UDim2.new(1, -526, 0, 40)

		refreshButton.AnchorPoint = Vector2.new(1, 0)
		refreshButton.Position = UDim2.new(1, -106, 0, 0)
		refreshButton.Size = UDim2.fromOffset(92, 40)

		closeButton.AnchorPoint = Vector2.new(1, 0)
		closeButton.Position = UDim2.new(1, 0, 0, 0)
		closeButton.Size = UDim2.fromOffset(92, 40)

		if targetDropdown then
			targetDropdown.Position = UDim2.new(0, 122, 0, 46)
			targetDropdown.Size = UDim2.fromOffset(240, 220)
		end

		leftTabsScroll.Visible = true
		topTabsScroll.Visible = false

		leftTabsScroll.Position = UDim2.new(0, 16, 0, 16)
		leftTabsScroll.Size = UDim2.new(0, 180, 1, -32)

		actionsPane.Position = UDim2.new(0, 208, 0, 16)
		actionsPane.Size = UDim2.new(1, -512, 1, -32)

		snapshotPane.Position = UDim2.new(1, -288, 0, 16)
		snapshotPane.Size = UDim2.new(0, 272, 1, -32)
		return
	end

	if width >= 760 then
		headerFrame.Size = UDim2.new(1, -24, 0, 112)
		bodyFrame.Position = UDim2.new(0, 0, 0, 124)
		bodyFrame.Size = UDim2.new(1, 0, 1, -124)

		accessBadge.Position = UDim2.new(0, 0, 0, 0)
		accessBadge.Size = UDim2.fromOffset(110, 40)

		targetButton.Position = UDim2.new(0, 122, 0, 0)
		targetButton.Size = UDim2.fromOffset(220, 40)

		refreshButton.AnchorPoint = Vector2.new(1, 0)
		refreshButton.Position = UDim2.new(1, -106, 0, 0)
		refreshButton.Size = UDim2.fromOffset(92, 40)

		closeButton.AnchorPoint = Vector2.new(1, 0)
		closeButton.Position = UDim2.new(1, 0, 0, 0)
		closeButton.Size = UDim2.fromOffset(92, 40)

		searchBox.Position = UDim2.new(0, 0, 0, 54)
		searchBox.Size = UDim2.new(1, 0, 0, 40)

		if targetDropdown then
			targetDropdown.Position = UDim2.new(0, 122, 0, 46)
			targetDropdown.Size = UDim2.fromOffset(300, 220)
		end
	else
		headerFrame.Size = UDim2.new(1, -24, 0, 152)
		bodyFrame.Position = UDim2.new(0, 0, 0, 164)
		bodyFrame.Size = UDim2.new(1, 0, 1, -164)

		accessBadge.Position = UDim2.new(0, 0, 0, 0)
		accessBadge.Size = UDim2.fromOffset(96, 36)

		refreshButton.AnchorPoint = Vector2.new(1, 0)
		refreshButton.Position = UDim2.new(1, -90, 0, 0)
		refreshButton.Size = UDim2.fromOffset(82, 36)

		closeButton.AnchorPoint = Vector2.new(1, 0)
		closeButton.Position = UDim2.new(1, 0, 0, 0)
		closeButton.Size = UDim2.fromOffset(82, 36)

		targetButton.Position = UDim2.new(0, 0, 0, 48)
		targetButton.Size = UDim2.new(1, 0, 0, 38)

		searchBox.Position = UDim2.new(0, 0, 0, 98)
		searchBox.Size = UDim2.new(1, 0, 0, 38)

		if targetDropdown then
			targetDropdown.Position = UDim2.new(0, 0, 0, 90)
			targetDropdown.Size = UDim2.new(1, 0, 0, 220)
		end
	end

	leftTabsScroll.Visible = false
	topTabsScroll.Visible = true

	topTabsScroll.Position = UDim2.new(0, 16, 0, 16)
	topTabsScroll.Size = UDim2.new(1, -32, 0, 44)

	if width >= 760 then
		actionsPane.Position = UDim2.new(0, 16, 0, 72)
		actionsPane.Size = UDim2.new(1, -312, 1, -88)

		snapshotPane.Position = UDim2.new(1, -288, 0, 72)
		snapshotPane.Size = UDim2.new(0, 272, 1, -88)
	else
		actionsPane.Position = UDim2.new(0, 16, 0, 72)
		actionsPane.Size = UDim2.new(1, -32, 0.56, -72)

		snapshotPane.Position = UDim2.new(0, 16, 1, -220)
		snapshotPane.Size = UDim2.new(1, -32, 0, 204)
	end
end

local function buildFrame()
	if rootFrame and rootFrame.Parent then
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "TestManager"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.92, 0.88)
	frame.BackgroundColor3 = THEME.background
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = framesContainer
	createCorner(frame, 18)
	createStroke(frame, THEME.stroke, 0.05, 1.5)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(360, 420)
	sizeConstraint.MaxSize = Vector2.new(1500, 960)
	sizeConstraint.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -24, 0, 60)
	header.Position = UDim2.new(0, 12, 0, 12)
	header.Parent = frame

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 0, 0, 72)
	body.Size = UDim2.new(1, 0, 1, -72)
	body.Parent = frame

	local badge = Instance.new("TextLabel")
	badge.Name = "AccessBadge"
	badge.BackgroundColor3 = THEME.panelSoft
	badge.BorderSizePixel = 0
	badge.Position = UDim2.new(0, 0, 0, 0)
	badge.Size = UDim2.fromOffset(110, 40)
	badge.Text = "TESTER"
	badge.TextColor3 = THEME.text
	badge.TextSize = 14
	badge.Font = Enum.Font.GothamBold
	badge.Parent = header
	createCorner(badge, 12)
	createStroke(badge, THEME.stroke, 0.1, 1)

	local targetSelect = createTextButton(header, "Target: Self", THEME.panel)
	targetSelect.Position = UDim2.new(0, 122, 0, 0)
	targetSelect.Size = UDim2.fromOffset(180, 40)

	local refresh = createTextButton(header, "Refresh", THEME.panel)
	refresh.AnchorPoint = Vector2.new(1, 0)
	refresh.Position = UDim2.new(1, -106, 0, 0)
	refresh.Size = UDim2.fromOffset(92, 40)

	local close = createTextButton(header, "Close", THEME.panel)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(92, 40)

	local queryBox = createTextBox(header, "Search commands")
	queryBox.Position = UDim2.new(0, 314, 0, 0)
	queryBox.Size = UDim2.new(1, -526, 0, 40)

	local dropdown = Instance.new("Frame")
	dropdown.Name = "TargetDropdown"
	dropdown.BackgroundColor3 = THEME.panel
	dropdown.BorderSizePixel = 0
	dropdown.Position = UDim2.new(0, 122, 0, 46)
	dropdown.Size = UDim2.fromOffset(240, 220)
	dropdown.Visible = false
	dropdown.ZIndex = 20
	dropdown.Parent = header
	createCorner(dropdown, 12)
	createStroke(dropdown, THEME.stroke, 0.1, 1)

	local dropdownScrollFrame = Instance.new("ScrollingFrame")
	dropdownScrollFrame.BackgroundTransparency = 1
	dropdownScrollFrame.BorderSizePixel = 0
	dropdownScrollFrame.ScrollBarImageTransparency = 0.4
	dropdownScrollFrame.ScrollBarThickness = 6
	dropdownScrollFrame.ZIndex = 21
	dropdownScrollFrame.Size = UDim2.new(1, -12, 1, -12)
	dropdownScrollFrame.Position = UDim2.new(0, 6, 0, 6)
	dropdownScrollFrame.CanvasSize = UDim2.new()
	dropdownScrollFrame.Parent = dropdown

	local dropdownContentFrame = Instance.new("Frame")
	dropdownContentFrame.BackgroundTransparency = 1
	dropdownContentFrame.ZIndex = 21
	dropdownContentFrame.Size = UDim2.new(1, -4, 0, 0)
	dropdownContentFrame.AutomaticSize = Enum.AutomaticSize.Y
	dropdownContentFrame.Parent = dropdownScrollFrame

	local dropdownLayout = Instance.new("UIListLayout")
	dropdownLayout.Padding = UDim.new(0, 6)
	dropdownLayout.Parent = dropdownContentFrame
	bindCanvasSize(dropdownScrollFrame, dropdownLayout, "Y")

	local leftTabs = Instance.new("ScrollingFrame")
	leftTabs.BackgroundColor3 = THEME.panel
	leftTabs.BorderSizePixel = 0
	leftTabs.ScrollBarThickness = 6
	leftTabs.ScrollBarImageTransparency = 0.45
	leftTabs.Parent = body
	createCorner(leftTabs, 14)
	createStroke(leftTabs, THEME.stroke, 0.18, 1)

	local leftTabsContentFrame = Instance.new("Frame")
	leftTabsContentFrame.BackgroundTransparency = 1
	leftTabsContentFrame.Size = UDim2.new(1, -8, 0, 0)
	leftTabsContentFrame.AutomaticSize = Enum.AutomaticSize.Y
	leftTabsContentFrame.Parent = leftTabs

	local leftLayout = Instance.new("UIListLayout")
	leftLayout.Padding = UDim.new(0, 8)
	leftLayout.Parent = leftTabsContentFrame
	bindCanvasSize(leftTabs, leftLayout, "Y")

	local topTabs = Instance.new("ScrollingFrame")
	topTabs.BackgroundTransparency = 1
	topTabs.BorderSizePixel = 0
	topTabs.ScrollBarThickness = 4
	topTabs.ScrollBarImageTransparency = 0.55
	topTabs.ScrollingDirection = Enum.ScrollingDirection.X
	topTabs.Parent = body

	local topTabsContentFrame = Instance.new("Frame")
	topTabsContentFrame.BackgroundTransparency = 1
	topTabsContentFrame.Size = UDim2.new(0, 0, 1, 0)
	topTabsContentFrame.AutomaticSize = Enum.AutomaticSize.X
	topTabsContentFrame.Parent = topTabs

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.Padding = UDim.new(0, 8)
	topLayout.Parent = topTabsContentFrame
	bindCanvasSize(topTabs, topLayout, "X")

	local actionsPanel = Instance.new("Frame")
	actionsPanel.BackgroundColor3 = THEME.panel
	actionsPanel.BorderSizePixel = 0
	actionsPanel.Parent = body
	createCorner(actionsPanel, 14)
	createStroke(actionsPanel, THEME.stroke, 0.18, 1)

	local actionsScrollFrame = Instance.new("ScrollingFrame")
	actionsScrollFrame.BackgroundTransparency = 1
	actionsScrollFrame.BorderSizePixel = 0
	actionsScrollFrame.ScrollBarThickness = 6
	actionsScrollFrame.ScrollBarImageTransparency = 0.45
	actionsScrollFrame.Size = UDim2.new(1, -12, 1, -12)
	actionsScrollFrame.Position = UDim2.new(0, 6, 0, 6)
	actionsScrollFrame.Parent = actionsPanel

	local actionsContentFrame = Instance.new("Frame")
	actionsContentFrame.BackgroundTransparency = 1
	actionsContentFrame.Size = UDim2.new(1, -6, 0, 0)
	actionsContentFrame.AutomaticSize = Enum.AutomaticSize.Y
	actionsContentFrame.Parent = actionsScrollFrame

	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.Padding = UDim.new(0, 12)
	actionsLayout.Parent = actionsContentFrame
	bindCanvasSize(actionsScrollFrame, actionsLayout, "Y")

	local snapshotPanel = Instance.new("Frame")
	snapshotPanel.BackgroundColor3 = THEME.panel
	snapshotPanel.BorderSizePixel = 0
	snapshotPanel.Parent = body
	createCorner(snapshotPanel, 14)
	createStroke(snapshotPanel, THEME.stroke, 0.18, 1)

	local snapshotScrollFrame = Instance.new("ScrollingFrame")
	snapshotScrollFrame.BackgroundTransparency = 1
	snapshotScrollFrame.BorderSizePixel = 0
	snapshotScrollFrame.ScrollBarThickness = 6
	snapshotScrollFrame.ScrollBarImageTransparency = 0.45
	snapshotScrollFrame.Size = UDim2.new(1, -12, 1, -12)
	snapshotScrollFrame.Position = UDim2.new(0, 6, 0, 6)
	snapshotScrollFrame.Parent = snapshotPanel

	local snapshotContentFrame = Instance.new("Frame")
	snapshotContentFrame.BackgroundTransparency = 1
	snapshotContentFrame.Size = UDim2.new(1, -6, 0, 0)
	snapshotContentFrame.AutomaticSize = Enum.AutomaticSize.Y
	snapshotContentFrame.Parent = snapshotScrollFrame

	local snapshotLayout = Instance.new("UIListLayout")
	snapshotLayout.Padding = UDim.new(0, 8)
	snapshotLayout.Parent = snapshotContentFrame
	bindCanvasSize(snapshotScrollFrame, snapshotLayout, "Y")

	rootFrame = frame
	headerFrame = header
	bodyFrame = body
	accessBadge = badge
	targetButton = targetSelect
	targetDropdown = dropdown
	targetDropdownScroll = dropdownScrollFrame
	targetDropdownContent = dropdownContentFrame
	refreshButton = refresh
	closeButton = close
	searchBox = queryBox
	leftTabsScroll = leftTabs
	leftTabsContent = leftTabsContentFrame
	topTabsScroll = topTabs
	topTabsContent = topTabsContentFrame
	actionsPane = actionsPanel
	actionsScroll = actionsScrollFrame
	actionsContent = actionsContentFrame
	snapshotPane = snapshotPanel
	snapshotScroll = snapshotScrollFrame
	snapshotContent = snapshotContentFrame

	targetSelect.MouseButton1Click:Connect(function()
		if targetDropdown then
			targetDropdown.Visible = not targetDropdown.Visible
		end
	end)

	close.MouseButton1Click:Connect(function()
		FrameManager.close("TestManager")
	end)

	queryBox:GetPropertyChangedSignal("Text"):Connect(function()
		if renderActions then
			renderActions()
		end
	end)

	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if frame.Visible then
			requestSnapshot()
			startPolling()
		else
			if targetDropdown then
				targetDropdown.Visible = false
			end
			stopPolling()
		end
	end)

	updateLayout()
end

local function matchesAction(action, query: string): boolean
	if query == "" then
		return true
	end

	local haystack = string.lower((action.label or "") .. " " .. (action.description or "") .. " " .. (action.id or ""))
	return string.find(haystack, query, 1, true) ~= nil
end

local function resolveSearchValue(inputDef, state)
	local selectedValue = state[inputDef.id]
	if type(selectedValue) == "string" and selectedValue ~= "" then
		return selectedValue
	end

	local query = string.lower((state[inputDef.id .. "_query"] or "")):gsub("^%s+", ""):gsub("%s+$", "")
	if query == "" then
		return inputDef.default
	end

	for _, option in ipairs(inputDef.options or {}) do
		if string.lower(option.value) == query or string.lower(option.label) == query then
			return option.value
		end
	end

	return inputDef.default
end

local function ensureInputDefaults(action)
	local state = getActionState(action.id)
	for _, inputDef in ipairs(action.inputs or {}) do
		if inputDef.kind == "number" or inputDef.kind == "text" then
			if state[inputDef.id .. "_text"] == nil then
				state[inputDef.id .. "_text"] = tostring(inputDef.default or "")
			end
		elseif inputDef.kind == "boolean" then
			if state[inputDef.id] == nil then
				state[inputDef.id] = inputDef.default == true
			end
		elseif inputDef.kind == "search_select" then
			if state[inputDef.id] == nil and inputDef.default ~= nil then
				state[inputDef.id] = inputDef.default
			end
			if state[inputDef.id .. "_query"] == nil then
				state[inputDef.id .. "_query"] = getOptionLabel(inputDef.options, state[inputDef.id] or inputDef.default)
			end
		end
	end
	if state.confirmationText == nil then
		state.confirmationText = ""
	end
end

renderTargetDropdown = function()
	if not targetDropdownContent then
		return
	end

	clearContainer(targetDropdownContent)
	if #targets == 0 then
		local emptyLabel = createLabel(targetDropdownContent, "No online targets available.", 12, THEME.muted, false)
		emptyLabel.ZIndex = 21
		return
	end

	for _, target in ipairs(targets) do
		local button = createTextButton(targetDropdownContent, target.Name, selectedTargetUserId == target.UserId and THEME.accentDim or THEME.panelSoft)
		button.ZIndex = 21
		button.Size = UDim2.new(1, 0, 0, 34)
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Text = target.IsSelf and (`{target.Name} (You)`) or target.Name
		button.MouseButton1Click:Connect(function()
			selectedTargetUserId = target.UserId
			updateTargetButtonText()
			if targetDropdown then
				targetDropdown.Visible = false
			end
			requestSnapshot()
			if renderTargetDropdown then
				renderTargetDropdown()
			end
		end)
	end
end

renderTabs = function()
	if not leftTabsContent or not topTabsContent then
		return
	end

	clearContainer(leftTabsContent)
	clearContainer(topTabsContent)

	for _, categoryName in ipairs(categories) do
		local isActive = categoryName == selectedCategory
		local leftButton = createTextButton(leftTabsContent, categoryName, isActive and THEME.accentDim or THEME.panelSoft)
		leftButton.Size = UDim2.new(1, 0, 0, 38)
		leftButton.MouseButton1Click:Connect(function()
			selectedCategory = categoryName
			if renderTabs then
				renderTabs()
			end
			if renderActions then
				renderActions()
			end
		end)

		local topButton = createTextButton(topTabsContent, categoryName, isActive and THEME.accentDim or THEME.panelSoft)
		topButton.Size = UDim2.fromOffset(math.max(120, categoryName:len() * 10), 34)
		topButton.MouseButton1Click:Connect(function()
			selectedCategory = categoryName
			if renderTabs then
				renderTabs()
			end
			if renderActions then
				renderActions()
			end
		end)
	end
end

renderSnapshot = function()
	if not snapshotContent then
		return
	end

	clearContainer(snapshotContent)

	createLabel(snapshotContent, "Live Snapshot", 18, THEME.text, true)
	if not latestSnapshot then
		createLabel(snapshotContent, "No snapshot available yet.", 13, THEME.muted, false)
		return
	end

	local targetName = latestSnapshot.Name or "Unknown"
	createLabel(snapshotContent, `Target: {targetName}`, 13, THEME.accent, true)

	for _, field in ipairs(SNAPSHOT_FIELDS) do
		local rawValue = latestSnapshot[field.key]
		local value = if field.key == "FreeSpinRemaining" then formatSeconds(rawValue) else formatValue(rawValue)

		local row = Instance.new("Frame")
		row.BackgroundColor3 = THEME.panelSoft
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 32)
		row.Parent = snapshotContent
		createCorner(row, 10)

		local label = createLabel(row, field.label, 12, THEME.muted, true)
		label.Position = UDim2.new(0, 10, 0, 5)
		label.Size = UDim2.new(0.58, -12, 0, 18)
		label.AutomaticSize = Enum.AutomaticSize.None

		local valueLabel = createLabel(row, value, 12, THEME.text, false)
		valueLabel.Position = UDim2.new(0.58, 0, 0, 5)
		valueLabel.Size = UDim2.new(0.42, -10, 0, 18)
		valueLabel.AutomaticSize = Enum.AutomaticSize.None
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	end

	createLabel(snapshotContent, "Audit Log", 18, THEME.text, true)
	local auditLog = latestSnapshot.AuditLog or {}
	if #auditLog == 0 then
		createLabel(snapshotContent, "No actions logged yet.", 13, THEME.muted, false)
		return
	end

	for index = 1, math.min(#auditLog, 12) do
		local entry = auditLog[index]
		local card = Instance.new("Frame")
		card.BackgroundColor3 = THEME.panelSoft
		card.BorderSizePixel = 0
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.Parent = snapshotContent
		createCorner(card, 10)

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.Parent = card

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.Parent = card

		local statusColor = entry.Success == true and THEME.success or THEME.danger
		createLabel(card, `{entry.ActionId} -> {entry.TargetName}`, 13, statusColor, true)
		createLabel(card, tostring(entry.Result or "-"), 12, THEME.muted, false)
	end
end

local function buildSearchSelect(parent: Instance, action, inputDef)
	local state = getActionState(action.id)

	local wrap = Instance.new("Frame")
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = wrap

	createLabel(wrap, inputDef.label, 12, THEME.muted, true)

	local search = createTextBox(wrap, inputDef.placeholder or "Search...")
	search.Size = UDim2.new(1, 0, 0, 34)
	search.Text = state[inputDef.id .. "_query"] or ""

	local selectedLabel = createLabel(wrap, "Selected: " .. getOptionLabel(inputDef.options, state[inputDef.id]), 12, THEME.text, false)

	local resultScroll = Instance.new("ScrollingFrame")
	resultScroll.BackgroundColor3 = THEME.panelSoft
	resultScroll.BorderSizePixel = 0
	resultScroll.Size = UDim2.new(1, 0, 0, 116)
	resultScroll.ScrollBarThickness = 5
	resultScroll.ScrollBarImageTransparency = 0.5
	resultScroll.Parent = wrap
	createCorner(resultScroll, 10)

	local resultContent = Instance.new("Frame")
	resultContent.BackgroundTransparency = 1
	resultContent.Size = UDim2.new(1, -8, 0, 0)
	resultContent.AutomaticSize = Enum.AutomaticSize.Y
	resultContent.Parent = resultScroll

	local resultLayout = Instance.new("UIListLayout")
	resultLayout.Padding = UDim.new(0, 4)
	resultLayout.Parent = resultContent
	bindCanvasSize(resultScroll, resultLayout, "Y")

	local function renderResults()
		clearContainer(resultContent)
		local query = string.lower(search.Text)
		local shown = 0
		for _, option in ipairs(inputDef.options or {}) do
			local haystack = string.lower((option.label or "") .. " " .. (option.search or "") .. " " .. (option.value or ""))
			if query == "" or string.find(haystack, query, 1, true) then
				local button = createTextButton(resultContent, option.label, state[inputDef.id] == option.value and THEME.accentDim or THEME.panel)
				button.Size = UDim2.new(1, 0, 0, 28)
				button.TextSize = 12
				button.TextXAlignment = Enum.TextXAlignment.Left
				button.MouseButton1Click:Connect(function()
					state[inputDef.id] = option.value
					state[inputDef.id .. "_query"] = option.label
					search.Text = option.label
					selectedLabel.Text = "Selected: " .. option.label
					renderResults()
				end)
				shown += 1
				if shown >= 8 then
					break
				end
			end
		end

		if shown == 0 then
			createLabel(resultContent, "No matches.", 12, THEME.muted, false)
		end
	end

	search:GetPropertyChangedSignal("Text"):Connect(function()
		state[inputDef.id] = nil
		state[inputDef.id .. "_query"] = search.Text
		selectedLabel.Text = "Selected: " .. getOptionLabel(inputDef.options, resolveSearchValue(inputDef, state))
		renderResults()
	end)

	renderResults()
end

local function buildActionCard(parent: Instance, action)
	ensureInputDefaults(action)
	local state = getActionState(action.id)

	local card = Instance.new("Frame")
	card.BackgroundColor3 = THEME.panelSoft
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = parent
	createCorner(card, 14)
	createStroke(card, action.isDestructive and THEME.danger or THEME.stroke, 0.15, 1)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = card

	createLabel(card, action.label, 17, THEME.text, true)
	createLabel(card, action.description or "", 12, THEME.muted, false)

	local metaPieces = {}
	table.insert(metaPieces, action.allowOtherTarget and "Selected target" or "Self only")
	if action.isDestructive then
		table.insert(metaPieces, "Destructive")
	end
	createLabel(card, table.concat(metaPieces, "  |  "), 11, action.isDestructive and THEME.danger or THEME.accent, true)

	for _, inputDef in ipairs(action.inputs or {}) do
		if inputDef.kind == "number" or inputDef.kind == "text" then
			local wrap = Instance.new("Frame")
			wrap.BackgroundTransparency = 1
			wrap.Size = UDim2.new(1, 0, 0, 0)
			wrap.AutomaticSize = Enum.AutomaticSize.Y
			wrap.Parent = card

			local wrapLayout = Instance.new("UIListLayout")
			wrapLayout.Padding = UDim.new(0, 6)
			wrapLayout.Parent = wrap

			createLabel(wrap, inputDef.label, 12, THEME.muted, true)

			local textBox = createTextBox(wrap, inputDef.placeholder or "")
			textBox.Size = UDim2.new(1, 0, 0, 34)
			textBox.Text = tostring(state[inputDef.id .. "_text"] or "")
			textBox:GetPropertyChangedSignal("Text"):Connect(function()
				state[inputDef.id .. "_text"] = textBox.Text
			end)

			if inputDef.kind == "number" and type(inputDef.presets) == "table" and #inputDef.presets > 0 then
				local presetsWrap = Instance.new("Frame")
				presetsWrap.BackgroundTransparency = 1
				presetsWrap.Size = UDim2.new(1, 0, 0, 34)
				presetsWrap.Parent = wrap

				local presetsLayout = Instance.new("UIListLayout")
				presetsLayout.FillDirection = Enum.FillDirection.Horizontal
				presetsLayout.Padding = UDim.new(0, 6)
				presetsLayout.Parent = presetsWrap

				for _, preset in ipairs(inputDef.presets) do
					local presetButton = createTextButton(presetsWrap, tostring(preset), THEME.panel)
					presetButton.Size = UDim2.fromOffset(78, 28)
					presetButton.TextSize = 12
					presetButton.MouseButton1Click:Connect(function()
						textBox.Text = tostring(preset)
						state[inputDef.id .. "_text"] = textBox.Text
					end)
				end
			end
		elseif inputDef.kind == "boolean" then
			local wrap = Instance.new("Frame")
			wrap.BackgroundTransparency = 1
			wrap.Size = UDim2.new(1, 0, 0, 34)
			wrap.Parent = card

			local label = createLabel(wrap, inputDef.label, 12, THEME.muted, true)
			label.Size = UDim2.new(0.6, -8, 1, 0)
			label.AutomaticSize = Enum.AutomaticSize.None

			local toggle = createTextButton(wrap, state[inputDef.id] == true and "ON" or "OFF", state[inputDef.id] == true and THEME.success or THEME.panel)
			toggle.AnchorPoint = Vector2.new(1, 0)
			toggle.Position = UDim2.new(1, 0, 0, 0)
			toggle.Size = UDim2.fromOffset(84, 34)
			toggle.MouseButton1Click:Connect(function()
				state[inputDef.id] = not (state[inputDef.id] == true)
				toggle.Text = state[inputDef.id] == true and "ON" or "OFF"
				toggle.BackgroundColor3 = state[inputDef.id] == true and THEME.success or THEME.panel
			end)
		elseif inputDef.kind == "search_select" then
			buildSearchSelect(card, action, inputDef)
		end
	end

	if action.isDestructive then
		local requiredConfirmation = tostring(action.confirmationText or "RESET")
		local warning = createLabel(card, `Enter "{requiredConfirmation}" below to confirm.`, 12, THEME.danger, true)
		warning.Size = UDim2.new(1, 0, 0, 0)

		local confirmationBox = createTextBox(card, `Type {requiredConfirmation} here`)
		confirmationBox.Size = UDim2.new(1, 0, 0, 34)
		confirmationBox.Text = tostring(state.confirmationText or "")
		confirmationBox:GetPropertyChangedSignal("Text"):Connect(function()
			state.confirmationText = confirmationBox.Text
		end)
	end

	local statusColor = THEME.muted
	if state.lastSuccess == true then
		statusColor = THEME.success
	elseif state.lastSuccess == false then
		statusColor = THEME.danger
	end
	createLabel(card, tostring(state.lastStatus or "Ready."), 12, statusColor, false)

	local runButton = createTextButton(card, "Execute", action.isDestructive and THEME.danger or THEME.accentDim)
	runButton.Size = UDim2.new(1, 0, 0, 38)
	runButton.MouseButton1Click:Connect(function()
		local request = {
			actionId = action.id,
			targetUserId = selectedTargetUserId,
			params = {},
			confirmationText = state.confirmationText,
		}

		for _, inputDef in ipairs(action.inputs or {}) do
			if inputDef.kind == "number" then
				request.params[inputDef.id] = tonumber(state[inputDef.id .. "_text"]) or inputDef.default
			elseif inputDef.kind == "text" then
				request.params[inputDef.id] = state[inputDef.id .. "_text"] or inputDef.default or ""
			elseif inputDef.kind == "boolean" then
				request.params[inputDef.id] = state[inputDef.id] == true
			elseif inputDef.kind == "search_select" then
				request.params[inputDef.id] = resolveSearchValue(inputDef, state)
			end
		end

		local result, err = invokeRemote(ExecuteAction, request)
		if not result then
			state.lastSuccess = false
			state.lastStatus = err or "Failed to execute action."
			NotificationManager.show(state.lastStatus, "Error")
		elseif result.Success == true then
			state.lastSuccess = true
			state.lastStatus = result.Message or "Action completed."
			NotificationManager.show(state.lastStatus, "Success")
			if result.Targets then
				targets = result.Targets
				targetsByUserId = {}
				for _, target in ipairs(targets) do
					targetsByUserId[target.UserId] = target
				end
				if not targetsByUserId[selectedTargetUserId] then
					selectedTargetUserId = targets[1] and targets[1].UserId or player.UserId
				end
				updateTargetButtonText()
				if renderTargetDropdown then
					renderTargetDropdown()
				end
			end
			if result.Snapshot then
				latestSnapshot = result.Snapshot
			end
		else
			state.lastSuccess = false
			state.lastStatus = result.Error or result.Message or "Action failed."
			NotificationManager.show(state.lastStatus, "Error")
		end

		if renderActions then
			renderActions()
		end
		if renderSnapshot then
			renderSnapshot()
		end
	end)
end

renderActions = function()
	if not actionsContent or not searchBox then
		return
	end

	clearContainer(actionsContent)
	local query = string.lower(searchBox.Text or "")
	local useTwoColumns = rootFrame ~= nil and rootFrame.AbsoluteSize.X >= 760 and rootFrame.AbsoluteSize.X < 1200
	local filteredActions = {}

	local renderedCount = 0
	for _, action in ipairs(actions) do
		if action.category == selectedCategory and matchesAction(action, query) then
			table.insert(filteredActions, action)
			renderedCount += 1
		end
	end

	if renderedCount == 0 then
		createLabel(actionsContent, "No commands match this filter.", 13, THEME.muted, false)
		return
	end

	local columnCount = useTwoColumns and 2 or 1
	for index = 1, #filteredActions, columnCount do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Parent = actionsContent

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 12)
		rowLayout.Parent = row

		for column = 0, columnCount - 1 do
			local action = filteredActions[index + column]
			if action then
				local holder = Instance.new("Frame")
				holder.BackgroundTransparency = 1
				holder.AutomaticSize = Enum.AutomaticSize.Y
				holder.Size = if columnCount == 1 then UDim2.new(1, 0, 0, 0) else UDim2.new(0.5, -6, 0, 0)
				holder.Parent = row

				buildActionCard(holder, action)
			end
		end
	end
end

refreshAllUI = function()
	updateLayout()
	updateTargetButtonText()
	if accessBadge then
		accessBadge.Text = string.upper(accessLevel)
		accessBadge.BackgroundColor3 = bootstrapData and bootstrapData.AccessColor or THEME.panelSoft
		accessBadge.TextColor3 = bootstrapData and THEME.background or THEME.text
	end
	if renderTargetDropdown then
		renderTargetDropdown()
	end
	if renderTabs then
		renderTabs()
	end
	if renderActions then
		renderActions()
	end
	if renderSnapshot then
		renderSnapshot()
	end
end

local function initialize()
	if not requestBootstrap() then
		return
	end

	buildHudToggle()
	buildFrame()

	if refreshButton then
		refreshButton.MouseButton1Click:Connect(function()
			if requestBootstrap() then
				requestSnapshot()
				refreshAllUI()
			end
		end)
	end

	refreshAllUI()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end

		if input.KeyCode == Enum.KeyCode.T
			and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl))
			and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
		then
			toggleFrame()
		end
	end)
end

initialize()
