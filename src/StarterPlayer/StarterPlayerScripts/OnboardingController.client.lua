--!strict
-- LOCATION: StarterPlayerScripts/OnboardingController

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Templates = ReplicatedStorage:WaitForChild("Templates")
local BeamTemplate = Templates:WaitForChild("OnboardingBeam")
local Events = ReplicatedStorage:WaitForChild("Events")
local ReportTutorialAction = Events:WaitForChild("ReportTutorialAction") :: RemoteEvent

local mainGui = playerGui:WaitForChild("GUI")
local frames = mainGui:WaitForChild("Frames")
local hud = mainGui:WaitForChild("HUD")
local notifFrame = frames:WaitForChild("Notifications")
local instructionsLabel = notifFrame:WaitForChild("Instructions") :: TextLabel
local pickaxesFrame = frames:WaitForChild("Pickaxes")

local currentStep = 0
local activeBeam: Beam? = nil
local activeAttachment0: Attachment? = nil
local activeAttachment1: Attachment? = nil
local activeHighlight: Highlight? = nil
local worldTarget: BasePart? = nil
local refreshAccumulator = 0
local reportDebounce: {[string]: number} = {}
local finalMessageHideAt = 0

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

local function reportAction(actionId: string)
	local now = tick()
	local lastReportedAt = reportDebounce[actionId] or 0
	if now - lastReportedAt < 0.25 then
		return
	end

	reportDebounce[actionId] = now
	ReportTutorialAction:FireServer(actionId)
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
	end

	return nil
end

local function applyStepPresentation()
	local stepDefinition = TutorialConfiguration.Steps[currentStep]
	if not stepDefinition then
		clearAllTargets()
		return
	end

	if currentStep >= TutorialConfiguration.FinalStep then
		instructionsLabel.Text = stepDefinition.Text
		instructionsLabel.Visible = tick() < finalMessageHideAt
		clearAllTargets(true)
		return
	end

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
end

local function refreshCurrentStep()
	local savedStep = player:GetAttribute("OnboardingStep")
	if type(savedStep) ~= "number" then
		return
	end

	local clampedStep = math.clamp(savedStep, 1, TutorialConfiguration.FinalStep)
	if currentStep ~= clampedStep then
		if clampedStep >= TutorialConfiguration.FinalStep then
			finalMessageHideAt = tick() + 10
		end
		currentStep = clampedStep
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

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	clearAllTargets(true)
	connectUiReporting()
	refreshCurrentStep()
end)

RunService.RenderStepped:Connect(function(deltaTime)
	refreshAccumulator += deltaTime
	if refreshAccumulator >= 0.25 then
		refreshAccumulator = 0
		refreshCurrentStep()
	end
end)
