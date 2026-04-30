--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local JOYSTICK_SCALE = 1.5

type OriginalLayout = {
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local originalLayouts: {[GuiObject]: OriginalLayout} = {}
local rescaleToken = 0

local function contains(value: string, needle: string): boolean
	return string.find(string.lower(value), needle, 1, true) ~= nil
end

local function isExcludedControl(guiObject: GuiObject): boolean
	local name = guiObject.Name
	return contains(name, "jump")
		or contains(name, "bomb")
		or contains(name, "backpack")
		or contains(name, "hotbar")
end

local function hasMovementJoystickAncestor(instance: Instance, touchGui: ScreenGui): boolean
	local current = instance.Parent
	while current and current ~= touchGui do
		local name = string.lower(current.Name)
		if name == "dynamicthumbstickframe" or name == "thumbstickframe" or name == "dpadframe" then
			return true
		end
		current = current.Parent
	end

	return false
end

local function shouldScaleJoystickObject(instance: Instance, touchGui: ScreenGui): boolean
	if not instance:IsA("GuiObject") then
		return false
	end

	if isExcludedControl(instance) then
		return false
	end

	local name = string.lower(instance.Name)
	if name == "touchcontrolframe" or name == "dynamicthumbstickframe" then
		return false
	end

	return string.find(name, "thumbstick", 1, true) ~= nil
		or string.find(name, "joystick", 1, true) ~= nil
		or string.find(name, "dpad", 1, true) ~= nil
		or hasMovementJoystickAncestor(instance, touchGui)
end

local function scaledOffset(offset: number): number
	return math.round(offset * JOYSTICK_SCALE)
end

local function scaleSize(size: UDim2): UDim2
	return UDim2.new(
		size.X.Scale,
		scaledOffset(size.X.Offset),
		size.Y.Scale,
		scaledOffset(size.Y.Offset)
	)
end

local function getCenteredPosition(layout: OriginalLayout, newSize: UDim2): UDim2
	local anchorOffsetX = 0.5 - layout.AnchorPoint.X
	local anchorOffsetY = 0.5 - layout.AnchorPoint.Y

	local centerXScale = layout.Position.X.Scale + layout.Size.X.Scale * anchorOffsetX
	local centerXOffset = layout.Position.X.Offset + layout.Size.X.Offset * anchorOffsetX
	local centerYScale = layout.Position.Y.Scale + layout.Size.Y.Scale * anchorOffsetY
	local centerYOffset = layout.Position.Y.Offset + layout.Size.Y.Offset * anchorOffsetY

	return UDim2.new(
		centerXScale - newSize.X.Scale * anchorOffsetX,
		math.round(centerXOffset - newSize.X.Offset * anchorOffsetX),
		centerYScale - newSize.Y.Scale * anchorOffsetY,
		math.round(centerYOffset - newSize.Y.Offset * anchorOffsetY)
	)
end

local function scaleJoystickObject(guiObject: GuiObject)
	local layout = originalLayouts[guiObject]
	if not layout then
		layout = {
			Size = guiObject.Size,
			Position = guiObject.Position,
			AnchorPoint = guiObject.AnchorPoint,
		}
		originalLayouts[guiObject] = layout
	end

	local newSize = scaleSize(layout.Size)
	guiObject.Size = newSize
	guiObject.Position = getCenteredPosition(layout, newSize)
end

local function scaleTouchGui(touchGui: ScreenGui)
	for _, descendant in ipairs(touchGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and shouldScaleJoystickObject(descendant, touchGui) then
			scaleJoystickObject(descendant)
		end
	end
end

local function getTouchGui(): ScreenGui?
	local touchGui = playerGui:FindFirstChild("TouchGui")
	if touchGui and touchGui:IsA("ScreenGui") then
		return touchGui
	end

	return nil
end

local function applyJoystickScale()
	if not UserInputService.TouchEnabled then
		return
	end

	local touchGui = getTouchGui()
	if not touchGui then
		return
	end

	scaleTouchGui(touchGui)
end

local function scheduleJoystickScale()
	rescaleToken += 1
	local token = rescaleToken

	task.defer(function()
		if token == rescaleToken then
			applyJoystickScale()
		end
	end)
end

if UserInputService.TouchEnabled then
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "TouchGui" then
			scheduleJoystickScale()

			child.DescendantAdded:Connect(function()
				scheduleJoystickScale()
			end)
		end
	end)

	local touchGui = getTouchGui()
	if touchGui then
		touchGui.DescendantAdded:Connect(function()
			scheduleJoystickScale()
		end)
	end

	for _, delaySeconds in ipairs({0, 0.25, 0.75, 1.5, 3}) do
		task.delay(delaySeconds, applyJoystickScale)
	end
end
