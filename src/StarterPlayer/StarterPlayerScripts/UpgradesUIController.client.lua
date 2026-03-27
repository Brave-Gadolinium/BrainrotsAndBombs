--!strict
-- LOCATION: StarterPlayerScripts/UpgradesUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UpgradesConfig = require(Modules:WaitForChild("UpgradesConfigurations"))
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))

local player = Players.LocalPlayer
local Templates = ReplicatedStorage:WaitForChild("Templates")
local upgradeTemplate = Templates:WaitForChild("UpgradeTemplate") :: Frame

local Events = ReplicatedStorage:WaitForChild("Events")
local requestUpgradeEvent = Events:WaitForChild("RequestUpgradeAction") :: RemoteEvent
local updateEvent = Events:WaitForChild("UpdateUpgradesUI") :: RemoteEvent
local reportAnalyticsIntent = Events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local HOVER_SCALE = 1.05
local CLICK_SCALE = 0.95
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local uiReferences = {} 

local function setupButtonAnimation(button: GuiButton)
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "AnimationScale"
		uiScale.Parent = button
	end
	button.MouseEnter:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
	button.MouseLeave:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = 1}):Play() end)
	button.MouseButton1Down:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = CLICK_SCALE}):Play() end)
	button.MouseButton1Up:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
end

local function findTextLabel(parent: Instance): TextLabel?
	local label = parent:FindFirstChild("Text") or parent:FindFirstChild("Price")
	if label and label:IsA("TextLabel") then return label end
	return parent:FindFirstChildWhichIsA("TextLabel", true)
end

local function initializeUI()
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("GUI")
	local frames = mainGui:WaitForChild("Frames")
	local upgradesFrame = frames:WaitForChild("Upgrades")
	local scrollingFrame = upgradesFrame:WaitForChild("Scrolling")

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	table.clear(uiReferences)

	for _, upgrade in ipairs(UpgradesConfig.Upgrades) do
		if upgrade.HiddenInUI == true then
			continue
		end

		local newUpgrade = upgradeTemplate:Clone()
		newUpgrade.Name = upgrade.Id
		newUpgrade.Visible = true

		-- Main Title
		local titleLabel = newUpgrade:FindFirstChild("Text") :: TextLabel
		if titleLabel then titleLabel.Text = upgrade.DisplayName end

		-- Design (Image)
		local designFrame = newUpgrade:FindFirstChild("Design")
		if designFrame then
			local img = designFrame:FindFirstChild("Image") or designFrame:FindFirstChildWhichIsA("ImageLabel") :: ImageLabel
			if img then img.Image = upgrade.ImageId end
		end

		-- Buttons
		local buttonsFrame = newUpgrade:FindFirstChild("Buttons")
		local moneyBtn = buttonsFrame and buttonsFrame:FindFirstChild("Money") :: TextButton
		local robuxBtn = buttonsFrame and buttonsFrame:FindFirstChild("Robux") :: TextButton

		local moneyPriceLabel = moneyBtn and findTextLabel(moneyBtn)
		local robuxPriceLabel = robuxBtn and findTextLabel(robuxBtn)

		-- Stats
		local statsFrame = newUpgrade:FindFirstChild("Stats")
		local beforeFrame = statsFrame and statsFrame:FindFirstChild("Before")
		local afterFrame = statsFrame and statsFrame:FindFirstChild("After")

		local beforeLabel = beforeFrame and beforeFrame:FindFirstChild("Text") :: TextLabel
		local afterLabel = afterFrame and afterFrame:FindFirstChild("Text") :: TextLabel

		-- Money Button Logic
		if moneyBtn then
			setupButtonAnimation(moneyBtn)
			moneyBtn.MouseButton1Click:Connect(function()
				reportAnalyticsIntent:FireServer("UpgradeSelected", {
					upgradeId = upgrade.Id,
				})
				requestUpgradeEvent:FireServer(upgrade.Id)
			end)
		end

		-- Robux Button Logic
		if robuxBtn then
			local robuxId = upgrade.RobuxProductId
			if robuxId then
				setupButtonAnimation(robuxBtn)
				task.spawn(function()
					local success, info = pcall(function() return MarketplaceService:GetProductInfo(robuxId, Enum.InfoType.Product) end)
					if success and info and robuxPriceLabel then
						robuxPriceLabel.Text = "оЂ‚" .. tostring(info.PriceInRobux)
					end
				end)
				robuxBtn.MouseButton1Click:Connect(function()
					MarketplaceService:PromptProductPurchase(player, robuxId)
				end)
			else
				robuxBtn.Visible = false
			end
		end

		uiReferences[upgrade.Id] = {
			MoneyPriceLabel = moneyPriceLabel,
			BeforeLabel = beforeLabel,
			AfterLabel = afterLabel,
			Amount = upgrade.Amount
		}

		newUpgrade.Parent = scrollingFrame
	end
end

task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("GUI")
	local frames = mainGui:WaitForChild("Frames")
	local upgradesFrame = frames:WaitForChild("Upgrades")

	upgradesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if upgradesFrame.Visible then
			reportAnalyticsIntent:FireServer("UpgradesOpened")
		end
	end)
end)

local function onServerUpdate(data: any)
	for upgradeId, upgradeData in pairs(data) do
		local ref = uiReferences[upgradeId]
		if ref then
			-- Visual Cap for CarryCapacity (If it's Carry1 and the value is 3 or more)
			if upgradeId == "Carry1" and upgradeData.Current >= 3 then
				if ref.MoneyPriceLabel then ref.MoneyPriceLabel.Text = "MAX" end
				if ref.BeforeLabel then ref.BeforeLabel.Text = tostring(upgradeData.Current) end
				if ref.AfterLabel then ref.AfterLabel.Text = "MAX" end
			else
				if ref.MoneyPriceLabel then ref.MoneyPriceLabel.Text = "$" .. NumberFormatter.Format(upgradeData.Cost) end
				if ref.BeforeLabel then ref.BeforeLabel.Text = tostring(upgradeData.Current) end

				-- Automatically adds +1 or +3 to the After label depending on the config!
				if ref.AfterLabel then ref.AfterLabel.Text = tostring(upgradeData.Current + upgradeData.Amount) end 
			end
		end
	end
end

initializeUI()

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	initializeUI()
	updateEvent:FireServer() 
end)

updateEvent.OnClientEvent:Connect(onServerUpdate)
updateEvent:FireServer()
