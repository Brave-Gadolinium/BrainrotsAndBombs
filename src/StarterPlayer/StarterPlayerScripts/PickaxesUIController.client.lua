--!strict
-- LOCATION: StarterPlayerScripts/PickaxesUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- [ MODULES ]
local Modules = ReplicatedStorage:WaitForChild("Modules")
local PickaxesConfigurations = require(Modules:WaitForChild("PickaxesConfigurations"))
local NumberFormatter = require(Modules:WaitForChild("NumberFormatter"))
local PickaxesFolder = ReplicatedStorage:WaitForChild("Pickaxes")

-- Templates & Events
local Templates = ReplicatedStorage:WaitForChild("Templates")
local pickaxeTemplate = Templates:WaitForChild("PickaxeTemplate")
local Events = ReplicatedStorage:WaitForChild("Events")
local requestEvent = Events:WaitForChild("RequestPickaxeAction") :: RemoteEvent
local getDataFunction = Events:WaitForChild("GetPickaxeData") :: RemoteFunction
local reportAnalyticsIntent = Events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

-- State
local selectedPickaxeId: string? = nil
local isCurrentlyLocked: boolean = false
local isCurrentlyOwned: boolean = false

-- [ ANIMATION CONFIG ]
local HOVER_SCALE = 1.05
local CLICK_SCALE = 0.95
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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

-- [ CORE LOGIC ]
local function selectPickaxe(pickaxeId: string, showcaseFrame: Frame, isOwned: boolean, isLocked: boolean, shouldReport: boolean?)
	selectedPickaxeId = pickaxeId
	isCurrentlyOwned = isOwned
	isCurrentlyLocked = isLocked

	local config = PickaxesConfigurations.Pickaxes[pickaxeId]
	if not config then return end

	-- Get Showcase Elements
	local showcaseImage = showcaseFrame:WaitForChild("Image") :: ImageLabel
	local showcaseName = showcaseFrame:WaitForChild("Name") :: TextLabel
	local showcaseDamage = showcaseFrame:WaitForChild("Damage") :: TextLabel
	local showcaseSpeed = showcaseFrame:WaitForChild("Speed") :: TextLabel
	local buyButton = showcaseFrame:WaitForChild("Buy") :: TextButton
	local buyPriceText = buyButton:WaitForChild("Text") :: TextLabel

	-- Update Text Labels
	showcaseName.Text = config.DisplayName
	showcaseDamage.Text = "Damage: " .. tostring(config.Damage)
	showcaseSpeed.Text = "Speed: " .. tostring(config.Cooldown) .. "s"
	showcaseImage.Image = config.ImageId

	-- Silhouette the Showcase Image if locked
	if isLocked then
		showcaseImage.ImageColor3 = Color3.new(0, 0, 0)
	else
		showcaseImage.ImageColor3 = Color3.new(1, 1, 1) -- Reset to normal
	end

	-- Dynamic Showcase Button Logic
	if isOwned then
		buyPriceText.Text = "OWNED"
		buyButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100) -- Gray
	elseif isLocked then
		buyPriceText.Text = "LOCKED"
		buyButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50) -- Red
	else
		-- This is the NEXT pickaxe they are allowed to buy
		if config.Price > 0 then
			buyPriceText.Text = "BUY ($" .. NumberFormatter.Format(config.Price) .. ")"
		else
			buyPriceText.Text = "FREE"
		end
		buyButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50) -- Green
	end

	if shouldReport ~= false then
		reportAnalyticsIntent:FireServer("BombSelected", {
			pickaxeName = pickaxeId,
		})
	end
end

local function initializeUI()
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("GUI")
	local frames = mainGui:WaitForChild("Frames")
	local pickaxesFrame = frames:WaitForChild("Pickaxes")

	local scrollingFrame = pickaxesFrame:WaitForChild("Scrolling")
	local showcaseFrame = pickaxesFrame:WaitForChild("Showcase")

	-- Fetch player data securely from the Server
	local ownedPickaxes = getDataFunction:InvokeServer()
	if type(ownedPickaxes) ~= "table" then ownedPickaxes = {["Bomb 1"] = true} end

	-- 1. Clear existing items
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiButton") then 
			child:Destroy() 
		end
	end

	-- 2. Sort pickaxes safely
	local sortedPickaxes = {}

	for id, data in pairs(PickaxesConfigurations.Pickaxes) do
		local toolTemplate = PickaxesFolder:FindFirstChild(id)
		if toolTemplate then
			table.insert(sortedPickaxes, {Id = id, Data = data})
		end
	end
	table.sort(sortedPickaxes, function(a, b) return a.Data.Price < b.Data.Price end)

	if #sortedPickaxes == 0 then
		selectedPickaxeId = nil
		isCurrentlyOwned = false
		isCurrentlyLocked = true
		return
	end

	-- 3. Figure out which pickaxe is "Next"
	local nextAvailableId = nil
	for _, pickaxe in ipairs(sortedPickaxes) do
		if not ownedPickaxes[pickaxe.Id] then
			nextAvailableId = pickaxe.Id
			break
		end
	end

	-- ## FIXED: Figure out exactly which pickaxe we should auto-select on load ##
	-- If they own everything, it safely selects the very last pickaxe in the game.
	local pickaxeToAutoSelect = nextAvailableId or sortedPickaxes[#sortedPickaxes].Id

	-- 4. Populate Grid
	for i, pickaxe in ipairs(sortedPickaxes) do
		local newTemplate = pickaxeTemplate:Clone() :: TextButton
		newTemplate.Name = pickaxe.Id
		newTemplate.Parent = scrollingFrame
		newTemplate.Visible = true

		local isOwned = ownedPickaxes[pickaxe.Id] == true
		local isNext = (pickaxe.Id == nextAvailableId)
		local isLocked = not isOwned and not isNext

		-- Setup UI Elements
		local img = newTemplate:FindFirstChild("Image") :: ImageLabel
		local lockedIcon = newTemplate:FindFirstChild("Locked") :: ImageLabel
		local checkmarkIcon = newTemplate:FindFirstChild("Checkmark") :: ImageLabel
		local priceText = newTemplate:FindFirstChild("Price") :: TextLabel

		if img then 
			img.Image = pickaxe.Data.ImageId 

			-- Silhouette the Template Image if locked
			if isLocked then
				img.ImageColor3 = Color3.new(0, 0, 0)
			else
				img.ImageColor3 = Color3.new(1, 1, 1) -- Reset to normal
			end
		end

		if lockedIcon then lockedIcon.Visible = isLocked end
		if checkmarkIcon then checkmarkIcon.Visible = isOwned end

		-- Set Grid Price Text
		if priceText then
			if pickaxe.Data.Price > 0 then
				priceText.Text = "$" .. NumberFormatter.Format(pickaxe.Data.Price)
			else
				priceText.Text = "FREE"
			end
		end

		-- Setup Hover/Click Animation
		setupButtonAnimation(newTemplate)

		-- Handle Click
		newTemplate.MouseButton1Click:Connect(function()
			selectPickaxe(pickaxe.Id, showcaseFrame, isOwned, isLocked, true)
		end)

		-- ## FIXED: Auto-selects the pickaxe they left off on! ##
		if pickaxe.Id == pickaxeToAutoSelect then
			selectPickaxe(pickaxe.Id, showcaseFrame, isOwned, isLocked, false)
		end
	end

	-- 5. Setup Buy Button
	local buyButton = showcaseFrame:WaitForChild("Buy") :: TextButton
	if not buyButton:GetAttribute("ConnectionSet") then
		buyButton:SetAttribute("ConnectionSet", true)

		setupButtonAnimation(buyButton)

		buyButton.MouseButton1Click:Connect(function()
			if not selectedPickaxeId then return end
			if isCurrentlyOwned or isCurrentlyLocked then return end

			requestEvent:FireServer(selectedPickaxeId)
		end)
	end
end

task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("GUI")
	local frames = mainGui:WaitForChild("Frames")
	local pickaxesFrame = frames:WaitForChild("Pickaxes")

	pickaxesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if pickaxesFrame.Visible then
			reportAnalyticsIntent:FireServer("BombShopOpened")
		end
	end)
end)

-- Refresh UI when Server tells us a purchase was successful
local updateUIEvent = Events:WaitForChild("UpdatePickaxeUI") :: RemoteEvent
updateUIEvent.OnClientEvent:Connect(function()
	initializeUI()
end)

initializeUI()

player.CharacterAdded:Connect(function()
	task.wait(0.5) 
	initializeUI()
end)
