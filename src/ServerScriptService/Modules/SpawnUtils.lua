--!strict

local Workspace = game:GetService("Workspace")

local SpawnUtils = {}
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

function SpawnUtils.GetPlotSpawnCFrame(plot: Model, heightOffset: number?): CFrame?
	local offsetY = heightOffset or 3
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

return SpawnUtils
