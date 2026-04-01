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
local currentPostTutorialStage = PostTutorialConfiguration.Stages.WaitingForCharacterMoney
local activeBeam: Beam? = nil
local activeAttachment0: Attachment? = nil
local activeAttachment1: Attachment? = nil
local activeHighlight: Highlight? = nil
local worldTarget: BasePart? = nil
local refreshAccumulator = 0
local reportDebounce: {[string]: number} = {}
local finalMessageHideAt = 0
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

	local backButton = hud:FindFirstChild("Back")
	if backButton and backButton:IsA("GuiButton") then
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

local function syncTutorialGuiLayout(targetButton: GuiButton)
	if tutorialGuiProxyButton then
		tutorialGuiProxyButton.AnchorPoint = Vector2.zero
		tutorialGuiProxyButton.Position = UDim2.fromOffset(targetButton.AbsolutePosition.X, targetButton.AbsolutePosition.Y)
		tutorialGuiProxyButton.Size = UDim2.fromOffset(targetButton.AbsoluteSize.X, targetButton.AbsoluteSize.Y)
		tutorialGuiProxyButton.Rotation = targetButton.Rotation
	end

	local centerX = targetButton.AbsolutePosition.X + (targetButton.AbsoluteSize.X * 0.5)
	local topY = targetButton.AbsolutePosition.Y

	if tutorialGuiCursor then
		local cursorParent: Instance = targetButton
		if tutorialGuiProxyButton and (currentStep == 4 or currentStep == 7) then
			cursorParent = tutorialGuiProxyButton
		end

		if tutorialGuiCursor.Parent ~= cursorParent then
			tutorialGuiCursor.Parent = cursorParent
		end

		tutorialGuiCursor.AnchorPoint = Vector2.zero
		tutorialGuiCursor.Position = UDim2.new(0.7, 0, 0.3, 0)
		applyOverlayZIndex(tutorialGuiCursor, 16)
	end

	if tutorialGuiStepLabel then
		tutorialGuiStepLabel.AnchorPoint = Vector2.new(0.5, 1)
		tutorialGuiStepLabel.Position = UDim2.fromOffset(centerX, topY - 56)
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
	elseif tutorialGuiTargetStep == 7 then
		guiOverlaySuppressedUntil = tick() + 0.5
		reportAction("ShopOpened")
		FrameManager.open("Pickaxes")
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

local function shouldUseTutorialGuiProxy(step: number): boolean
	return step == 4 or step == 7
end

local function shouldShowTutorialGuiBlackout(step: number): boolean
	return step == 4 or step == 7
end

local function getTutorialGuiTarget(step: number): GuiButton?
	if step == 4 then
		local backButton = hud:FindFirstChild("Back")
		if backButton and backButton:IsA("GuiButton") then
			return backButton
		end
	elseif step == 7 then
		return findBombShopButton()
	elseif step == 8 then
		return findBombBuyButton()
	end

	return nil
end

local function refreshTutorialGuiOverlay()
	local backButton = hud:FindFirstChild("Back")
	if backButton and backButton:IsA("GuiButton") and currentStep ~= 4 then
		setHudBackButtonHidden(backButton, false)
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

	if currentStep == 4 then
		local stepDefinition = TutorialConfiguration.Steps[currentStep]
		if not tutorialGuiStepLabel or tutorialGuiStepLabel.Parent ~= tutorialGuiOverlay then
			createTutorialGuiLabel(stepDefinition and stepDefinition.Text or "")
		elseif stepDefinition then
			tutorialGuiStepLabel.Text = stepDefinition.Text
		end
	else
		destroyTutorialGuiLabel()
	end

	if shouldUseTutorialGuiProxy(currentStep) then
		if not tutorialGuiProxyButton
			or tutorialGuiProxyButton.Parent ~= tutorialGuiOverlay
			or tutorialGuiTargetStep ~= currentStep then
			createTutorialGuiProxyButton(targetButton)
		end
	else
		destroyTutorialGuiProxyButton()
	end

	if currentStep == 4 and targetButton:IsA("GuiButton") then
		setHudBackButtonHidden(targetButton, true)
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
		if hasEquippedBrainrot() then
			return findClosestFreeSlot()
		end
		return nil
	elseif step == 6 then
		return findClosestCollectTouch()
	elseif step == 7 or step == 8 then
		if not pickaxesFrame.Visible then
			return findClosestTaggedPart("ShopPart")
		end
		return nil
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
		hideTutorialGuiOverlay()
		clearAllTargets()
		return
	end

	if currentStep < TutorialConfiguration.FinalStep then
		instructionsLabel.Text = stepDefinition.Text
		instructionsLabel.Visible = true

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

	hideTutorialGuiOverlay()
	clearExpiredPostTutorialCompletion()

	if tick() < finalMessageHideAt then
		instructionsLabel.Text = stepDefinition.Text
		instructionsLabel.Visible = true
		clearAllTargets(true)
		return
	end

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
	local savedStep = player:GetAttribute("OnboardingStep")
	if type(savedStep) ~= "number" then
		return
	end

	local clampedStep = math.clamp(savedStep, 1, TutorialConfiguration.FinalStep)
	if currentStep ~= clampedStep then
		local previousStep = currentStep
		if previousStep > 0 and previousStep < TutorialConfiguration.FinalStep and clampedStep >= TutorialConfiguration.FinalStep then
			finalMessageHideAt = tick() + 10
		end
		currentStep = clampedStep
	end

	local savedPostTutorialStage = player:GetAttribute("PostTutorialStage")
	if type(savedPostTutorialStage) == "number" then
		currentPostTutorialStage = PostTutorialConfiguration.ClampStage(savedPostTutorialStage)
	else
		currentPostTutorialStage = PostTutorialConfiguration.Stages.WaitingForCharacterMoney
	end

	applyStepPresentation()
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
				reportAction("ShopOpened")
				task.defer(refreshCurrentStep)
			end
		end)
	end

	if not upgradesFrame:GetAttribute("TutorialConnected") then
		upgradesFrame:SetAttribute("TutorialConnected", true)
		upgradesFrame:GetPropertyChangedSignal("Visible"):Connect(function()
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
