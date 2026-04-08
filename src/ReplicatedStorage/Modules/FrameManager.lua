--[[
    SCRIPT: FrameManager (MODULE SCRIPT)
    Location: ReplicatedStorage/Modules/FrameManager
--]]
--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FrameManager = {}

local playerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local framesContainer: Folder = playerGui:WaitForChild("GUI"):WaitForChild("Frames")

local TWEEN_INFO: TweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local currentlyOpenFrame: Frame? = nil
local framePositions: {[Frame]: UDim2} = {}

local function initializeFrame(frame: Frame)
	if not framePositions[frame] then
		framePositions[frame] = frame.Position
		local hiddenPosition: UDim2 = UDim2.new(framePositions[frame].X.Scale, framePositions[frame].X.Offset, 1.5, 0)
		frame.Position = hiddenPosition
		frame.Visible = false
	end
end

function FrameManager.closeCurrent()
	if currentlyOpenFrame then
		FrameManager.close(currentlyOpenFrame.Name)
	end
end

function FrameManager.close(frameName: string)
	local targetFrame: Frame? = framesContainer:FindFirstChild(frameName)
	if not targetFrame or not targetFrame.Visible then return end

	initializeFrame(targetFrame)
	local hiddenPosition: UDim2 = UDim2.new(framePositions[targetFrame].X.Scale, framePositions[targetFrame].X.Offset, 1.5, 0)

	local slideOutTween: Tween = TweenService:Create(targetFrame, TWEEN_INFO, {Position = hiddenPosition})
	slideOutTween:Play()

	slideOutTween.Completed:Wait()
	targetFrame.Visible = false

	if currentlyOpenFrame == targetFrame then
		currentlyOpenFrame = nil
	end
end

function FrameManager.open(frameName: string)
	local targetFrame: Frame? = framesContainer:FindFirstChild(frameName)
	if not targetFrame or currentlyOpenFrame == targetFrame then return end

	initializeFrame(targetFrame)

	if currentlyOpenFrame then
		FrameManager.close(currentlyOpenFrame.Name)
	end

	targetFrame.Visible = true
	local originalPosition: UDim2 = framePositions[targetFrame]
	local slideInTween: Tween = TweenService:Create(targetFrame, TWEEN_INFO, {Position = originalPosition})
	slideInTween:Play()

	currentlyOpenFrame = targetFrame
end

function FrameManager.connect(button: TextButton | ImageButton, frameName: string, action: "Toggle" | "Open" | "Close"?)
	local targetFrame: Frame? = framesContainer:FindFirstChild(frameName)
	if not button or not targetFrame then return end

	action = action or "Toggle"
	initializeFrame(targetFrame)

	button.MouseButton1Click:Connect(function()
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
	return currentlyOpenFrame and currentlyOpenFrame.Name or nil
end

function FrameManager.isAnyFrameOpen(): boolean
	return currentlyOpenFrame ~= nil
end

return FrameManager