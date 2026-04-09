--!strict
-- LOCATION: StarterPlayerScripts/HUDController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService") 
local Workspace = game:GetService("Workspace")

-- [ MODULES ]
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local ItemConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemConfigurations"))
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

-- Income Calculation Constants
local INCOME_SCALING = Constants.INCOME_SCALING
local MUTATION_MULTIPLIERS = Constants.MUTATION_MULTIPLIERS

print("[HUDController] Loaded (Only Money in Leaderstats, Active Offline Income Calc)")

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

local function setupHUD()
	if hudInitialized then
		return
	end
	hudInitialized = true

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI")
	local hud = gui:WaitForChild("HUD")
	local timeLabel = hud:FindFirstChild("SessionTimer") :: TextLabel
	if not timeLabel then
		timeLabel = Instance.new("TextLabel")
		timeLabel.Name = "SessionTimer"
		timeLabel.AnchorPoint = Vector2.new(0.5, 0)
		timeLabel.Position = UDim2.fromScale(0.5, 0.02)
		timeLabel.Size = UDim2.fromOffset(260, 54)
		timeLabel.BackgroundTransparency = 0.25
		timeLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		timeLabel.BorderSizePixel = 0
		timeLabel.Font = Enum.Font.GothamBold
		timeLabel.TextScaled = true
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

		local base = itemData.Income or 0
		local mutMult = MUTATION_MULTIPLIERS[mut] or 1
		local lvlMult = INCOME_SCALING ^ (lvl - 1)
		return base * mutMult * lvlMult
	end

	local function updateOfflineIncomeLabel()
		local reb = player:GetAttribute("Rebirths") or 0
		local rebMult = 1 + (reb * 0.5)
		local isVip = player:GetAttribute("IsVIP") == true
		local vipMult = isVip and 1.5 or 1
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
	player:GetAttributeChangedSignal("IsVIP"):Connect(updateOfflineIncomeLabel)
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
