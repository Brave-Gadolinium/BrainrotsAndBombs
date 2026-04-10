--!strict
-- LOCATION: StarterPlayerScripts/XrayBonusController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientZoneService = require(ReplicatedStorage.Modules.ClientZoneService)
local XrayBonusConfiguration = require(ReplicatedStorage.Modules.XrayBonusConfiguration)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Templates = ReplicatedStorage:WaitForChild("Templates")
local MinesFolder = Workspace:WaitForChild("Mines")

local ATTRIBUTE_HAS_XRAY = "HasXRayBonus"
local ATTRIBUTE_XRAY_ROUND_ID = "XRayRoundId"

local highlightRadius = math.max(1, tonumber(XrayBonusConfiguration.HighlightRadius) or 20)
local refreshInterval = math.max(0.05, tonumber(XrayBonusConfiguration.HighlightRefreshInterval) or 0.2)

local activeHighlights: {[Model]: Highlight} = {}
local activeBeam: Beam? = nil
local activeAttachment0: Attachment? = nil
local activeAttachment1: Attachment? = nil
local activeBeamTarget: BasePart? = nil
local refreshAccumulator = refreshInterval
local warnedMissingBeamTemplate = false

local function getBeamTemplate(): Beam?
	local template = Templates:FindFirstChild("OnboardingBeam")
	if template and template:IsA("Beam") then
		return template
	end

	if not warnedMissingBeamTemplate then
		warn("[XrayBonusController] Templates.OnboardingBeam is missing or is not a Beam.")
		warnedMissingBeamTemplate = true
	end

	return nil
end

local function getAliveRootPart(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function getCurrentRoundId(): number?
	return tonumber(Workspace:GetAttribute("SessionRoundId"))
end

local function cleanupBeam()
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

	activeBeamTarget = nil
end

local function cleanupHighlights()
	for model, highlight in pairs(activeHighlights) do
		activeHighlights[model] = nil
		highlight:Destroy()
	end
end

local function clearAllVisuals()
	cleanupBeam()
	cleanupHighlights()
end

local function isBrainrotModel(instance: Instance): boolean
	return instance:IsA("Model")
		and instance.Name == "SpawnedItem"
		and instance:GetAttribute("IsSpawnedItem") == true
end

local function getBrainrotPrimaryPart(model: Model): BasePart?
	local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	return nil
end

local function isXrayActiveForCurrentRound(): boolean
	if XrayBonusConfiguration.Enabled ~= true then
		return false
	end

	if Workspace:GetAttribute("SessionEnded") == true then
		return false
	end

	if player:GetAttribute(ATTRIBUTE_HAS_XRAY) ~= true then
		return false
	end

	local currentRoundId = getCurrentRoundId()
	if not currentRoundId then
		return false
	end

	return tonumber(player:GetAttribute(ATTRIBUTE_XRAY_ROUND_ID)) == currentRoundId
end

local function ensureHighlight(model: Model)
	local existingHighlight = activeHighlights[model]
	if existingHighlight and existingHighlight.Parent then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "XrayHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = XrayBonusConfiguration.HighlightFillColor
	highlight.FillTransparency = tonumber(XrayBonusConfiguration.HighlightFillTransparency) or 0.45
	highlight.OutlineColor = XrayBonusConfiguration.HighlightOutlineColor
	highlight.OutlineTransparency = tonumber(XrayBonusConfiguration.HighlightOutlineTransparency) or 0
	highlight.Adornee = model
	highlight.Parent = playerGui

	activeHighlights[model] = highlight
end

local function cleanupStaleHighlights(validModels: {[Model]: boolean})
	for model, highlight in pairs(activeHighlights) do
		if not validModels[model] or model.Parent == nil then
			activeHighlights[model] = nil
			highlight:Destroy()
		end
	end
end

local function ensureBeam(targetPart: BasePart)
	local rootPart = getAliveRootPart()
	if not rootPart then
		cleanupBeam()
		return
	end

	if activeBeam
		and activeAttachment0
		and activeAttachment1
		and activeBeamTarget == targetPart
		and activeAttachment0.Parent == rootPart
		and activeAttachment1.Parent == targetPart then
		return
	end

	local beamTemplate = getBeamTemplate()
	if not beamTemplate then
		cleanupBeam()
		return
	end

	cleanupBeam()

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "XrayBeamRootAttachment"
	attachment0.Parent = rootPart
	activeAttachment0 = attachment0

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "XrayBeamTargetAttachment"
	attachment1.Parent = targetPart
	activeAttachment1 = attachment1

	local beam = beamTemplate:Clone()
	beam.Name = "XrayBeam"
	beam.Attachment0 = attachment1
	beam.Attachment1 = attachment0
	beam.Parent = rootPart
	activeBeam = beam
	activeBeamTarget = targetPart
end

local function forEachWorldBrainrot(callback: (Model) -> ())
	for _, mineZone in ipairs(MinesFolder:GetChildren()) do
		for _, child in ipairs(mineZone:GetChildren()) do
			if isBrainrotModel(child) then
				callback(child)
			end
		end
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if isBrainrotModel(child) then
			callback(child)
		end
	end
end

local function refreshXrayVisuals()
	if not isXrayActiveForCurrentRound() or not ClientZoneService.IsInMineZone() then
		clearAllVisuals()
		return
	end

	local rootPart = getAliveRootPart()
	if not rootPart then
		clearAllVisuals()
		return
	end

	local validModels: {[Model]: boolean} = {}
	local nearestTarget: BasePart? = nil
	local nearestDistance = math.huge

	forEachWorldBrainrot(function(model)
		local primaryPart = getBrainrotPrimaryPart(model)
		if not primaryPart then
			return
		end

		local distance = (primaryPart.Position - rootPart.Position).Magnitude
		if distance > highlightRadius then
			return
		end

		validModels[model] = true
		ensureHighlight(model)

		if distance < nearestDistance then
			nearestDistance = distance
			nearestTarget = primaryPart
		end
	end)

	cleanupStaleHighlights(validModels)

	if XrayBonusConfiguration.UseNearestBeam and nearestTarget then
		ensureBeam(nearestTarget)
	else
		cleanupBeam()
	end
end

if XrayBonusConfiguration.Enabled == true then
	player:GetAttributeChangedSignal(ATTRIBUTE_HAS_XRAY):Connect(function()
		refreshXrayVisuals()
	end)

	player:GetAttributeChangedSignal(ATTRIBUTE_XRAY_ROUND_ID):Connect(function()
		refreshXrayVisuals()
	end)

	Workspace:GetAttributeChangedSignal("SessionRoundId"):Connect(function()
		refreshXrayVisuals()
	end)

	Workspace:GetAttributeChangedSignal("SessionEnded"):Connect(function()
		refreshXrayVisuals()
	end)

	ClientZoneService.Changed:Connect(function()
		refreshXrayVisuals()
	end)

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 5)
		refreshXrayVisuals()
	end)

	player.CharacterRemoving:Connect(function()
		clearAllVisuals()
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		refreshAccumulator += deltaTime
		if refreshAccumulator < refreshInterval then
			return
		end

		refreshAccumulator = 0
		refreshXrayVisuals()
	end)

	task.defer(refreshXrayVisuals)
end
