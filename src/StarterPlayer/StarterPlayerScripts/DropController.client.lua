--!strict
-- LOCATION: StarterPlayerScripts/DropController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientZoneService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClientZoneService"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Events = ReplicatedStorage:WaitForChild("Events")
local DropEvent = Events:WaitForChild("RequestDropItem")

local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")

local characterConnections: {RBXScriptConnection} = {}
local isInMineZone = false
local hasCarryVisual = false
local serverCarriedItemCount = 0
local ALLOW_MANUAL_CARRY_DROP = true
local DROP_BUTTON_NAME = "Drop"
local CARRIED_ITEM_COUNT_ATTRIBUTE = "CarriedItemCount"

local function createDropButton(): TextButton
	local button = Instance.new("TextButton")
	button.Name = DROP_BUTTON_NAME
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -24, 1, -142)
	button.Size = UDim2.fromOffset(96, 40)
	button.BackgroundColor3 = Color3.fromRGB(230, 67, 67)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = "Drop"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Visible = false
	button.ZIndex = 20

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 28, 28)
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = button

	button.Parent = hud
	return button
end

local function getDropButton(): GuiButton
	local existing = hud:FindFirstChild(DROP_BUTTON_NAME) or hud:WaitForChild(DROP_BUTTON_NAME, 5)
	if existing and existing:IsA("GuiButton") then
		return existing
	end

	return createDropButton()
end

local dropButton = getDropButton()

local function refreshServerCarriedItemCount()
	serverCarriedItemCount = math.max(0, math.floor(tonumber(player:GetAttribute(CARRIED_ITEM_COUNT_ATTRIBUTE)) or 0))
end

local function disconnectConnections(connections: {RBXScriptConnection})
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function updateDropButton()
	local isCarrying = hasCarryVisual or serverCarriedItemCount > 0
	local shouldShow = ALLOW_MANUAL_CARRY_DROP and isInMineZone and isCarrying
	dropButton.Visible = shouldShow
	dropButton.Active = shouldShow
	dropButton.AutoButtonColor = shouldShow
end

local function isCarryInstance(instance: Instance): boolean
	return instance.Name == "StackItem" or instance.Name == "HeadStackItem"
end

local function hasCarryInstance(character: Model?): boolean
	if not character then
		return false
	end

	for _, child in ipairs(character:GetChildren()) do
		if isCarryInstance(child) then
			return true
		end
	end

	return false
end

local function refreshCarryingState(character: Model?)
	hasCarryVisual = hasCarryInstance(character)
	updateDropButton()
end

local function bindCharacter(character: Model?)
	disconnectConnections(characterConnections)
	refreshCarryingState(character)

	if not character then
		return
	end

	table.insert(characterConnections, character.ChildAdded:Connect(function(child)
		if isCarryInstance(child) then
			refreshCarryingState(character)
		end
	end))

	table.insert(characterConnections, character.ChildRemoved:Connect(function(child)
		if isCarryInstance(child) then
			refreshCarryingState(character)
		end
	end))
end

dropButton.MouseButton1Click:Connect(function()
	if dropButton.Visible then
		DropEvent:FireServer()
	end
end)

isInMineZone = ClientZoneService.IsInMineZone()
refreshServerCarriedItemCount()
bindCharacter(player.Character)
updateDropButton()

ClientZoneService.Changed:Connect(function(nextZone)
	isInMineZone = nextZone ~= nil
	updateDropButton()
end)

player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
	task.defer(function()
		isInMineZone = ClientZoneService.IsInMineZone()
		updateDropButton()
	end)
end)

player:GetAttributeChangedSignal(CARRIED_ITEM_COUNT_ATTRIBUTE):Connect(function()
	refreshServerCarriedItemCount()
	updateDropButton()
end)

player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
end)

player.CharacterRemoving:Connect(function()
	bindCharacter(nil)
end)
