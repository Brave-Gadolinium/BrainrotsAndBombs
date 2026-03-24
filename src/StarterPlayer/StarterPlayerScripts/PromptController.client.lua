--!strict
-- LOCATION: StarterPlayerScripts/PromptController

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- [ ASSETS ]
local Templates = ReplicatedStorage:WaitForChild("Templates")
local CustomPromptTemplate = Templates:WaitForChild("CustomPrompt")

-- [ CONFIGURATION ]
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- [ LOGIC ]
local function setupPrompt(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end

	-- 1. Clone UI
	local promptUI = CustomPromptTemplate:Clone()

	-- 2. Setup References
	local button = promptUI:WaitForChild("Button") :: TextButton
	local tapImage = button:FindFirstChild("TapImage") :: ImageLabel
	local keyLabel = button:FindFirstChild("KeyLabel") :: TextLabel
	local textLabel = promptUI:FindFirstChild("Text") :: TextLabel

	-- 3. Set Text
	if textLabel then
		textLabel.Text = prompt.ActionText
	end

	-- 4. Platform Visibility
	local isMobile = UserInputService.TouchEnabled

	if tapImage then tapImage.Visible = isMobile end
	if keyLabel then 
		keyLabel.Visible = not isMobile 
		keyLabel.Text = prompt.KeyboardKeyCode.Name
	end

	-- 5. Create BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PromptBillboard"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromScale(16, 8) 
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.Adornee = prompt.Parent
	billboard.Parent = PlayerGui

	-- Critical: Ensure the Billboard itself doesn't block, but contents do
	billboard.Active = true 

	promptUI.Parent = billboard

	-- 6. Animate In
	promptUI.Size = UDim2.fromScale(0, 0)
	TweenService:Create(promptUI, TWEEN_INFO, {Size = UDim2.fromScale(1, 1)}):Play()

	-- 7. Cleanup Listener
	local hideListener
	hideListener = prompt.PromptHidden:Connect(function()
		hideListener:Disconnect()
		billboard:Destroy()
	end)

	-- 8. ## INPUT DEBUGGING & HANDLING ##

	button.Active = true
	button.Selectable = true
	button.ZIndex = 10 

	-- Disable Active on everything else
	for _, child in ipairs(promptUI:GetDescendants()) do
		if child ~= button and child:IsA("GuiObject") then
			child.Active = false
		end
	end

	-- Interaction Function
	local function interact()
		print("[Debug] Interact Triggered")
		if prompt.Parent then
			if prompt.HoldDuration > 0 then
				print("   > Start Hold")
				prompt:InputHoldBegin()
			else
				print("   > Instant Fire")
				prompt:InputHoldBegin()
				prompt:InputHoldEnd()
			end
		end
	end

	-- Connection 1: Activated (PC/Console)
	button.Activated:Connect(function()
		interact()
	end)

	-- Connection 2: TouchTap (Mobile Tap)
	button.TouchTap:Connect(function()
		interact()
	end)

	-- Connection 3: InputBegan (Mobile Press)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or 
			input.UserInputType == Enum.UserInputType.MouseButton1 then

			if prompt.Parent then
				prompt:InputHoldBegin()
			end
		end
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or 
			input.UserInputType == Enum.UserInputType.MouseButton1 then

			if prompt.Parent then
				prompt:InputHoldEnd()
			end
		end
	end)
end

ProximityPromptService.PromptShown:Connect(setupPrompt)