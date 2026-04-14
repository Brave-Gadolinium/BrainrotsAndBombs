--!strict
-- LOCATION: StarterPlayerScripts/HUDController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService") 
local Workspace = game:GetService("Workspace")

-- [ MODULES ]
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local ItemConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemConfigurations"))
local IncomeCalculationUtils = require(ReplicatedStorage.Modules.IncomeCalculationUtils)
local MultiplierUtils = require(ReplicatedStorage.Modules.MultiplierUtils)
local ProductConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProductConfigurations"))
local NotificationManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NotificationManager")) 
local Constants = require(ReplicatedStorage.Modules.Constants)
local FrameManager = require(ReplicatedStorage.Modules.FrameManager)

local player = Players.LocalPlayer
local hudInitialized = false

-- Animation Config
local HOVER_SCALE = 1.05
local CLICK_SCALE = 0.95
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

print("[HUDController] Loaded (Only Money in Leaderstats, Active Offline Income Calc)")

local function isTouchOnlyControls(): boolean
	return UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
		and not UserInputService.MouseEnabled
end

local function setupButtonAnimation(button: GuiButton)
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale"); uiScale.Name = "AnimationScale"; uiScale.Parent = button
	end
	button.MouseEnter:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
	button.MouseLeave:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = 1}):Play() end)
	button.MouseButton1Down:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = CLICK_SCALE}):Play() end)
	button.MouseButton1Up:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
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

local function setupHUD()
	if hudInitialized then
		return
	end
	hudInitialized = true

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI")
	local hud = gui:WaitForChild("HUD")
	local timeLabel = hud:FindFirstChild("SessionTimer") :: TextLabel
	local boosts = hud:FindFirstChild("Boosts")
	local friendBoostLabel = boosts and waitForPath(boosts, {"Friends", "Value"}, 2)
	local rebirthBoostLabel = boosts and waitForPath(boosts, {"Rebirth", "Value"}, 2)

	local function updateSessionTimerLayout()
		local viewportSize = gui.AbsoluteSize
		local touchOnly = isTouchOnlyControls()
		local width = if touchOnly
			then math.clamp(math.floor(viewportSize.X * 0.30 + 0.5), 104, 148)
			else math.clamp(math.floor(viewportSize.X * 0.20 + 0.5), 180, 320)
		local height = if touchOnly
			then math.clamp(math.floor(viewportSize.Y * 0.04 + 0.5), 24, 34)
			else math.clamp(math.floor(viewportSize.Y * 0.055 + 0.5), 40, 58)
		local topOffset = if touchOnly
			then math.clamp(math.floor(viewportSize.Y * 0.012 + 0.5), 4, 10)
			else math.clamp(math.floor(viewportSize.Y * 0.02 + 0.5), 8, 18)
		local textSize = if touchOnly
			then math.clamp(math.floor(height * 0.52 + 0.5), 14, 18)
			else math.clamp(math.floor(height * 0.48 + 0.5), 18, 28)
		local cornerRadius = if touchOnly
			then math.clamp(math.floor(height * 0.25 + 0.5), 6, 10)
			else math.clamp(math.floor(height * 0.22 + 0.5), 8, 14)
		local strokeThickness = if touchOnly then 1 else 2

		timeLabel.Position = UDim2.new(0.5, 0, 0, topOffset)
		timeLabel.Size = UDim2.fromOffset(width, height)
		timeLabel.TextScaled = false
		timeLabel.TextSize = textSize

		local corner = timeLabel:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, cornerRadius)
		end

		local stroke = timeLabel:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = strokeThickness
		end
	end

	if not timeLabel then
		timeLabel = Instance.new("TextLabel")
		timeLabel.Name = "SessionTimer"
		timeLabel.AnchorPoint = Vector2.new(0.5, 0)
		timeLabel.BackgroundTransparency = 0.25
		timeLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		timeLabel.BorderSizePixel = 0
		timeLabel.Font = Enum.Font.GothamBold
		timeLabel.TextScaled = false
		timeLabel.Text = "05:00"
		timeLabel.Parent = hud

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = timeLabel

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.65
		stroke.Parent = timeLabel
	end

	updateSessionTimerLayout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSessionTimerLayout)

	-- 1. TRACK MONEY AND OFFLINE INCOME
	local labels = hud:WaitForChild("Labels")
	local moneyLabel = labels:WaitForChild("Money") :: TextLabel
	local offlineLabel = labels:WaitForChild("Offline") :: TextLabel

	local leaderstats = player:WaitForChild("leaderstats")
	local moneyStat = leaderstats:WaitForChild("Money") :: NumberValue

	local function updateMoney()
		moneyLabel.Text = NumberFormatter.Format(moneyStat.Value)
	end
	moneyStat.Changed:Connect(updateMoney)
	updateMoney()

	local function formatSessionTime(totalSeconds: number): string
		local minutes = math.floor(totalSeconds / 60)
		local seconds = totalSeconds % 60
		return string.format("%02d:%02d", minutes, seconds)
	end

	local function updateSessionTimer()
		timeLabel.Visible = not FrameManager.isAnyFrameOpen()

		local isEnded = Workspace:GetAttribute("SessionEnded") == true
		local message = Workspace:GetAttribute("SessionMessage")
		local remaining = Workspace:GetAttribute("SessionTimeRemaining")
		local warningThreshold = Constants.SESSION_WARNING_THRESHOLD

		if isEnded and type(message) == "string" and message ~= "" then
			timeLabel.Text = message
			timeLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			return
		end

		if type(remaining) ~= "number" then
			return
		end

		timeLabel.Text = formatSessionTime(remaining)
		if remaining <= warningThreshold then
			timeLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		else
			timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end

	Workspace:GetAttributeChangedSignal("SessionTimeRemaining"):Connect(updateSessionTimer)
	Workspace:GetAttributeChangedSignal("SessionEnded"):Connect(updateSessionTimer)
	Workspace:GetAttributeChangedSignal("SessionMessage"):Connect(updateSessionTimer)
	FrameManager.Changed:Connect(updateSessionTimer)
	updateSessionTimer()

	local trackedVisualItems: {[Model]: number} = {}
	local plotConnections: {RBXScriptConnection} = {}
	local watchedPlot: Model? = nil
	local baseIncomePerSec = 0

	local function disconnectConnections(connections: {RBXScriptConnection})
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	local function getVisualItemIncome(model: Model): number
		local name = model:GetAttribute("OriginalName")
		local mut = model:GetAttribute("Mutation") or "Normal"
		local lvl = model:GetAttribute("Level") or 1
		local itemData = ItemConfigurations.GetItemData(name)
		if not itemData then
			return 0
		end

		return IncomeCalculationUtils.ComputeBaseIncomePerSecond(itemData.Income or 0, mut, lvl)
	end

	local function updateBoostLabels()
		if friendBoostLabel and friendBoostLabel:IsA("TextLabel") then
			local friendBoostMultiplier = tonumber(player:GetAttribute("FriendBoostMultiplier")) or 1
			friendBoostLabel.Text = MultiplierUtils.FormatMultiplier(friendBoostMultiplier)
		end

		if rebirthBoostLabel and rebirthBoostLabel:IsA("TextLabel") then
			local rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
			rebirthBoostLabel.Text = MultiplierUtils.FormatMultiplier(
				MultiplierUtils.GetRebirthMultiplier(rebirths)
			)
		end
	end

	local function updateOfflineIncomeLabel()
		local reb = tonumber(player:GetAttribute("Rebirths")) or 0
		local rebMult = MultiplierUtils.GetRebirthMultiplier(reb)
		local isVip = player:GetAttribute("IsVIP") == true
		local vipMult = IncomeCalculationUtils.GetVipMultiplier(isVip)
		local offlinePerHour = baseIncomePerSec * rebMult * vipMult * 3600

		if offlineLabel then
			offlineLabel.Text = "Offline/Hour: $" .. NumberFormatter.Format(offlinePerHour)
		end
	end

	local function trackVisualItem(model: Model)
		if trackedVisualItems[model] ~= nil then
			return
		end

		local incomePerSec = getVisualItemIncome(model)
		trackedVisualItems[model] = incomePerSec
		baseIncomePerSec += incomePerSec
		updateOfflineIncomeLabel()
	end

	local function untrackVisualItem(model: Model)
		local incomePerSec = trackedVisualItems[model]
		if incomePerSec == nil then
			return
		end

		trackedVisualItems[model] = nil
		baseIncomePerSec = math.max(0, baseIncomePerSec - incomePerSec)
		updateOfflineIncomeLabel()
	end

	local function bindPlot(plot: Model?)
		disconnectConnections(plotConnections)
		watchedPlot = plot
		baseIncomePerSec = 0
		table.clear(trackedVisualItems)

		if not plot then
			updateOfflineIncomeLabel()
			return
		end

		table.insert(plotConnections, plot.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Model") and descendant.Name == "VisualItem" then
				trackVisualItem(descendant)
			end
		end))

		table.insert(plotConnections, plot.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("Model") and descendant.Name == "VisualItem" then
				untrackVisualItem(descendant)
			end
		end))

		for _, descendant in ipairs(plot:GetDescendants()) do
			if descendant:IsA("Model") and descendant.Name == "VisualItem" then
				trackVisualItem(descendant)
			end
		end

		updateOfflineIncomeLabel()
	end

	local plotName = "Plot_" .. player.Name
	local function refreshPlotBinding()
		local plot = Workspace:FindFirstChild(plotName)
		if plot and plot:IsA("Model") then
			bindPlot(plot)
		else
			bindPlot(nil)
		end
	end

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == plotName then
			refreshPlotBinding()
		end
	end)

	Workspace.ChildRemoved:Connect(function(child)
		if child == watchedPlot or child.Name == plotName then
			refreshPlotBinding()
		end
	end)

	player:GetAttributeChangedSignal("Rebirths"):Connect(updateOfflineIncomeLabel)
	player:GetAttributeChangedSignal("Rebirths"):Connect(updateBoostLabels)
	player:GetAttributeChangedSignal("IsVIP"):Connect(updateOfflineIncomeLabel)
	player:GetAttributeChangedSignal("FriendBoostMultiplier"):Connect(updateBoostLabels)
	updateBoostLabels()
	refreshPlotBinding()

	-- 2. SETUP RANDOM ITEM BUTTON (GACHA)
	local rightPanel = hud:WaitForChild("Right")
	local randomBtn = rightPanel:WaitForChild("Random") :: TextButton
	local itemImage = randomBtn:WaitForChild("Image") :: ImageLabel
	local randomPriceLabel = randomBtn:WaitForChild("Price") :: TextLabel
	local randomTextLabel = randomBtn:FindFirstChild("Text") :: TextLabel 

	setupButtonAnimation(randomBtn)

	local validItems = {}
	for name, data in pairs(ItemConfigurations.Items) do
		if data.Rarity ~= "Common" and data.Rarity ~= "Uncommon" then table.insert(validItems, data) end
	end

	if #validItems > 0 then
		local totalValidItems = #validItems
		if not randomBtn:GetAttribute("CyclerRunning") then
			randomBtn:SetAttribute("CyclerRunning", true)
			task.spawn(function()
				while randomBtn.Parent do
					local selectedData = validItems[math.random(1, totalValidItems)]
					itemImage.Image = selectedData.ImageId
					if randomTextLabel then randomTextLabel.Text = string.format("Random (%.1f%%)", (1 / totalValidItems) * 100) end
					task.wait(1.5)
				end
			end)
		end
	end

	local randomProductId = ProductConfigurations.Products["RandomItem"]
	if randomProductId then
		task.spawn(function()
			local success, info = pcall(function() return MarketplaceService:GetProductInfo(randomProductId, Enum.InfoType.Product) end)
			if success and info and randomPriceLabel then randomPriceLabel.Text = "" .. tostring(info.PriceInRobux) else if randomPriceLabel then randomPriceLabel.Text = "N/A" end end
		end)
		randomBtn.MouseButton1Click:Connect(function() MarketplaceService:PromptProductPurchase(player, randomProductId) end)
	end

	-- 3. SETUP INVITE FRIENDS BUTTON
	local leftButtons2 = hud:WaitForChild("Left"):WaitForChild("Buttons2")
	local inviteBtn = leftButtons2:FindFirstChild("Invite") :: TextButton
	if inviteBtn then
		setupButtonAnimation(inviteBtn)
		inviteBtn.MouseButton1Click:Connect(function()
			local success, canInvite = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
			if success and canInvite then SocialService:PromptGameInvite(player) else NotificationManager.show("You cannot send invites right now.", "Error") end
		end)
	end
end

player.CharacterAdded:Connect(function(char) task.wait(0.5); setupHUD() end)
if player.Character then setupHUD() end
