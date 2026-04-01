local BACK_BUTTON_TEXT = "Back to base"

local button = script.Parent

local function applyBackButtonCopy(target: Instance)
	if target:IsA("TextButton") or target:IsA("TextLabel") then
		--target.Text = BACK_BUTTON_TEXT
	end
end

if button:IsA("GuiButton") then
	button.Visible = true
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
