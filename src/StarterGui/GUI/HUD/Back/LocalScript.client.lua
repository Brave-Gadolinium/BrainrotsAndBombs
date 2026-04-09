local BACK_BUTTON_TEXT = "Back to base"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrameManager = require(ReplicatedStorage.Modules.FrameManager)

local button = script.Parent

local function applyBackButtonCopy(target: Instance)
	if target:IsA("TextButton") or target:IsA("TextLabel") then
		--target.Text = BACK_BUTTON_TEXT
	end
end

local function shouldShowBackButton(): boolean
	if not button:IsA("GuiButton") then
		return false
	end

	if FrameManager.isAnyFrameOpen() then
		return false
	end

	return button:GetAttribute("HUDModeVisible") == true
end

local function refreshBackButtonVisibility()
	if not button:IsA("GuiButton") then
		return
	end

	local visible = shouldShowBackButton()
	button.Visible = visible
	button.Active = visible
end

applyBackButtonCopy(button)

local label = button:FindFirstChild("Text", true)
if label then
	applyBackButtonCopy(label)
end

button.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "Text" or descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
		applyBackButtonCopy(descendant)
	end
end)

button.MouseButton1Click:Connect(function()
	game.ReplicatedStorage.Remotes.Helper.TeleportPlayer:FireServer()
end)

FrameManager.Changed:Connect(refreshBackButtonVisibility)
button:GetAttributeChangedSignal("HUDModeVisible"):Connect(refreshBackButtonVisibility)

refreshBackButtonVisibility()
