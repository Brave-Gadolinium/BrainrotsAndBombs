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
