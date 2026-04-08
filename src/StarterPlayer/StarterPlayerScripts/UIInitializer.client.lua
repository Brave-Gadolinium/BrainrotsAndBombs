--!strict
-- LOCATION: StarterPlayerScripts/UIInitializer

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

-- Modules
local FrameManager = require(ReplicatedStorage.Modules.FrameManager)

local UIInitializer = {}

-- [ CONFIGURATION ]
local DEBOUNCE_TIME = 0.5
local CLOSE_DISTANCE = 15 -- Studs for Touch Zones

-- Animation Config
local HOVER_SCALE = 1.1
local CLICK_SCALE = 0.95
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- [ REFERENCES ]
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mainGui = playerGui:WaitForChild("GUI") 
local framesContainer = mainGui:WaitForChild("Frames")
local hudGui = mainGui:WaitForChild("HUD") 

local lastInteraction = 0
local OWN_BASE_INTERACTION_RADIUS = 100

local function ensureGuiCorner(target: Instance, radius: UDim)
	if target:FindFirstChildOfClass("UICorner") then
		return
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = target
end

local function ensureBoostersButton()
	local rightPanel = hudGui:FindFirstChild("Right")
	if not rightPanel then
		return
	end

	local existingButton = rightPanel:FindFirstChild("BoostersButton")
	if existingButton and existingButton:IsA("GuiButton") then
		return
	end

	local button = Instance.new("TextButton")
	button.Name = "BoostersButton"
	button.Size = UDim2.fromOffset(120, 40)
	button.Position = UDim2.new(1, -124, 0, 56)
	button.AnchorPoint = Vector2.new(0, 0)
	button.BackgroundColor3 = Color3.fromRGB(255, 170, 64)
	button.TextColor3 = Color3.fromRGB(20, 20, 20)
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.Text = "Boosters"
	button.Parent = rightPanel
	ensureGuiCorner(button, UDim.new(0, 10))

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.25
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.2
	stroke.Parent = button
end

local function createBoosterCard(parent: Instance, order: number, title: string, descriptionText: string): Frame
	local card = Instance.new("Frame")
	card.Name = title:gsub("%s+", "")
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -18, 0, 96)
	card.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
	card.BorderSizePixel = 0
	card.Parent = parent
	ensureGuiCorner(card, UDim.new(0, 10))

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -170, 0, 26)
	titleLabel.Position = UDim2.fromOffset(10, 6)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.Text = title
	titleLabel.Parent = card

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "Description"
	descriptionLabel.Size = UDim2.new(1, -20, 0, 38)
	descriptionLabel.Position = UDim2.fromOffset(10, 34)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.TextSize = 14
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
	descriptionLabel.Text = descriptionText
	descriptionLabel.Parent = card

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "Buy"
	buyButton.Size = UDim2.fromOffset(140, 36)
	buyButton.Position = UDim2.new(1, -150, 1, -46)
	buyButton.BackgroundColor3 = Color3.fromRGB(255, 170, 64)
	buyButton.TextColor3 = Color3.fromRGB(20, 20, 20)
	buyButton.TextScaled = true
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Text = "Buy"
	buyButton.Parent = card
	ensureGuiCorner(buyButton, UDim.new(0, 8))

	return card
end

local function ensureBoostersFrame()
	local existing = framesContainer:FindFirstChild("Boosters")
	if existing and existing:IsA("GuiObject") then
		return
	end

	local frame = Instance.new("Frame")
	frame.Name = "Boosters"
	frame.Size = UDim2.fromOffset(560, 500)
	frame.Position = UDim2.new(0.5, -280, 0.5, -250)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = framesContainer
	ensureGuiCorner(frame, UDim.new(0, 14))

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -120, 0, 40)
	title.Position = UDim2.fromOffset(14, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 28
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Boosters"
	title.Parent = frame

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.Size = UDim2.fromOffset(36, 36)
	closeButton.Position = UDim2.new(1, -46, 0, 10)
	closeButton.BackgroundColor3 = Color3.fromRGB(52, 52, 60)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextScaled = true
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.Text = "X"
	closeButton.Parent = frame
	ensureGuiCorner(closeButton, UDim.new(1, 0))

	local scrolling = Instance.new("ScrollingFrame")
	scrolling.Name = "Content"
	scrolling.Size = UDim2.new(1, -20, 1, -64)
	scrolling.Position = UDim2.fromOffset(10, 54)
	scrolling.BackgroundTransparency = 1
	scrolling.BorderSizePixel = 0
	scrolling.ScrollBarThickness = 6
	scrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrolling.CanvasSize = UDim2.new()
	scrolling.Parent = frame

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scrolling

	createBoosterCard(scrolling, 1, "Mega Explosion", "10 minutes. Sets your bomb explosion radius to max.")
	createBoosterCard(scrolling, 2, "Shield", "10 minutes. Blocks bomb knockback, ragdoll and carried brainrot loss.")
	createBoosterCard(scrolling, 3, "Nuke Booster", "Instantly hits other players in the mining zone.")
	createBoosterCard(scrolling, 4, "Auto Bomb", "Permanent gamepass with On/Off toggle.")
end

local function getPlayerPlot(): Model?
	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if plot and plot:IsA("Model") then
		return plot
	end

	return nil
end

local function getPlotCenter(plot: Model): Vector3?
	if plot.Parent then
		return plot:GetPivot().Position
	end

	local spawnPart = plot:FindFirstChild("Spawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.Position
	end

	local primaryPart = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart", true)
	if primaryPart then
		return primaryPart.Position
	end

	return nil
end

local function isWithinOwnBaseInteractionRange(position: Vector3): boolean
	local playerPlot = getPlayerPlot()
	if not playerPlot then
		return false
	end

	local plotCenter = getPlotCenter(playerPlot)
	if not plotCenter then
		return false
	end

	return (position - plotCenter).Magnitude <= OWN_BASE_INTERACTION_RADIUS
end

-- [ HELPER: BUTTON ANIMATIONS ]
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

-- [ SETUP: CLOSE BUTTONS ]
local function setupCloseButton(frame: GuiObject)
	local closeBtn = frame:FindFirstChild("Close", true) 
	if closeBtn and (closeBtn:IsA("TextButton") or closeBtn:IsA("ImageButton")) then
		FrameManager.connect(closeBtn, frame.Name, "Close")
		setupButtonAnimation(closeBtn)
	end
end

-- [ LOGIC: HUD BUTTONS ]
local function setupHudButtons()
	for _, descendant in ipairs(hudGui:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			local frameName = descendant.Name:gsub("Button", "") -- "ShopButton" -> "Shop"

			-- ## SAFETY: Ignore Notifications ##
			if frameName == "Notifications" then continue end

			local targetFrame = framesContainer:FindFirstChild(frameName)
			if targetFrame then
				FrameManager.connect(descendant, frameName, "Toggle")
				setupButtonAnimation(descendant)
			end
		end
	end
end

-- [ LOGIC: WORKSPACE TOUCH ]
local function setupTaggedTouchTrigger(tagName: string, frameName: string)
	local targetFrame = framesContainer:FindFirstChild(frameName) :: GuiObject
	if not targetFrame then return end

	local openedByTouch = false
	local activeTouchPart: BasePart? = nil

	local function connectTouchPart(touchPart: Instance)
		if not touchPart:IsA("BasePart") then
			return
		end

		if touchPart:GetAttribute("TouchTriggerConnected") then
			return
		end

		touchPart:SetAttribute("TouchTriggerConnected", true)

		touchPart.Touched:Connect(function(hit)
			local now = tick()
			if now - lastInteraction < DEBOUNCE_TIME then return end
			local char = hit.Parent
			if char == player.Character then
				local hum = char:FindFirstChild("Humanoid")
				local root = char:FindFirstChild("HumanoidRootPart")
				if hum and hum.Health > 0 and root and root:IsA("BasePart") and isWithinOwnBaseInteractionRange(root.Position) then
					lastInteraction = now
					openedByTouch = true
					activeTouchPart = touchPart
					FrameManager.open(frameName)
				end
			end
		end)
	end

	-- Reset the touch flag if the frame gets closed by ANY means (Distance, HUD button, or X button)
	targetFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not targetFrame.Visible then
			openedByTouch = false
			activeTouchPart = nil
		end
	end)

	for _, taggedInstance in ipairs(CollectionService:GetTagged(tagName)) do
		connectTouchPart(taggedInstance)
	end

	CollectionService:GetInstanceAddedSignal(tagName):Connect(connectTouchPart)

	task.spawn(function()
		while true do
			task.wait(0.5)
			-- ONLY check distance if the menu was opened by walking onto the part
			if openedByTouch and targetFrame.Visible and player.Character and player.Character.PrimaryPart and activeTouchPart then
				local dist = (player.Character.PrimaryPart.Position - activeTouchPart.Position).Magnitude
				if dist > CLOSE_DISTANCE then
					FrameManager.close(frameName)
				end
			end
		end
	end)
end

-- [ INIT ]
function UIInitializer:Init()
	print("[UIInitializer] Starting...")
	pcall(function() StarterGui:SetCore("ResetButtonCallback", false) end)

	-- 2. Initialize Frames (Use IsA("GuiObject") to catch ScrollingFrames too!)
	ensureBoostersFrame()
	ensureBoostersButton()
	for _, child in ipairs(framesContainer:GetChildren()) do
		if child:IsA("GuiObject") then

			if child.Name ~= "Notifications" then
				child.Visible = false
				setupCloseButton(child)
			else
				-- Force Notifications container to be visible!
				child.Visible = true 
			end

		end
	end

	setupHudButtons()
	setupTaggedTouchTrigger("UpgradePart", "Upgrades")
	setupTaggedTouchTrigger("ShopPart", "Pickaxes")

	print("[UIInitializer] Ready.")
end

UIInitializer:Init()

return UIInitializer
