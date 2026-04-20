--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Modules.Constants)

local MineSpawnUtils = {}

local DEFAULT_MAX_ATTEMPTS_PER_ITEM = 15
local ZONE_Y_OFFSETS = {
	Zone1 = 2,
}

local function clonePositions(source: {Vector3}?): {Vector3}
	local positions = {}
	for _, position in ipairs(source or {}) do
		if typeof(position) == "Vector3" then
			table.insert(positions, position)
		end
	end
	return positions
end

local function isTooClose2D(position: Vector3, existingPositions: {Vector3}, minSpacing: number): boolean
	if minSpacing <= 0 then
		return false
	end

	for _, existingPosition in ipairs(existingPositions) do
		local distance = Vector2.new(position.X - existingPosition.X, position.Z - existingPosition.Z).Magnitude
		if distance < minSpacing then
			return true
		end
	end

	return false
end

local function getRandomMineSpawnCFrameWithinDepthBand(mineZonePart: BasePart, minDepthRatio: number, maxDepthRatio: number): CFrame
	local randomX = (math.random() - 0.5) * (mineZonePart.Size.X * 0.9)
	local randomZ = (math.random() - 0.5) * (mineZonePart.Size.Z * 0.9)
	local halfHeight = mineZonePart.Size.Y * 0.5
	local clampedMinRatio = math.clamp(minDepthRatio, 0, 1)
	local clampedMaxRatio = math.clamp(maxDepthRatio, clampedMinRatio, 1)
	local selectedDepthRatio = clampedMinRatio + ((clampedMaxRatio - clampedMinRatio) * math.random())
	local randomY = halfHeight - (selectedDepthRatio * mineZonePart.Size.Y)
	local extraYOffset = ZONE_Y_OFFSETS[mineZonePart.Name] or 0

	return CFrame.new((mineZonePart.CFrame * CFrame.new(randomX, randomY + extraYOffset, randomZ)).Position)
end

function MineSpawnUtils.BuildSpawnCFrames(mineZonePart: BasePart, requestedCount: number, existingPositions: {Vector3}?, options: {[string]: any}?): {CFrame}
	local minSpacing = math.max(0, tonumber(if type(options) == "table" then options.MinSpacing else nil) or (Constants.MIN_ITEM_SPACING or 0))
	local maxAttemptsPerItem = math.max(1, math.floor(tonumber(if type(options) == "table" then options.MaxAttemptsPerItem else nil) or DEFAULT_MAX_ATTEMPTS_PER_ITEM))
	local applyRandomRotation = if type(options) == "table" and options.RandomRotation ~= nil then options.RandomRotation == true else true
	local minDepthRatio = math.clamp(tonumber(if type(options) == "table" then options.MinDepthRatio else nil) or 0, 0, 1)
	local maxDepthRatio = math.clamp(tonumber(if type(options) == "table" then options.MaxDepthRatio else nil) or 1, minDepthRatio, 1)
	local generatedCFrames = {}
	local occupiedPositions = clonePositions(existingPositions)

	for _ = 1, math.max(0, math.floor(tonumber(requestedCount) or 0)) do
		local selectedCFrame: CFrame? = nil

		for _ = 1, maxAttemptsPerItem do
			local candidateCFrame = getRandomMineSpawnCFrameWithinDepthBand(mineZonePart, minDepthRatio, maxDepthRatio)
			if not isTooClose2D(candidateCFrame.Position, occupiedPositions, minSpacing) then
				selectedCFrame = if applyRandomRotation
					then candidateCFrame * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
					else candidateCFrame
				table.insert(occupiedPositions, candidateCFrame.Position)
				break
			end
		end

		if selectedCFrame then
			table.insert(generatedCFrames, selectedCFrame)
		end
	end

	return generatedCFrames
end

return MineSpawnUtils
