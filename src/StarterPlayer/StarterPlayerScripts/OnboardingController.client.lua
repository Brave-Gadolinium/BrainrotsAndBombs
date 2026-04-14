--!strict
-- LOCATION: StarterPlayerScripts/OnboardingController

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PostTutorialConfiguration = require(ReplicatedStorage.Modules.PostTutorialConfiguration)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)
local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local ClientZoneService = require(ReplicatedStorage.Modules.ClientZoneService)

local SatchelFolder = ReplicatedStorage:WaitForChild("Satchel")
local SatchelLoader = SatchelFolder:WaitForChild("SatchelLoader")
local SatchelModule = SatchelLoader:WaitForChild("Satchel")
local Satchel = require(SatchelModule)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Templates = ReplicatedStorage:WaitForChild("Templates")
local BeamTemplate = Templates:WaitForChild("OnboardingBeam")
local Events = ReplicatedStorage:WaitForChild("Events")
local ReportTutorialAction = Events:WaitForChild("ReportTutorialAction") :: RemoteEvent
local ShowPostTutorialCompletion = Events:WaitForChild("ShowPostTutorialCompletion") :: RemoteEvent
local TeleportPlayer = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Helper"):WaitForChild("TeleportPlayer") :: RemoteEvent

local mainGui = playerGui:WaitForChild("GUI")
local frames = mainGui:WaitForChild("Frames")
local hud = mainGui:WaitForChild("HUD")
local notifFrame = frames:WaitForChild("Notifications")
local instructionsLabel = notifFrame:WaitForChild("Instructions") :: TextLabel
local pickaxesFrame = frames:WaitForChild("Pickaxes")
local upgradesFrame = frames:WaitForChild("Upgrades")

type QueuedPostTutorialCompletion = {
	Text: string,
	Duration: number,
}

type ActivePostTutorialCompletion = {
	Text: string,
	HideAt: number,
}

local currentStep = 0
local currentPostTutorialStage = PostTutorialConfiguration.Stages.Completed
local activeBeam: Beam? = nil
local activeAttachment0: Attachment? = nil
local activeAttachment1: Attachment? = nil
local activeHighlight: Highlight? = nil
local worldTarget: BasePart? = nil
local refreshAccumulator = 0
local reportDebounce: {[string]: number} = {}
local tutorialGuiOverlay: ScreenGui? = nil
local tutorialGuiBlackout: Frame? = nil
local tutorialGuiProxyButton: GuiButton? = nil
local tutorialGuiCursor: ImageLabel? = nil
local tutorialGuiStepLabel: TextLabel? = nil
local tutorialGuiPulseScale: UIScale? = nil
local tutorialGuiPulseTween: Tween? = nil
local tutorialGuiTargetStep: number? = nil
local guiOverlaySuppressedUntil = 0
local hiddenHudBackState: {[Instance]: {[string]: any}} = {}
local postTutorialCompletionQueue: {QueuedPostTutorialCompletion} = {}
local activePostTutorialCompletion: ActivePostTutorialCompletion? = nil
local shouldUseTutorialGuiProxy: ((number) -> boolean)? = nil
local getTutorialGuiTarget: ((number) -> GuiButton?)? = nil
local maskedGuiVisibility: {[GuiObject]: boolean} = {}
local maskedGuiEnabled: {[Instance]: boolean} = {}
local lastTutorialInventoryVisible: boolean? = nil
local isRefreshingStep = false
local DEBUG_TUTORIAL = true
local lastMaskKey: string? = nil
local maskActive = false

local function debugTutorialLog(message: string)
	if DEBUG_TUTORIAL then
		print(("[Tutorial][Client] %s"):format(message))
	end
end

local function getCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local function getRootPart(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function cleanupWorldVisuals()
	if activeBeam then
		activeBeam:Destroy()
		activeBeam = nil
	end
	if activeAttachment0 then
		activeAttachment0:Destroy()
		activeAttachment0 = nil
	end
	if activeAttachment1 then
		activeAttachment1:Destroy()
		activeAttachment1 = nil
	end
	if activeHighlight then
		activeHighlight:Destroy()
		activeHighlight = nil
	end

	worldTarget = nil
end

local function cleanupBeamVisuals()
	if activeBeam then
		activeBeam:Destroy()
		activeBeam = nil
	end
	if activeAttachment0 then
		activeAttachment0:Destroy()
		activeAttachment0 = nil
	end
	if activeAttachment1 then
		activeAttachment1:Destroy()
		activeAttachment1 = nil
	end

	worldTarget = nil
end

local function cleanupHighlightVisual()
	if activeHighlight then
		activeHighlight:Destroy()
		activeHighlight = nil
	end
end

local function setupBeam(targetPart: BasePart)
	local rootPart = getCharacter():WaitForChild("HumanoidRootPart") :: BasePart

	if worldTarget == targetPart and activeBeam and activeAttachment0 and activeAttachment1 then
		return
	end

	cleanupBeamVisuals()

	local att0 = Instance.new("Attachment")
	att0.Name = "TutorialAtt0"
	att0.Parent = rootPart
	activeAttachment0 = att0

	local att1 = Instance.new("Attachment")
	att1.Name = "TutorialAtt1"
	att1.Parent = targetPart
	activeAttachment1 = att1

	local beam = BeamTemplate:Clone()
	beam.Attachment0 = att1
	beam.Attachment1 = att0
	beam.Parent = rootPart
	activeBeam = beam
	worldTarget = targetPart
end

local function setupHighlight(targetInstance: Instance)
	if activeHighlight and activeHighlight.Adornee == targetInstance then
		return
	end

	cleanupHighlightVisual()

	local highlight = Instance.new("Highlight")
	highlight.Name = "TutorialHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(255, 225, 80)
	highlight.FillTransparency = 0.35
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineTransparency = 0
	highlight.Adornee = targetInstance
	highlight.Parent = playerGui

	activeHighlight = highlight
end

local function clearAllTargets(keepText: boolean?)
	cleanupWorldVisuals()
	if not keepText then
		instructionsLabel.Visible = false
	end
end

local function clearExpiredPostTutorialCompletion()
	if activePostTutorialCompletion and tick() >= activePostTutorialCompletion.HideAt then
		activePostTutorialCompletion = nil
	end
end

local function getActivePostTutorialCompletion(canStartQueued: boolean): ActivePostTutorialCompletion?
	clearExpiredPostTutorialCompletion()

	if not activePostTutorialCompletion and canStartQueued and #postTutorialCompletionQueue > 0 then
		local nextCompletion = table.remove(postTutorialCompletionQueue, 1)
		activePostTutorialCompletion = {
			Text = nextCompletion.Text,
			HideAt = tick() + nextCompletion.Duration,
		}
	end

	return activePostTutorialCompletion
end

local function reportAction(actionId: string)
	local now = tick()
	local lastReportedAt = reportDebounce[actionId] or 0
	if now - lastReportedAt < 0.25 then
		return
	end

	reportDebounce[actionId] = now
	debugTutorialLog(("ReportAction %s (step=%d)"):format(actionId, currentStep))
	ReportTutorialAction:FireServer(actionId)
end

local function ensureTutorialGuiOverlay()
	if tutorialGuiOverlay and tutorialGuiOverlay.Parent then
		return
	end

	local overlayGui = Instance.new("ScreenGui")
	overlayGui.Name = "TutorialGuiOverlay"
	overlayGui.ResetOnSpawn = false
	overlayGui.IgnoreGuiInset = true
	overlayGui.DisplayOrder = 1000
	overlayGui.Enabled = false
	overlayGui.Parent = playerGui

	local blackout = Instance.new("Frame")
	blackout.Name = "Blackout"
	blackout.Size = UDim2.fromScale(1, 1)
	blackout.Position = UDim2.fromScale(0, 0)
	blackout.BackgroundColor3 = Color3.new(0, 0, 0)
	blackout.BackgroundTransparency = 0.45
	blackout.BorderSizePixel = 0
	blackout.Active = true
	blackout.ZIndex = 1
	blackout.Parent = overlayGui

	tutorialGuiOverlay = overlayGui
	tutorialGuiBlackout = blackout
end

local function stopGuiPulseTween()
	if tutorialGuiPulseTween then
		tutorialGuiPulseTween:Cancel()
		tutorialGuiPulseTween = nil
	end
end

local function removeScripts(instance: Instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function applyOverlayZIndex(instance: Instance, zIndex: number)
	if instance:IsA("GuiObject") then
		instance.ZIndex = zIndex
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = zIndex
		end
	end
end

local function destroyTutorialGuiProxyButton()
	stopGuiPulseTween()

	if tutorialGuiProxyButton then
		tutorialGuiProxyButton:Destroy()
		tutorialGuiProxyButton = nil
	end

	tutorialGuiPulseScale = nil
	tutorialGuiTargetStep = nil
end

local function destroyTutorialGuiCursor()
	if tutorialGuiCursor then
		tutorialGuiCursor:Destroy()
		tutorialGuiCursor = nil
	end
end

local function destroyTutorialGuiLabel()
	if tutorialGuiStepLabel then
		tutorialGuiStepLabel:Destroy()
		tutorialGuiStepLabel = nil
	end
end

local function hideTutorialGuiOverlay()
	destroyTutorialGuiProxyButton()
	destroyTutorialGuiCursor()
	destroyTutorialGuiLabel()

	if tutorialGuiOverlay then
		tutorialGuiOverlay.Enabled = false
	end
end

local function setHudBackButtonHidden(backButton: GuiButton, hidden: boolean)
	if not hidden then
		for instance, originalState in pairs(hiddenHudBackState) do
			if instance.Parent then
				if instance:IsA("GuiObject") and originalState.BackgroundTransparency ~= nil then
					instance.BackgroundTransparency = originalState.BackgroundTransparency
				end
				if (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) and originalState.TextTransparency ~= nil then
					instance.TextTransparency = originalState.TextTransparency
					instance.TextStrokeTransparency = originalState.TextStrokeTransparency
				end
				if (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) and originalState.ImageTransparency ~= nil then
					instance.ImageTransparency = originalState.ImageTransparency
				end
				if instance:IsA("UIStroke") and originalState.Transparency ~= nil then
					instance.Transparency = originalState.Transparency
				end
				if instance:IsA("GuiButton") and originalState.Active ~= nil then
					instance.Active = originalState.Active
					instance.AutoButtonColor = originalState.AutoButtonColor
				end
			end
		end
		table.clear(hiddenHudBackState)
		return
	end

	local function hideInstanceVisual(instance: Instance)
		if hiddenHudBackState[instance] == nil then
			local originalState: {[string]: any} = {}
			if instance:IsA("GuiObject") then
				originalState.BackgroundTransparency = instance.BackgroundTransparency
			end
			if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
				originalState.TextTransparency = instance.TextTransparency
				originalState.TextStrokeTransparency = instance.TextStrokeTransparency
			end
			if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
				originalState.ImageTransparency = instance.ImageTransparency
			end
			if instance:IsA("UIStroke") then
				originalState.Transparency = instance.Transparency
			end
			if instance:IsA("GuiButton") then
				originalState.Active = instance.Active
				originalState.AutoButtonColor = instance.AutoButtonColor
			end
			hiddenHudBackState[instance] = originalState
		end

		if instance:IsA("GuiObject") then
			instance.BackgroundTransparency = 1
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			instance.TextTransparency = 1
			instance.TextStrokeTransparency = 1
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			instance.ImageTransparency = 1
		end
		if instance:IsA("UIStroke") then
			instance.Transparency = 1
		end
		if instance:IsA("GuiButton") then
			instance.Active = false
			instance.AutoButtonColor = false
		end
	end

	hideInstanceVisual(backButton)
	for _, descendant in ipairs(backButton:GetDescendants()) do
		hideInstanceVisual(descendant)
	end
end

local function getCurrentStepPresentation()
	return TutorialConfiguration.GetStepPresentation(currentStep)
end

local function getBackButton(): GuiButton?
	local backButton = hud:FindFirstChild("Back")
	if backButton and backButton:IsA("GuiButton") then
		return backButton
	end

	return nil
end

local function findMoneyLabel(): GuiObject?
	local moneyLabel = hud:FindFirstChild("Money", true)
	if moneyLabel and moneyLabel:IsA("GuiObject") then
		return moneyLabel
	end

	return nil
end

local function findMobileBombButton(): GuiObject?
	local mobileBombButton = mainGui:FindFirstChild("MobileBombButton")
	if mobileBombButton and mobileBombButton:IsA("GuiObject") then
		return mobileBombButton
	end

	return nil
end

local function findMobileJumpButton(): GuiButton?
	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not touchGui then
		return nil
	end

	local directButton = touchGui:FindFirstChild("JumpButton", true)
	if directButton and directButton:IsA("GuiButton") then
		return directButton
	end

	for _, descendant in ipairs(touchGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and string.find(string.lower(descendant.Name), "jump", 1, true) then
			return descendant
		end
	end

	return nil
end

local function findBackpackGui(): ScreenGui?
	local backpackGui = playerGui:FindFirstChild("BackpackGui")
	if backpackGui and backpackGui:IsA("ScreenGui") then
		return backpackGui
	end

	return nil
end

local function isMaskableEnabledInstance(instance: Instance): boolean
	return instance:IsA("ScreenGui") or instance:IsA("SurfaceGui") or instance:IsA("BillboardGui")
end

local function setMaskedGuiVisible(guiObject: GuiObject, visible: boolean)
	if maskedGuiVisibility[guiObject] == nil then
		maskedGuiVisibility[guiObject] = guiObject.Visible
	end

	if guiObject.Visible ~= visible then
		guiObject.Visible = visible
	end
end

local function restoreMaskedGuiVisible(guiObject: GuiObject)
	local originalVisible = maskedGuiVisibility[guiObject]
	if originalVisible == nil then
		return
	end

	maskedGuiVisibility[guiObject] = nil
	if guiObject.Parent then
		if guiObject.Visible ~= originalVisible then
			guiObject.Visible = originalVisible
		end
	end
end

local function setMaskedGuiEnabled(instance: Instance, enabled: boolean)
	if not isMaskableEnabledInstance(instance) then
		return
	end

	if maskedGuiEnabled[instance] == nil then
		maskedGuiEnabled[instance] = (instance :: any).Enabled
	end

	if (instance :: any).Enabled ~= enabled then
		(instance :: any).Enabled = enabled
	end
end

local function restoreMaskedGuiEnabled(instance: Instance)
	local originalEnabled = maskedGuiEnabled[instance]
	if originalEnabled == nil then
		return
	end

	maskedGuiEnabled[instance] = nil
	if instance.Parent and isMaskableEnabledInstance(instance) then
		if (instance :: any).Enabled ~= originalEnabled then
			(instance :: any).Enabled = originalEnabled
		end
	end
end

local function syncTutorialInventoryState(shouldShowInventory: boolean)
	local backpackGui = findBackpackGui()
	if backpackGui then
		backpackGui.Enabled = true
	end

	if Satchel.SetBackpackEnabled then
		if lastTutorialInventoryVisible ~= shouldShowInventory then
			lastTutorialInventoryVisible = shouldShowInventory
			if shouldShowInventory then
				Satchel:SetBackpackEnabled(true)
			else
				Satchel:SetBackpackEnabled(false)
			end
		end
	end
end

local function shouldBackpackBeVisibleOutsideTutorial(): boolean
	return not ClientZoneService.IsInMineZone() and not FrameManager.isAnyFrameOpen()
end

local function restoreTutorialUiMask()
	pickaxesFrame:SetAttribute("IgnoreFrameManagerBlocking", false)
	upgradesFrame:SetAttribute("IgnoreFrameManagerBlocking", false)

	local maskedGuiObjects = {}
	for guiObject in pairs(maskedGuiVisibility) do
		table.insert(maskedGuiObjects, guiObject)
	end
	for _, guiObject in ipairs(maskedGuiObjects) do
		restoreMaskedGuiVisible(guiObject)
	end

	local maskedEnabledInstances = {}
	for instance in pairs(maskedGuiEnabled) do
		table.insert(maskedEnabledInstances, instance)
	end
	for _, instance in ipairs(maskedEnabledInstances) do
		restoreMaskedGuiEnabled(instance)
	end

	local backButton = getBackButton()
	if backButton then
		setHudBackButtonHidden(backButton, false)
	end

	local backpackGui = findBackpackGui()
	if backpackGui then
		backpackGui.Enabled = true
	end

	if Satchel.SetBackpackEnabled then
		Satchel:SetBackpackEnabled(shouldBackpackBeVisibleOutsideTutorial())
	end

	lastTutorialInventoryVisible = nil
	lastMaskKey = nil
	maskActive = false
end

local function getTutorialProxyOffset(step: number): Vector2
	return Vector2.zero
end

local function syncTutorialGuiLayout(targetButton: GuiButton)
	local presentation = getCurrentStepPresentation()
	local proxyOffset = getTutorialProxyOffset(currentStep)

	if tutorialGuiProxyButton then
		tutorialGuiProxyButton.AnchorPoint = Vector2.zero
		local proxyScale = math.max(1, tonumber(presentation.BackProxyScale) or 1)
		local scaledWidth = targetButton.AbsoluteSize.X * proxyScale
		local scaledHeight = targetButton.AbsoluteSize.Y * proxyScale
		local scaledPosition = targetButton.AbsolutePosition
			- Vector2.new((scaledWidth - targetButton.AbsoluteSize.X) * 0.5, (scaledHeight - targetButton.AbsoluteSize.Y) * 0.5)

		tutorialGuiProxyButton.Position = UDim2.fromOffset(
			scaledPosition.X + proxyOffset.X,
			scaledPosition.Y + proxyOffset.Y
		)
		tutorialGuiProxyButton.Size = UDim2.fromOffset(scaledWidth, scaledHeight)
		tutorialGuiProxyButton.Rotation = targetButton.Rotation
	end

	if tutorialGuiCursor then
		local cursorTarget = targetButton
		if tutorialGuiProxyButton and shouldUseTutorialGuiProxy and shouldUseTutorialGuiProxy(currentStep) then
			cursorTarget = tutorialGuiProxyButton
		end

		if tutorialGuiOverlay and tutorialGuiCursor.Parent ~= tutorialGuiOverlay then
			tutorialGuiCursor.Parent = tutorialGuiOverlay
		end

		local targetPos = cursorTarget.AbsolutePosition
		local targetSize = cursorTarget.AbsoluteSize
		tutorialGuiCursor.AnchorPoint = Vector2.zero
		tutorialGuiCursor.Position = UDim2.fromOffset(
			targetPos.X + targetSize.X * 0.7,
			targetPos.Y + targetSize.Y * 0.3
		)
		applyOverlayZIndex(tutorialGuiCursor, 16)
	end
end

local function createTutorialGuiCursor()
	if tutorialGuiCursor or not tutorialGuiOverlay then
		return
	end

	local cursorTemplate = ReplicatedStorage:FindFirstChild("Cursor", true)
	if not cursorTemplate or not cursorTemplate:IsA("ImageLabel") then
		return
	end

	local cursor = cursorTemplate:Clone()
	removeScripts(cursor)
	cursor.Name = "TutorialCursor"
	cursor.Visible = true
	cursor.Parent = tutorialGuiOverlay
	cursor.AnchorPoint = Vector2.zero
	cursor.Position = UDim2.new(0.7, 0, 0.3, 0)
	cursor.Size = UDim2.new(cursor.Size.X.Scale * 2, cursor.Size.X.Offset * 2, cursor.Size.Y.Scale, cursor.Size.Y.Offset)
	applyOverlayZIndex(cursor, 16)
	tutorialGuiCursor = cursor
end

local function createTutorialGuiLabel(text: string)
	if tutorialGuiStepLabel or not tutorialGuiOverlay then
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "TutorialStepLabel"
	label.Size = UDim2.fromOffset(220, 40)
	label.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 20
	label.Font = Enum.Font.GothamBold
	label.TextWrapped = true
	label.Parent = tutorialGuiOverlay
	label.ZIndex = 15

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	tutorialGuiStepLabel = label
end

local function handleTutorialGuiProxyClick()
	if tutorialGuiTargetStep == 4 then
		guiOverlaySuppressedUntil = tick() + 1
		hideTutorialGuiOverlay()
		reportAction("BackPressed")
		TeleportPlayer:FireServer()
	end
end

local function createTutorialGuiProxyButton(targetButton: GuiButton)
	ensureTutorialGuiOverlay()
	destroyTutorialGuiProxyButton()

	local proxyButton = targetButton:Clone()
	removeScripts(proxyButton)
	proxyButton.Name = "TutorialGuiProxy"
	proxyButton.Visible = true
	proxyButton.Active = true
	proxyButton.Selectable = true
	proxyButton.Parent = tutorialGuiOverlay
	tutorialGuiProxyButton = proxyButton
	tutorialGuiTargetStep = currentStep
	applyOverlayZIndex(proxyButton, 10)

	local proxyTextLabel = proxyButton:FindFirstChild("Text", true)
	if proxyTextLabel and proxyTextLabel:IsA("TextLabel") then
		proxyTextLabel.ZIndex = 14
	end

	syncTutorialGuiLayout(targetButton)

	local pulseScale = proxyButton:FindFirstChild("TutorialPulseScale") :: UIScale?
	if not pulseScale then
		pulseScale = Instance.new("UIScale")
		pulseScale.Name = "TutorialPulseScale"
		pulseScale.Parent = proxyButton
	end
	pulseScale.Scale = 1

	local pulseTween = TweenService:Create(
		pulseScale,
		TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{Scale = 1.08}
	)
	pulseTween:Play()

	proxyButton.MouseButton1Click:Connect(function()
		handleTutorialGuiProxyClick()
	end)

	tutorialGuiPulseScale = pulseScale
	tutorialGuiPulseTween = pulseTween
end

local function findBombShopButton(): GuiButton?
	local directButton = hud:FindFirstChild("Pickaxes", true)
	if directButton and directButton:IsA("GuiButton") then
		return directButton
	end

	local fallbackButton = hud:FindFirstChild("PickaxesButton", true)
	if fallbackButton and fallbackButton:IsA("GuiButton") then
		return fallbackButton
	end

	for _, descendant in ipairs(hud:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			local mappedFrameName = descendant.Name:gsub("Button", "")
			if mappedFrameName == "Pickaxes" then
				return descendant
			end
		end
	end

	return nil
end

local function findBombBuyButton(): GuiButton?
	local showcaseFrame = pickaxesFrame:FindFirstChild("Showcase")
	if not showcaseFrame then
		local scrollingFrame = pickaxesFrame:FindFirstChild("ScrollingFrame") or pickaxesFrame:FindFirstChild("Scrolling")
		if scrollingFrame then
			showcaseFrame = scrollingFrame:FindFirstChild("Showcase")
		end
	end
	if not showcaseFrame then
		return nil
	end

	local buttonsFrame = showcaseFrame:FindFirstChild("Buttons")
	local buyButton = buttonsFrame and buttonsFrame:FindFirstChild("Buy")
	if not buyButton then
		buyButton = showcaseFrame:FindFirstChild("Buy", true)
	end
	if buyButton and buyButton:IsA("GuiButton") then
		return buyButton
	end

	return nil
end

local function findCharacterUpgradeButton(): GuiButton?
	local scrollingFrame = upgradesFrame:FindFirstChild("Scrolling")
	if not scrollingFrame then
		return nil
	end

	local upgradeCard = scrollingFrame:FindFirstChild(TutorialConfiguration.TutorialCharacterUpgradeId)
	if not upgradeCard then
		return nil
	end

	local buttonsFrame = upgradeCard:FindFirstChild("Buttons")
	local moneyButton = buttonsFrame and buttonsFrame:FindFirstChild("Money")
	if moneyButton and moneyButton:IsA("GuiButton") then
		return moneyButton
	end

	return nil
end

local function findBaseUpgradeSurfaceGui(): SurfaceGui?
	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then
		return nil
	end

	local upgradeModel = plot:FindFirstChild("UpgradeSlotsButton", true)
	if not upgradeModel then
		return nil
	end

	local upgradeMainGui = upgradeModel:FindFirstChild("MainGUI")
	local surfaceGui = upgradeMainGui and upgradeMainGui:FindFirstChild("SurfaceGuiA")
	if surfaceGui and surfaceGui:IsA("SurfaceGui") then
		return surfaceGui
	end

	local fallbackSurfaceGui = upgradeModel:FindFirstChildWhichIsA("SurfaceGui", true)
	if fallbackSurfaceGui then
		return fallbackSurfaceGui
	end

	return nil
end

local function findBaseUpgradeGuiButton(): GuiButton?
	local surfaceGui = findBaseUpgradeSurfaceGui()
	local frame = surfaceGui and surfaceGui:FindFirstChild("FrameB")
	local button = frame and frame:FindFirstChild("UpgradeButton")
	if button and button:IsA("GuiButton") then
		return button
	end

	if surfaceGui then
		local fallbackButton = surfaceGui:FindFirstChild("UpgradeButton", true)
		if fallbackButton and fallbackButton:IsA("GuiButton") then
			return fallbackButton
		end
	end

	return nil
end

local function getPlayerPlotSurfaceGuis(): {SurfaceGui}
	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then
		return {}
	end

	local surfaceGuis = {}
	for _, descendant in ipairs(plot:GetDescendants()) do
		if descendant:IsA("SurfaceGui") then
			table.insert(surfaceGuis, descendant)
		end
	end

	return surfaceGuis
end

local function isDescendantOfAny(instance: Instance, roots: {Instance}): boolean
	for _, root in ipairs(roots) do
		if instance == root or instance:IsDescendantOf(root) then
			return true
		end
	end

	return false
end

local function collectGuiLineage(targetSet: {[Instance]: boolean}, instance: Instance?)
	local current = instance
	while current and current ~= playerGui do
		targetSet[current] = true
		if current == mainGui then
			break
		end
		current = current.Parent
	end
end

local function applyMaskToRoot(root: Instance, allowedLineage: {[Instance]: boolean}, fullTreeRoots: {Instance})
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			if allowedLineage[descendant] or isDescendantOfAny(descendant, fullTreeRoots) then
				restoreMaskedGuiVisible(descendant)
			else
				setMaskedGuiVisible(descendant, false)
			end
		end
	end
end

local function syncTutorialFrames(presentation)
	pickaxesFrame:SetAttribute("IgnoreFrameManagerBlocking", presentation.ShowPickaxesFrame == true)
	upgradesFrame:SetAttribute("IgnoreFrameManagerBlocking", presentation.ShowUpgradesFrame == true)

	local allowedFrameName: string? = nil
	if presentation.ShowPickaxesFrame then
		allowedFrameName = "Pickaxes"
	elseif presentation.ShowUpgradesFrame then
		allowedFrameName = "Upgrades"
	end

	local currentFrameName = FrameManager.getCurrentFrameName()
	local transitionalFrameName: string? = nil
	if currentStep == 7 then
		transitionalFrameName = "Pickaxes"
	elseif currentStep == 9 then
		transitionalFrameName = "Upgrades"
	end

	if currentFrameName
		and currentFrameName ~= allowedFrameName
		and currentFrameName ~= transitionalFrameName then
		FrameManager.closeCurrent()
	end

	if presentation.ShowUpgradesFrame and not upgradesFrame.Visible then
		task.defer(function()
			local currentPresentation = getCurrentStepPresentation()
			if currentStep == 10 and currentPresentation.ShowUpgradesFrame and not upgradesFrame.Visible then
				FrameManager.open("Upgrades")
			end
		end)
	end
end

local function applyTutorialUiMask(presentation)
	if not presentation.MaskUi then
		if maskActive then
			restoreTutorialUiMask()
		end
		return
	end

	local maskKey = table.concat({
		tostring(currentStep),
		tostring(presentation.ShowText),
		tostring(presentation.ShowMoney),
		tostring(presentation.ShowInventory),
		tostring(presentation.ShowBombShopButton),
		tostring(presentation.ShowPickaxesFrame),
		tostring(presentation.ShowUpgradesFrame),
		tostring(presentation.ShowBaseUpgradeSurfaceButton),
		tostring(presentation.ShowMobileBombButton),
		tostring(presentation.ShowJumpButton),
		tostring(presentation.ShowBackButton),
		tostring(presentation.BackProxyScale),
		tostring(presentation.UseBlackout),
	}, "|")

	if maskActive and lastMaskKey == maskKey then
		return
	end

	maskActive = true
	lastMaskKey = maskKey

	debugTutorialLog(("ApplyMask step=%d text=%s money=%s inv=%s pickaxes=%s upgrades=%s base=%s mobileBomb=%s jump=%s"):format(
		currentStep,
		tostring(presentation.ShowText),
		tostring(presentation.ShowMoney),
		tostring(presentation.ShowInventory),
		tostring(presentation.ShowPickaxesFrame),
		tostring(presentation.ShowUpgradesFrame),
		tostring(presentation.ShowBaseUpgradeSurfaceButton),
		tostring(presentation.ShowMobileBombButton),
		tostring(presentation.ShowJumpButton)
	))

	syncTutorialFrames(presentation)

	local allowedLineage: {[Instance]: boolean} = {}
	local forceVisibleLineage: {[Instance]: boolean} = {}
	local fullTreeRoots = {}

	local function allowFullTree(instance: Instance?)
		if not instance then
			return
		end

		table.insert(fullTreeRoots, instance)
		collectGuiLineage(allowedLineage, instance)
		collectGuiLineage(forceVisibleLineage, instance)
	end

	if presentation.ShowText then
		allowFullTree(instructionsLabel)
	end

	if presentation.ShowMoney then
		allowFullTree(findMoneyLabel())
	end

	if presentation.ShowBombShopButton then
		allowFullTree(findBombShopButton())
	end

	if presentation.ShowBackButton then
		allowFullTree(getBackButton())
	end

	if presentation.ShowPickaxesFrame then
		allowFullTree(pickaxesFrame)
	end

	if presentation.ShowUpgradesFrame then
		allowFullTree(upgradesFrame)
	end

	applyMaskToRoot(hud, allowedLineage, fullTreeRoots)
	applyMaskToRoot(frames, allowedLineage, fullTreeRoots)

	for instance in pairs(forceVisibleLineage) do
		if instance:IsA("GuiObject") then
			setMaskedGuiVisible(instance, true)
		end
	end

	local mobileBombButton = findMobileBombButton()
	if mobileBombButton then
		if presentation.ShowMobileBombButton then
			restoreMaskedGuiVisible(mobileBombButton)
		else
			setMaskedGuiVisible(mobileBombButton, false)
		end
	end

	local jumpButton = findMobileJumpButton()
	if jumpButton then
		if presentation.ShowJumpButton then
			restoreMaskedGuiVisible(jumpButton)
		else
			setMaskedGuiVisible(jumpButton, false)
		end
	end

	syncTutorialInventoryState(presentation.ShowInventory)

	local baseSurfaceGui = findBaseUpgradeSurfaceGui()
	local baseButton = findBaseUpgradeGuiButton()
	for _, surfaceGui in ipairs(getPlayerPlotSurfaceGuis()) do
		local shouldShowSurface = presentation.ShowBaseUpgradeSurfaceButton and surfaceGui == baseSurfaceGui
		if currentStep == 11 or currentStep == 12 then
			setMaskedGuiEnabled(surfaceGui, shouldShowSurface)
		else
			restoreMaskedGuiEnabled(surfaceGui)
		end
	end

	if baseButton then
		setMaskedGuiVisible(baseButton, presentation.ShowBaseUpgradeSurfaceButton)
	end

	local backButton = getBackButton()
	if backButton then
		setHudBackButtonHidden(backButton, presentation.BackProxyScale > 1)
	end

	if tutorialGuiBlackout then
		tutorialGuiBlackout.Visible = presentation.UseBlackout
		tutorialGuiBlackout.Active = presentation.UseBlackout
	end
end

shouldUseTutorialGuiProxy = function(step: number): boolean
	local presentation = TutorialConfiguration.GetStepPresentation(step)
	return presentation.ShowBackButton and (tonumber(presentation.BackProxyScale) or 1) > 1
end

local function shouldShowTutorialGuiBlackout(step: number): boolean
	local presentation = TutorialConfiguration.GetStepPresentation(step)
	return presentation.UseBlackout
end

getTutorialGuiTarget = function(step: number): GuiButton?
	if step == 4 then
		return getBackButton()
	elseif step == 8 then
		return findBombBuyButton()
	elseif step == 10 then
		return findCharacterUpgradeButton()
	elseif step == 11 then
		return findBaseUpgradeGuiButton()
	end

	return nil
end

local function refreshTutorialGuiOverlay()
	local presentation = getCurrentStepPresentation()
	if not presentation.MaskUi then
		hideTutorialGuiOverlay()
		return
	end

	local targetButton = getTutorialGuiTarget(currentStep)
	if not targetButton then
		hideTutorialGuiOverlay()
		return
	end

	local shouldShow = tick() >= guiOverlaySuppressedUntil
		and targetButton.Visible
		and targetButton.AbsoluteSize.X > 0
		and targetButton.AbsoluteSize.Y > 0

	if not shouldShow then
		hideTutorialGuiOverlay()
		return
	end

	ensureTutorialGuiOverlay()
	if tutorialGuiOverlay then
		tutorialGuiOverlay.Enabled = true
	end

	if tutorialGuiBlackout then
		local showBlackout = shouldShowTutorialGuiBlackout(currentStep)
		tutorialGuiBlackout.Visible = showBlackout
		tutorialGuiBlackout.Active = showBlackout
	end

	if not tutorialGuiCursor or tutorialGuiCursor.Parent ~= tutorialGuiOverlay then
		createTutorialGuiCursor()
	end

	destroyTutorialGuiLabel()

	if shouldUseTutorialGuiProxy(currentStep) then
		if not tutorialGuiProxyButton
			or tutorialGuiProxyButton.Parent ~= tutorialGuiOverlay
			or tutorialGuiTargetStep ~= currentStep then
			createTutorialGuiProxyButton(targetButton)
		end
	else
		destroyTutorialGuiProxyButton()
	end

	syncTutorialGuiLayout(targetButton)
end

local function hasEquippedBrainrot(): boolean
	local character = player.Character
	if not character then
		return false
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Mutation") ~= nil then
			return true
		end
	end

	return character:FindFirstChild("StackItem") ~= nil or character:FindFirstChild("HeadStackItem") ~= nil
end

local function findTutorialMiningZonePart(): BasePart?
	local rootPart = getRootPart()
	if not rootPart then
		return nil
	end

	local closestPart: BasePart? = nil
	local closestDistance = math.huge

	for _, instance in ipairs(CollectionService:GetTagged("MiningZoneTutorial")) do
		if instance:IsA("BasePart") then
			local distance = (instance.Position - rootPart.Position).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestPart = instance
			end
		end
	end

	return closestPart
end

local function findClosestBrainrot(): Model?
	local rootPart = getRootPart()
	if not rootPart then
		return nil
	end

	local minesFolder = Workspace:FindFirstChild("Mines")
	if not minesFolder then
		return nil
	end

	local closestItem: Model? = nil
	local closestDistance = math.huge

	for _, mine in ipairs(minesFolder:GetChildren()) do
		for _, item in ipairs(mine:GetChildren()) do
			if item:IsA("Model") and item.Name == "SpawnedItem" and item:GetAttribute("IsSpawnedItem") then
				local primary = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
				if primary then
					local distance = (primary.Position - rootPart.Position).Magnitude
					if distance < closestDistance then
						closestDistance = distance
						closestItem = item
					end
				end
			end
		end
	end

	return closestItem
end

local function getPlayerPlot(): Model?
	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if plot and plot:IsA("Model") then
		return plot
	end

	return nil
end

local function iteratePlotSlots(callback: (Model, BasePart, BasePart?) -> boolean?)
	local plot = getPlayerPlot()
	if not plot then
		return
	end

	for _, floor in ipairs(plot:GetChildren()) do
		if floor:IsA("Model") and floor.Name:match("^Floor%d+$") then
			local slots = floor:FindFirstChild("Slots")
			if slots then
				for _, slot in ipairs(slots:GetChildren()) do
					if slot:IsA("Model") and slot:GetAttribute("IsUnlocked") == true then
						local spawnPart = slot:FindFirstChild("Spawn")
						local collectTouch = slot:FindFirstChild("CollectTouch")
						if spawnPart and spawnPart:IsA("BasePart") then
							local shouldBreak = callback(slot, spawnPart, if collectTouch and collectTouch:IsA("BasePart") then collectTouch else nil)
							if shouldBreak then
								return
							end
						end
					end
				end
			end
		end
	end
end

local function findClosestFreeSlot(): BasePart?
	local rootPart = getRootPart()
	if not rootPart then
		return nil
	end

	local closestSlot: BasePart? = nil
	local closestDistance = math.huge

	iteratePlotSlots(function(_, spawnPart)
		if not spawnPart:FindFirstChild("VisualItem") then
			local distance = (spawnPart.Position - rootPart.Position).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestSlot = spawnPart
			end
		end
		return false
	end)

	return closestSlot
end

local function findClosestCollectTouch(): BasePart?
	local rootPart = getRootPart()
	if not rootPart then
		return nil
	end

	local closestCollect: BasePart? = nil
	local closestDistance = math.huge

	iteratePlotSlots(function(_, spawnPart, collectTouch)
		local collectGui = collectTouch and collectTouch:FindFirstChild("CollectGUI")
		if collectTouch and spawnPart:FindFirstChild("VisualItem") and (not collectGui or not collectGui:IsA("SurfaceGui") or collectGui.Enabled) then
			local distance = (collectTouch.Position - rootPart.Position).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestCollect = collectTouch
			end
		end
		return false
	end)

	return closestCollect
end

local function findClosestTaggedPart(tagName: string): BasePart?
	local rootPart = getRootPart()
	if not rootPart then
		return nil
	end

	local PLOT_OWNERSHIP_FALLBACK_DISTANCE = 90

	local function getOwningPlot(instance: Instance?): Model?
		local current = instance
		while current and current ~= Workspace do
			if current:IsA("Model") and string.match(current.Name, "^Plot_.+") ~= nil then
				return current
			end
			current = current.Parent
		end

		return nil
	end

	local function getPlotOwnerUserId(plot: Model): number?
		local ownerUserId = tonumber(plot:GetAttribute("OwnerUserId"))
		if ownerUserId ~= nil then
			return ownerUserId
		end

		if plot.Name == ("Plot_" .. player.Name) then
			return player.UserId
		end

		return nil
	end

	local function getPlotAnchorPosition(plot: Model): Vector3?
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

	local function getNearestPlotOwnerUserId(position: Vector3): number?
		local closestOwnerUserId: number? = nil
		local closestDistance = math.huge

		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Model") and string.match(child.Name, "^Plot_.+") ~= nil then
				local anchorPosition = getPlotAnchorPosition(child)
				if anchorPosition then
					local distance = (anchorPosition - position).Magnitude
					if distance < closestDistance then
						closestDistance = distance
						closestOwnerUserId = getPlotOwnerUserId(child)
					end
				end
			end
		end

		if closestDistance <= PLOT_OWNERSHIP_FALLBACK_DISTANCE then
			return closestOwnerUserId
		end

		return nil
	end

	local function isOwnPlotPart(instance: Instance): boolean
		local plot = getOwningPlot(instance)
		if not plot then
			if instance:IsA("BasePart") then
				local nearestOwnerUserId = getNearestPlotOwnerUserId(instance.Position)
				if nearestOwnerUserId ~= nil then
					return nearestOwnerUserId == player.UserId
				end
			end
			return true
		end

		local ownerUserId = getPlotOwnerUserId(plot)
		if ownerUserId ~= nil then
			return ownerUserId == player.UserId
		end

		return plot.Name == ("Plot_" .. player.Name)
	end

	local closestPart: BasePart? = nil
	local closestDistance = math.huge

	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
		if instance:IsA("BasePart") and isOwnPlotPart(instance) then
			local distance = (instance.Position - rootPart.Position).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestPart = instance
			end
		end
	end

	return closestPart
end

local function findUpgradeSlotsButtonTarget(): BasePart?
	local plot = getPlayerPlot()
	if not plot then
		return nil
	end

	local upgradeSlotsButton = plot:FindFirstChild("UpgradeSlotsButton", true)
	if not upgradeSlotsButton then
		return nil
	end

	if upgradeSlotsButton:IsA("BasePart") then
		return upgradeSlotsButton
	end

	if upgradeSlotsButton:IsA("Model") then
		return upgradeSlotsButton.PrimaryPart or upgradeSlotsButton:FindFirstChildWhichIsA("BasePart", true)
	end

	return upgradeSlotsButton:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveWorldTargetForStep(step: number): Instance?
	if step == 1 then
		return findTutorialMiningZonePart()
	elseif step == 3 then
		return findClosestBrainrot()
	elseif step == 5 then
		return findClosestFreeSlot()
	elseif step == 6 then
		return findClosestCollectTouch()
	elseif step == 7 or step == 8 then
		if not pickaxesFrame.Visible then
			return findClosestTaggedPart("ShopPart")
		end
		return nil
	elseif step == 9 then
		if not upgradesFrame.Visible then
			return findClosestTaggedPart("UpgradePart")
		end
		return nil
	elseif step == 10 then
		if not upgradesFrame.Visible then
			return findClosestTaggedPart("UpgradePart")
		end
		return nil
	elseif step == 11 then
		return findUpgradeSlotsButtonTarget()
	end

	return nil
end

local function resolvePostTutorialWorldTarget(stage: number): BasePart?
	if stage == PostTutorialConfiguration.Stages.PromptCharacterUpgrade then
		if upgradesFrame.Visible then
			return nil
		end

		return findClosestTaggedPart("UpgradePart")
	elseif stage == PostTutorialConfiguration.Stages.PromptBaseUpgrade then
		return findUpgradeSlotsButtonTarget()
	end

	return nil
end

local function getActivePostTutorialPromptStage(): number?
	if currentPostTutorialStage == PostTutorialConfiguration.Stages.PromptCharacterUpgrade then
		return currentPostTutorialStage
	end

	if currentPostTutorialStage == PostTutorialConfiguration.Stages.PromptBaseUpgrade then
		return currentPostTutorialStage
	end

	return nil
end

local function applyStepPresentation()
	local stepDefinition = TutorialConfiguration.Steps[currentStep]
	if not stepDefinition then
		restoreTutorialUiMask()
		hideTutorialGuiOverlay()
		clearAllTargets()
		return
	end

	local presentation = TutorialConfiguration.GetStepPresentation(currentStep)
	if presentation.MaskUi then
		applyTutorialUiMask(presentation)
		instructionsLabel.Text = stepDefinition.Text
		instructionsLabel.Visible = presentation.ShowText

		local newWorldTarget = resolveWorldTargetForStep(currentStep)
		if newWorldTarget then
			if currentStep == 3 then
				if newWorldTarget:IsA("Model") then
					local targetPart = newWorldTarget.PrimaryPart or newWorldTarget:FindFirstChildWhichIsA("BasePart")
					if targetPart then
						setupBeam(targetPart)
					else
						cleanupBeamVisuals()
					end
					setupHighlight(newWorldTarget)
				else
					cleanupWorldVisuals()
				end
			elseif newWorldTarget:IsA("BasePart") then
				setupBeam(newWorldTarget)
				cleanupHighlightVisual()
			else
				cleanupWorldVisuals()
			end
		else
			cleanupWorldVisuals()
		end

		refreshTutorialGuiOverlay()
		return
	end

	restoreTutorialUiMask()
	hideTutorialGuiOverlay()

	if currentStep < TutorialConfiguration.FinalStep then
		instructionsLabel.Text = stepDefinition.Text
		instructionsLabel.Visible = presentation.ShowText

		local newWorldTarget = resolveWorldTargetForStep(currentStep)
		if newWorldTarget then
			if currentStep == 3 then
				if newWorldTarget:IsA("Model") then
					local targetPart = newWorldTarget.PrimaryPart or newWorldTarget:FindFirstChildWhichIsA("BasePart")
					if targetPart then
						setupBeam(targetPart)
					else
						cleanupBeamVisuals()
					end
					setupHighlight(newWorldTarget)
				else
					cleanupWorldVisuals()
				end
			elseif newWorldTarget:IsA("BasePart") then
				setupBeam(newWorldTarget)
				cleanupHighlightVisual()
			else
				cleanupWorldVisuals()
			end
		else
			clearAllTargets(presentation.ShowText)
		end

		return
	end

	clearExpiredPostTutorialCompletion()

	local postTutorialCompletion = getActivePostTutorialCompletion(true)
	if postTutorialCompletion then
		instructionsLabel.Text = postTutorialCompletion.Text
		instructionsLabel.Visible = true
		clearAllTargets(true)
		return
	end

	local postTutorialPromptStage = getActivePostTutorialPromptStage()
	if postTutorialPromptStage then
		instructionsLabel.Text = PostTutorialConfiguration.PromptTexts[postTutorialPromptStage] or ""
		instructionsLabel.Visible = true

		local newWorldTarget = resolvePostTutorialWorldTarget(postTutorialPromptStage)
		if newWorldTarget then
			setupBeam(newWorldTarget)
			cleanupHighlightVisual()
		else
			cleanupWorldVisuals()
		end

		return
	end

	clearAllTargets()
end

local function refreshCurrentStep()
	if isRefreshingStep then
		return
	end
	isRefreshingStep = true

	local savedStep = player:GetAttribute("OnboardingStep")
	if type(savedStep) ~= "number" then
		isRefreshingStep = false
		return
	end

	local clampedStep = math.clamp(savedStep, 1, TutorialConfiguration.FinalStep)
	if currentStep ~= clampedStep then
		local previousStep = currentStep
		currentStep = clampedStep
		debugTutorialLog(("StepChanged %d -> %d"):format(previousStep, currentStep))
	end

	local savedPostTutorialStage = player:GetAttribute("PostTutorialStage")
	if type(savedPostTutorialStage) == "number" then
		currentPostTutorialStage = PostTutorialConfiguration.ClampStage(savedPostTutorialStage)
	else
		currentPostTutorialStage = PostTutorialConfiguration.Stages.Completed
	end

	applyStepPresentation()
	isRefreshingStep = false
end

local function connectUiReporting()
	local backButton = hud:FindFirstChild("Back")
	if backButton and backButton:IsA("GuiButton") and not backButton:GetAttribute("TutorialConnected") then
		backButton:SetAttribute("TutorialConnected", true)
		backButton.MouseButton1Click:Connect(function()
			reportAction("BackPressed")
		end)
		backButton:GetPropertyChangedSignal("Visible"):Connect(function()
			refreshTutorialGuiOverlay()
		end)
	end

	if not pickaxesFrame:GetAttribute("TutorialConnected") then
		pickaxesFrame:SetAttribute("TutorialConnected", true)
		pickaxesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if pickaxesFrame.Visible then
				debugTutorialLog("PickaxesFrame Visible")
				if pickaxesFrame:GetAttribute("OpenedByTouchTrigger") == true then
					reportAction("ShopOpened")
				end
				task.defer(refreshCurrentStep)
			end
		end)
	end

	if not upgradesFrame:GetAttribute("TutorialConnected") then
		upgradesFrame:SetAttribute("TutorialConnected", true)
		upgradesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if upgradesFrame.Visible then
				debugTutorialLog("UpgradesFrame Visible")
				reportAction("UpgradesOpened")
			end
			task.defer(refreshCurrentStep)
		end)
	end
end

task.spawn(function()
	while player:GetAttribute("OnboardingStep") == nil do
		task.wait(0.25)
	end

	connectUiReporting()
	refreshCurrentStep()
end)

player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
	refreshCurrentStep()
end)

player:GetAttributeChangedSignal("PostTutorialStage"):Connect(function()
	refreshCurrentStep()
end)

ShowPostTutorialCompletion.OnClientEvent:Connect(function(message: string, duration: number?)
	if type(message) ~= "string" or message == "" then
		return
	end

	table.insert(postTutorialCompletionQueue, {
		Text = message,
		Duration = math.max(0, tonumber(duration) or PostTutorialConfiguration.CompletionMessageDuration),
	})

	task.defer(refreshCurrentStep)
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	restoreTutorialUiMask()
	hideTutorialGuiOverlay()
	clearAllTargets(true)
	guiOverlaySuppressedUntil = 0
	connectUiReporting()
	refreshCurrentStep()
end)

RunService.RenderStepped:Connect(function(deltaTime)
	refreshTutorialGuiOverlay()

	refreshAccumulator += deltaTime
	if refreshAccumulator >= 0.25 then
		refreshAccumulator = 0
		refreshCurrentStep()
	end
end)
