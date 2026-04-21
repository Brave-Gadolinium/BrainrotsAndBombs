--!strict
-- LOCATION: StarterPlayerScripts/SellController

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- [ NPC REFERENCES ]
local sellNPC = Workspace:WaitForChild("SellNPC")
local sourceGui = sellNPC:WaitForChild("SellGUI") -- The template inside the NPC

-- [ CONFIG ]
local MAX_DISTANCE = 15
local CHECK_RATE = 0.2
local DEBOUNCE_TIME = 0.5

-- [ EVENTS ]
local Events = ReplicatedStorage:WaitForChild("Events")
local SellEvent = Events:WaitForChild("RequestSell")

-- [ ANIMATION CONFIG ]
local HOVER_SCALE = 1.1
local CLICK_SCALE = 0.95
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- [ STATE ]
local isMenuOpen = false
local SellGUI: BillboardGui? = nil -- Variable to hold the current GUI
local activeSellPart: BasePart? = nil
local lastInteraction = 0
local OWN_BASE_INTERACTION_RADIUS = 100
local DEBUG_SELL_TRACE = false

local function debugSellTrace(message: string)
	if DEBUG_SELL_TRACE then
		print(("[BrainrotTrace][SellController][%s][step=%s] %s"):format(
			player.Name,
			tostring(player:GetAttribute("OnboardingStep")),
			message
		))
	end
end

local function shouldBlockTutorialSell(): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep > 0
		and onboardingStep < TutorialConfiguration.FinalStep
		and (onboardingStep == 4 or onboardingStep == 5)
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

-- [ HELPER: Button Animation ]
local function setupButtonAnimation(button: GuiButton)
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "AnimationScale"
		uiScale.Parent = button
	end

	uiScale.Scale = 1

	button.MouseEnter:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
	button.MouseLeave:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = 1}):Play() end)
	button.MouseButton1Down:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = CLICK_SCALE}):Play() end)
	button.MouseButton1Up:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
end

-- [ LOGIC ]

local function closeSellMenu()
	if SellGUI then
		SellGUI.Enabled = false
	end
	debugSellTrace("closeSellMenu")
	isMenuOpen = false
	activeSellPart = nil
end

local function openSellMenu(sellPart: BasePart)
	if shouldBlockTutorialSell() then
		debugSellTrace(("openSellMenu blocked by tutorial sellPart=%s"):format(sellPart:GetFullName()))
		return
	end
	if isMenuOpen or not SellGUI then return end
	isMenuOpen = true
	activeSellPart = sellPart
	debugSellTrace(("openSellMenu sellPart=%s"):format(sellPart:GetFullName()))

	SellGUI.Enabled = true
	SellGUI.Adornee = sellPart

	-- Reset buttons scale (Manual find because references might change)
	local buttons = {SellGUI:FindFirstChild("Close", true), SellGUI:FindFirstChild("SellEquipped", true), SellGUI:FindFirstChild("SellInventory", true)}
	for _, btn in pairs(buttons) do
		if btn and btn:IsA("GuiButton") then
			local scale = btn:FindFirstChild("AnimationScale") :: UIScale
			if scale then scale.Scale = 1 end
		end
	end

	-- Auto-Close Loop
	task.spawn(function()
		while isMenuOpen do
			task.wait(CHECK_RATE)

			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")

			if not root or not activeSellPart then
				closeSellMenu()
				break
			end

			local distance = (root.Position - activeSellPart.Position).Magnitude

			if distance > MAX_DISTANCE then
				closeSellMenu()
				break
			end
		end
	end)
end

-- [ SETUP FUNCTION ]
-- This function runs every time the player spawns to create a fresh GUI
local function setupUI()
	-- 1. Cleanup old reference if it exists (though usually it's destroyed by death)
	if SellGUI then 
		SellGUI:Destroy() 
		SellGUI = nil
	end

	-- 2. Clone fresh GUI
	SellGUI = sourceGui:Clone()
	if SellGUI then
		SellGUI.Parent = playerGui
		SellGUI.Enabled = false
		SellGUI.AlwaysOnTop = true
		SellGUI.MaxDistance = 0

		-- 3. Get New Buttons
		local closeBtn = SellGUI:WaitForChild("Close") :: ImageButton
		local sellEquippedBtn = SellGUI:WaitForChild("SellEquipped") :: ImageButton
		local sellInventoryBtn = SellGUI:WaitForChild("SellInventory") :: ImageButton

		-- 4. Connect New Buttons
		closeBtn.MouseButton1Click:Connect(closeSellMenu)
		setupButtonAnimation(closeBtn)

		sellEquippedBtn.MouseButton1Click:Connect(function()
			if shouldBlockTutorialSell() then
				debugSellTrace("SellEquipped click blocked by tutorial")
				closeSellMenu()
				return
			end
			debugSellTrace("SellEquipped click fired")
			SellEvent:FireServer("Equipped")
			closeSellMenu() 
		end)
		setupButtonAnimation(sellEquippedBtn)

		sellInventoryBtn.MouseButton1Click:Connect(function()
			if shouldBlockTutorialSell() then
				debugSellTrace("SellInventory click blocked by tutorial")
				closeSellMenu()
				return
			end
			debugSellTrace("SellInventory click fired")
			SellEvent:FireServer("Inventory")
			closeSellMenu() 
		end)
		setupButtonAnimation(sellInventoryBtn)
	end
end

local function connectSellPart(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end

	if instance:GetAttribute("SellTouchConnected") then
		return
	end

	instance:SetAttribute("SellTouchConnected", true)

	instance.Touched:Connect(function(hit)
		local now = tick()
		if now - lastInteraction < DEBOUNCE_TIME then
			return
		end

		local character = hit.Parent
		if character ~= player.Character then
			return
		end

		local humanoid = character:FindFirstChild("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		if not root or not root:IsA("BasePart") then
			return
		end

		if not isWithinOwnBaseInteractionRange(root.Position) then
			return
		end

		if shouldBlockTutorialSell() then
			debugSellTrace(("SellPart touched but blocked by tutorial part=%s"):format(instance:GetFullName()))
			return
		end

		lastInteraction = now
		openSellMenu(instance)
	end)
end

for _, taggedPart in ipairs(CollectionService:GetTagged("SellPart")) do
	connectSellPart(taggedPart)
end

CollectionService:GetInstanceAddedSignal("SellPart"):Connect(connectSellPart)

-- Setup UI immediately on load
setupUI()

-- Re-Setup UI whenever the character spawns (Fixes the death issue)
player.CharacterAdded:Connect(function()
	-- Wait a brief moment to ensure PlayerGui is ready
	task.wait(0.5) 
	setupUI()
	isMenuOpen = false -- Reset state
	activeSellPart = nil
end)

sourceGui.Enabled = false 
