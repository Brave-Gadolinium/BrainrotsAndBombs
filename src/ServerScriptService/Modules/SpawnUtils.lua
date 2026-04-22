--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)

local SpawnUtils = {}
local DEFAULT_SPAWN_HEIGHT_OFFSET = 3
local NEW_PLAYER_PART_NAME = "NewPlayerPart"
local NEW_PLAYER_PART_TAG = "NewPlayerPart"
local PLOT_SPAWN_UNLOCK_STEP = math.max(1, math.floor(tonumber(TutorialConfiguration.PlotSpawnUnlockStep) or 5))
local PLOT_TELEPORT_DOWN_OFFSET = 1.25

local function getClosestMiningZonePosition(fromPosition: Vector3): Vector3?
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then
		return nil
	end

	local closestPosition: Vector3? = nil
	local closestDistance = math.huge

	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local offset = zonePart.Position - fromPosition
			local distance = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z

			if distance < closestDistance then
				closestDistance = distance
				closestPosition = zonePart.Position
			end
		end
	end

	return closestPosition
end

local function getNewPlayerSpawnPart(): BasePart?
	local zonesFolder = Workspace:FindFirstChild("Zones")
	local namedPart = if zonesFolder then zonesFolder:FindFirstChild(NEW_PLAYER_PART_NAME) else nil
	if namedPart and namedPart:IsA("BasePart") then
		return namedPart
	end

	for _, taggedInstance in ipairs(CollectionService:GetTagged(NEW_PLAYER_PART_TAG)) do
		if taggedInstance:IsA("BasePart") then
			return taggedInstance
		end
	end

	return nil
end

function SpawnUtils.ShouldUseNewPlayerSpawn(onboardingStep: number?): boolean
	local currentStep = math.max(1, math.floor(tonumber(onboardingStep) or 1))

	return currentStep < PLOT_SPAWN_UNLOCK_STEP
end

function SpawnUtils.GetNewPlayerSpawnCFrame(heightOffset: number?): CFrame?
	local spawnPart = getNewPlayerSpawnPart()
	if not spawnPart then
		return nil
	end

	local offsetY = heightOffset or DEFAULT_SPAWN_HEIGHT_OFFSET
	return spawnPart.CFrame + Vector3.new(0, (spawnPart.Size.Y * 0.5) + offsetY, 0)
end

function SpawnUtils.GetPlotSpawnCFrame(plot: Model, heightOffset: number?): CFrame?
	local offsetY = heightOffset or DEFAULT_SPAWN_HEIGHT_OFFSET
	local spawnPart = plot:FindFirstChild("Spawn", true)
	local anchorPart = if spawnPart and spawnPart:IsA("BasePart") then spawnPart else plot.PrimaryPart

	if not anchorPart then
		return nil
	end

	-- Spawn slightly lower than the raw target to avoid catching overhead base geometry.
	local spawnPosition = anchorPart.Position + Vector3.new(0, offsetY - PLOT_TELEPORT_DOWN_OFFSET, 0)
	local mineZonePosition = getClosestMiningZonePosition(spawnPosition)

	if mineZonePosition then
		local lookTarget = Vector3.new(mineZonePosition.X, spawnPosition.Y, mineZonePosition.Z)
		local horizontalOffset = lookTarget - spawnPosition

		if horizontalOffset.Magnitude > 0.001 then
			return CFrame.lookAt(spawnPosition, lookTarget)
		end
	end

	return anchorPart.CFrame + Vector3.new(0, offsetY, 0)
end

function SpawnUtils.GetCharacterSpawnCFrame(plot: Model?, onboardingStep: number?, heightOffset: number?): CFrame?
	if SpawnUtils.ShouldUseNewPlayerSpawn(onboardingStep) then
		local tutorialSpawnCFrame = SpawnUtils.GetNewPlayerSpawnCFrame(heightOffset)
		if tutorialSpawnCFrame then
			return tutorialSpawnCFrame
		end
	end

	if plot then
		return SpawnUtils.GetPlotSpawnCFrame(plot, heightOffset)
	end

	return nil
end

return SpawnUtils
