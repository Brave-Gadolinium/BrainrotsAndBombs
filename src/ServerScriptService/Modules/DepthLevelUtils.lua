--!strict

local Workspace = game:GetService("Workspace")

local DepthLevelUtils = {}

local minesFolder = Workspace:WaitForChild("Mines")

local function getZoneLevelFromName(name: string): number?
	return tonumber(string.match(name, "^Zone(%d+)$"))
end

local function isInsidePart(position: Vector3, part: BasePart): boolean
	local relativePos = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5

	return math.abs(relativePos.X) <= halfSize.X
		and math.abs(relativePos.Y) <= halfSize.Y
		and math.abs(relativePos.Z) <= halfSize.Z
end

function DepthLevelUtils.GetDepthLevelAtPosition(position: Vector3): number
	local highestLevel = 0

	for _, child in ipairs(minesFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local zoneLevel = getZoneLevelFromName(child.Name)
			if zoneLevel and zoneLevel > highestLevel and isInsidePart(position, child) then
				highestLevel = zoneLevel
			end
		end
	end

	return highestLevel
end

return DepthLevelUtils
