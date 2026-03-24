--!strict
-- LOCATION: StarterPlayerScripts/SellController

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- [ NPC REFERENCES ]
local sellNPC = Workspace:WaitForChild("SellNPC")
local proxPart = sellNPC:WaitForChild("ProxPart")
local prompt = proxPart:WaitForChild("ProximityPrompt") :: ProximityPrompt
local sourceGui = sellNPC:WaitForChild("SellGUI") -- The template inside the NPC

-- [ CONFIG ]
local MAX_DISTANCE = prompt.MaxActivationDistance + 5 
local CHECK_RATE = 0.2

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
	isMenuOpen = false

	-- ## FIX: Robust Re-Enable Logic ##
	prompt.Enabled = false
	task.delay(0.5, function()
		prompt.Enabled = true
	end)
end

local function openSellMenu()
	if isMenuOpen or not SellGUI then return end
	isMenuOpen = true

	SellGUI.Enabled = true
	prompt.Enabled = false 

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

			if not root or not proxPart then
				closeSellMenu()
				break
			end

			local distance = (root.Position - proxPart.Position).Magnitude

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
		SellGUI.Adornee = proxPart 
		SellGUI.Enabled = false

		-- 3. Get New Buttons
		local closeBtn = SellGUI:WaitForChild("Close") :: ImageButton
		local sellEquippedBtn = SellGUI:WaitForChild("SellEquipped") :: ImageButton
		local sellInventoryBtn = SellGUI:WaitForChild("SellInventory") :: ImageButton

		-- 4. Connect New Buttons
		closeBtn.MouseButton1Click:Connect(closeSellMenu)
		setupButtonAnimation(closeBtn)

		sellEquippedBtn.MouseButton1Click:Connect(function()
			SellEvent:FireServer("Equipped")
			closeSellMenu() 
		end)
		setupButtonAnimation(sellEquippedBtn)

		sellInventoryBtn.MouseButton1Click:Connect(function()
			SellEvent:FireServer("Inventory")
			closeSellMenu() 
		end)
		setupButtonAnimation(sellInventoryBtn)
	end
end

-- [ CONNECTIONS ]

-- Connect the ProximityPrompt (This stays in Workspace, so we don't need to re-connect it)
prompt.Triggered:Connect(openSellMenu)

-- Setup UI immediately on load
setupUI()

-- Re-Setup UI whenever the character spawns (Fixes the death issue)
player.CharacterAdded:Connect(function()
	-- Wait a brief moment to ensure PlayerGui is ready
	task.wait(0.5) 
	setupUI()
	isMenuOpen = false -- Reset state
	prompt.Enabled = true
end)

-- Ensure prompt is enabled on load
sourceGui.Enabled = false 
prompt.Enabled = true

print("[SellController] Loaded - Death Fix Applied")