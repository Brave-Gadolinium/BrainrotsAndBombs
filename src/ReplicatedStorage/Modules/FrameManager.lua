--[[
    SCRIPT: FrameManager (MODULE SCRIPT)
    Location: ReplicatedStorage/Modules/FrameManager
--]]
--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local FrameManager = {}

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local framesContainer: Folder = playerGui:WaitForChild("GUI"):WaitForChild("Frames")

local TWEEN_INFO: TweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local BLUR_TWEEN_INFO: TweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BLUR_EFFECT_NAME = "FrameManagerBlur"
local BLUR_VISIBLE_SIZE = 18
local NON_BLOCKING_ATTRIBUTE = "IgnoreFrameManagerBlocking"

local currentlyOpenFrame: GuiObject? = nil
local framePositions: {[GuiObject]: UDim2} = {}
local trackedFrames: {[GuiObject]: {RBXScriptConnection}} = {}
local stateChangedEvent = Instance.new("BindableEvent")
local lastAnyFrameOpen = false
local lastFrameName: string? = nil

FrameManager.Changed = stateChangedEvent.Event

local function isBlockingFrame(frame: Instance): boolean
	return frame:IsA("GuiObject")
		and frame.Name ~= "Notifications"
		and frame:GetAttribute(NON_BLOCKING_ATTRIBUTE) ~= true
end

local function ensureBlurEffect(): BlurEffect
	local existing = Lighting:FindFirstChild(BLUR_EFFECT_NAME)
	if existing and existing:IsA("BlurEffect") then
		return existing
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = BLUR_EFFECT_NAME
	blur.Size = 0
	blur.Enabled = true
	blur.Parent = Lighting
	return blur
end

local function updateBlur(anyFrameOpen: boolean)
	local blur = ensureBlurEffect()
	local targetSize = if anyFrameOpen then BLUR_VISIBLE_SIZE else 0
	if math.abs(blur.Size - targetSize) < 0.01 then
		return
	end

	TweenService:Create(blur, BLUR_TWEEN_INFO, {Size = targetSize}):Play()
end

local function getVisibleBlockingFrame(): GuiObject?
	if currentlyOpenFrame
		and currentlyOpenFrame.Parent
		and currentlyOpenFrame.Visible
		and isBlockingFrame(currentlyOpenFrame)
	then
		return currentlyOpenFrame
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if child:IsA("GuiObject") and isBlockingFrame(child) and child.Visible then
			return child
		end
	end

	return nil
end

local function syncFrameState()
	local visibleFrame = getVisibleBlockingFrame()
	currentlyOpenFrame = visibleFrame

	local anyFrameOpen = visibleFrame ~= nil
	updateBlur(anyFrameOpen)

	local frameName = if visibleFrame then visibleFrame.Name else nil
	if anyFrameOpen ~= lastAnyFrameOpen or frameName ~= lastFrameName then
		lastAnyFrameOpen = anyFrameOpen
		lastFrameName = frameName
		stateChangedEvent:Fire(anyFrameOpen, frameName)
	end
end

local function trackFrame(frame: Instance)
	if not isBlockingFrame(frame) then
		return
	end

	local guiObject = frame :: GuiObject
	if trackedFrames[guiObject] then
		return
	end

	trackedFrames[guiObject] = {
		guiObject:GetPropertyChangedSignal("Visible"):Connect(syncFrameState),
		guiObject:GetAttributeChangedSignal(NON_BLOCKING_ATTRIBUTE):Connect(syncFrameState),
	}
end

local function untrackFrame(frame: Instance)
	if not frame:IsA("GuiObject") then
		return
	end

	local connections = trackedFrames[frame]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		trackedFrames[frame] = nil
	end
end

local function initializeFrame(frame: GuiObject)
	if not framePositions[frame] then
		framePositions[frame] = frame.Position
		local hiddenPosition: UDim2 = UDim2.new(framePositions[frame].X.Scale, framePositions[frame].X.Offset, 1.5, 0)
		frame.Position = hiddenPosition
		frame.Visible = false
	end
end

for _, child in ipairs(framesContainer:GetChildren()) do
	trackFrame(child)
end

framesContainer.ChildAdded:Connect(function(child)
	trackFrame(child)
	task.defer(syncFrameState)
end)

framesContainer.ChildRemoved:Connect(function(child)
	untrackFrame(child)
	task.defer(syncFrameState)
end)

function FrameManager.closeCurrent()
	syncFrameState()
	if currentlyOpenFrame then
		FrameManager.close(currentlyOpenFrame.Name)
	end
end

function FrameManager.close(frameName: string)
	syncFrameState()
	local targetFrame = framesContainer:FindFirstChild(frameName)
	if not targetFrame or not targetFrame.Visible then return end
	if not targetFrame:IsA("GuiObject") then return end

	initializeFrame(targetFrame)
	local hiddenPosition: UDim2 = UDim2.new(framePositions[targetFrame].X.Scale, framePositions[targetFrame].X.Offset, 1.5, 0)

	local slideOutTween: Tween = TweenService:Create(targetFrame, TWEEN_INFO, {Position = hiddenPosition})
	slideOutTween:Play()

	slideOutTween.Completed:Wait()
	targetFrame.Visible = false

	if currentlyOpenFrame == targetFrame then
		currentlyOpenFrame = nil
	end

	syncFrameState()
end

function FrameManager.open(frameName: string)
	syncFrameState()
	local targetFrame = framesContainer:FindFirstChild(frameName)
	if not targetFrame or currentlyOpenFrame == targetFrame then return end
	if not targetFrame:IsA("GuiObject") then return end

	initializeFrame(targetFrame)

	if currentlyOpenFrame then
		FrameManager.close(currentlyOpenFrame.Name)
	end

	targetFrame.Visible = true
	local originalPosition: UDim2 = framePositions[targetFrame]
	local slideInTween: Tween = TweenService:Create(targetFrame, TWEEN_INFO, {Position = originalPosition})
	slideInTween:Play()

	currentlyOpenFrame = targetFrame
	syncFrameState()
end

function FrameManager.connect(button: TextButton | ImageButton, frameName: string, action: "Toggle" | "Open" | "Close"?)
	local targetFrame = framesContainer:FindFirstChild(frameName)
	if not button or not targetFrame then return end
	if not targetFrame:IsA("GuiObject") then return end

	action = action or "Toggle"
	initializeFrame(targetFrame)

	button.MouseButton1Click:Connect(function()
		syncFrameState()
		if action == "Close" then
			FrameManager.close(frameName)
		elseif action == "Open" then
			FrameManager.open(frameName)
		else  -- Toggle
			if currentlyOpenFrame == targetFrame then
				FrameManager.close(frameName)
			else
				FrameManager.open(frameName)
			end
		end
	end)
end

function FrameManager.getCurrentFrameName(): string?
	syncFrameState()
	return currentlyOpenFrame and currentlyOpenFrame.Name or nil
end

function FrameManager.isAnyFrameOpen(): boolean
	syncFrameState()
	return currentlyOpenFrame ~= nil
end

syncFrameState()

return FrameManager
