--!strict
-- LOCATION: StarterPlayerScripts/AutoBombHudController

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ProductConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProductConfigurations"))
local FrameManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FrameManager"))

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestAutoBombState = events:WaitForChild("RequestAutoBombState") :: RemoteEvent
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")

local TOGGLE_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TOGGLE_BUSY_TIMEOUT = 1.5
local TOGGLE_POINT_ON_COLOR = Color3.fromRGB(92, 226, 120)
local TOGGLE_POINT_OFF_COLOR = Color3.fromRGB(255, 84, 84)

local autoBombFrame: GuiObject? = nil
local toggleButton: GuiButton? = nil
local toggleTrack: GuiObject? = nil
local togglePoint: GuiObject? = nil
local toggleTrackSizeConnection: RBXScriptConnection? = nil
local hudVisibilityConnection: RBXScriptConnection? = nil
local pointPositionTween: Tween? = nil
local pointColorTween: Tween? = nil
local toggleBusy = false
local pendingToggleState: boolean? = nil

local refreshHudAutoBomb: () -> ()

local function disconnectToggleTrackConnection()
	if toggleTrackSizeConnection then
		toggleTrackSizeConnection:Disconnect()
		toggleTrackSizeConnection = nil
	end
end

local function disconnectHudVisibilityConnection()
	if hudVisibilityConnection then
		hudVisibilityConnection:Disconnect()
		hudVisibilityConnection = nil
	end
end

local function cancelToggleTweens()
	if pointPositionTween then
		pointPositionTween:Cancel()
		pointPositionTween = nil
	end

	if pointColorTween then
		pointColorTween:Cancel()
		pointColorTween = nil
	end
end

local function reportStorePromptFailed(reason: string)
	reportAnalyticsIntent:FireServer("StorePromptFailed", {
		surface = "autobomb_hud",
		section = "autobomb_hud",
		entrypoint = "toggle",
		productName = "AutoBomb",
		passId = ProductConfigurations.GamePasses.AutoBomb,
		purchaseKind = "gamepass",
		paymentType = "robux",
		reason = reason,
	})
end

local function setButtonText(button: GuiButton?, text: string)
	if not button then
		return
	end

	if button:IsA("TextButton") then
		button.Text = text
		return
	end

	local label = button:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = text
	end
end

local function setPointColorInstant(point: GuiObject, color: Color3)
	if point:IsA("ImageLabel") or point:IsA("ImageButton") then
		point.ImageColor3 = color
	elseif point:IsA("Frame") or point:IsA("TextButton") or point:IsA("TextLabel") then
		point.BackgroundColor3 = color
	end
end

local function tweenPointColor(point: GuiObject, color: Color3)
	if point:IsA("ImageLabel") or point:IsA("ImageButton") then
		pointColorTween = TweenService:Create(point, TOGGLE_TWEEN_INFO, {ImageColor3 = color})
		pointColorTween:Play()
	elseif point:IsA("Frame") or point:IsA("TextButton") or point:IsA("TextLabel") then
		pointColorTween = TweenService:Create(point, TOGGLE_TWEEN_INFO, {BackgroundColor3 = color})
		pointColorTween:Play()
	end
end

local function findAutoBombFrame(): GuiObject?
	local left = hud:FindFirstChild("Left")
	local buttons = left and left:FindFirstChild("Buttons1")
	local frame = buttons and buttons:FindFirstChild("Autobomb")
	if frame and frame:IsA("GuiObject") then
		return frame
	end

	return nil
end

local function findToggleButton(frame: GuiObject?): GuiButton?
	if not frame then
		return nil
	end

	local button = frame:FindFirstChild("Toggle", true)
	if button and button:IsA("GuiButton") then
		return button
	end

	return nil
end

local function findToggleTrack(button: GuiButton?): GuiObject?
	if not button then
		return nil
	end

	local mainFrame = button:FindFirstChild("MainFrame")
	local base = mainFrame and mainFrame:FindFirstChild("Base")
	local back = base and base:FindFirstChild("back")
	if back and back:IsA("GuiObject") then
		return back
	end

	return nil
end

local function findTogglePoint(track: GuiObject?): GuiObject?
	if not track then
		return nil
	end

	local point = track:FindFirstChild("Point")
	if point and point:IsA("GuiObject") then
		return point
	end

	return nil
end

local function shouldShowAutoBomb(): boolean
	if FrameManager.isAnyFrameOpen() then
		return false
	end

	if not autoBombFrame then
		return false
	end

	return autoBombFrame:GetAttribute("HUDModeVisible") == true
end

local function getTogglePointPositions(): (UDim2?, UDim2?)
	local track = toggleTrack
	local point = togglePoint
	if not track or not point then
		return nil, nil
	end

	local trackSize = track.AbsoluteSize
	local pointSize = point.AbsoluteSize
	if trackSize.X <= 0 or trackSize.Y <= 0 or pointSize.X <= 0 or pointSize.Y <= 0 then
		return nil, nil
	end

	local horizontalPadding = math.max(2, math.floor((trackSize.Y - pointSize.Y) * 0.5))
	local availableOffset = math.max(horizontalPadding, trackSize.X - pointSize.X - horizontalPadding)
	local leftPosition = UDim2.new(0, horizontalPadding, 0.5, 0)
	local rightPosition = UDim2.new(0, availableOffset, 0.5, 0)

	return leftPosition, rightPosition
end

local function applyToggleVisualState(isEnabled: boolean, instant: boolean?)
	local track = toggleTrack
	local point = togglePoint
	if not track or not point then
		return
	end

	point.AnchorPoint = Vector2.new(0, 0.5)

	local leftPosition, rightPosition = getTogglePointPositions()
	if not leftPosition or not rightPosition then
		return
	end

	local targetPosition = if isEnabled then rightPosition else leftPosition
	local targetColor = if isEnabled then TOGGLE_POINT_ON_COLOR else TOGGLE_POINT_OFF_COLOR

	cancelToggleTweens()

	if instant then
		point.Position = targetPosition
		setPointColorInstant(point, targetColor)
		return
	end

	pointPositionTween = TweenService:Create(point, TOGGLE_TWEEN_INFO, {Position = targetPosition})
	pointPositionTween:Play()
	tweenPointColor(point, targetColor)
end

function refreshHudAutoBomb()
	if not autoBombFrame then
		return
	end

	local hasAutoBomb = player:GetAttribute("HasAutoBomb") == true
	local actualState = player:GetAttribute("AutoBombEnabled") == true
	local displayedState = if pendingToggleState ~= nil then pendingToggleState else actualState
	local shouldShow = shouldShowAutoBomb()

	autoBombFrame.Visible = shouldShow

	if toggleButton then
		toggleButton.Active = not toggleBusy
		toggleButton.AutoButtonColor = not toggleBusy
		if hasAutoBomb then
			setButtonText(toggleButton, if displayedState then "On" else "Off")
		else
			setButtonText(toggleButton, "Buy")
		end
	end

	applyToggleVisualState(displayedState, not shouldShow)
end

local function beginToggleRequest(nextState: boolean)
	toggleBusy = true
	pendingToggleState = nextState
	refreshHudAutoBomb()

	task.delay(TOGGLE_BUSY_TIMEOUT, function()
		if pendingToggleState == nextState then
			toggleBusy = false
			pendingToggleState = nil
			refreshHudAutoBomb()
		end
	end)
end

local function bindToggleButton(button: GuiButton?)
	if not button or button:GetAttribute("AutoBombHudBound") == true then
		return
	end

	button:SetAttribute("AutoBombHudBound", true)
	button.Activated:Connect(function()
		if toggleBusy then
			return
		end

		if player:GetAttribute("HasAutoBomb") == true then
			local nextState = not (player:GetAttribute("AutoBombEnabled") == true)
			beginToggleRequest(nextState)

			reportAnalyticsIntent:FireServer("AutoBombToggleRequested", {
				surface = "autobomb_hud",
				enabled = nextState,
			})
			requestAutoBombState:FireServer(nextState)
			return
		end

		local passId = ProductConfigurations.GamePasses.AutoBomb
		if type(passId) == "number" and passId > 0 then
			reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
				surface = "autobomb_hud",
				section = "autobomb_hud",
				entrypoint = "toggle",
				productName = "AutoBomb",
				passId = passId,
				purchaseKind = "gamepass",
				paymentType = "robux",
			})
			local success, err = pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, passId)
			end)
			if not success then
				warn("[AutoBombHudController] Failed to prompt AutoBomb pass:", err)
				reportStorePromptFailed("prompt_failed")
			end
		else
			reportStorePromptFailed("missing_pass_id")
		end
	end)
end

local function bindToggleTrack(track: GuiObject?)
	if toggleTrack == track then
		return
	end

	disconnectToggleTrackConnection()
	toggleTrack = track

	if toggleTrack then
		toggleTrackSizeConnection = toggleTrack:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			refreshHudAutoBomb()
		end)
	end
end

local function bindHudVisibility(frame: GuiObject?)
	if autoBombFrame == frame and hudVisibilityConnection then
		return
	end

	disconnectHudVisibilityConnection()
	autoBombFrame = frame

	if autoBombFrame then
		hudVisibilityConnection = autoBombFrame:GetAttributeChangedSignal("HUDModeVisible"):Connect(refreshHudAutoBomb)
	end
end

local function resolveHudAutoBomb()
	bindHudVisibility(findAutoBombFrame())
	toggleButton = findToggleButton(autoBombFrame)
	bindToggleTrack(findToggleTrack(toggleButton))
	togglePoint = findTogglePoint(toggleTrack)

	bindToggleButton(toggleButton)
	refreshHudAutoBomb()
end

local function onAutoBombStateChanged()
	toggleBusy = false
	pendingToggleState = nil
	refreshHudAutoBomb()
end

hud.DescendantAdded:Connect(function(descendant)
	local name = descendant.Name
	if name == "Autobomb" or name == "Toggle" or name == "MainFrame" or name == "Base" or name == "back" or name == "Point" then
		task.defer(resolveHudAutoBomb)
	end
end)

hud.DescendantRemoving:Connect(function(descendant)
	if descendant == autoBombFrame or descendant == toggleButton or descendant == toggleTrack or descendant == togglePoint then
		task.defer(resolveHudAutoBomb)
	end
end)

player:GetAttributeChangedSignal("HasAutoBomb"):Connect(onAutoBombStateChanged)
player:GetAttributeChangedSignal("AutoBombEnabled"):Connect(onAutoBombStateChanged)
FrameManager.Changed:Connect(refreshHudAutoBomb)

resolveHudAutoBomb()
