--!strict
-- LOCATION: StarterPlayerScripts/CollectionZoneController

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- [ MODULES ]
local SatchelFolder = ReplicatedStorage:WaitForChild("Satchel")
local SatchelLoader = SatchelFolder:WaitForChild("SatchelLoader")
local SatchelModule = SatchelLoader:WaitForChild("Satchel")
local Satchel = require(SatchelModule)

-- [ CONFIG ]
local CollectionZones = Workspace:WaitForChild("Zones")

-- [ REFERENCES ]
local player = Players.LocalPlayer

-- [ STATE ]
local currentActiveZoneName = "Init" 

-- [ HELPERS ]
local function getCurrentZoneName(position: Vector3): string
	for _, zonePart in ipairs(CollectionZones:GetChildren()) do
		-- ## Check specifically for multiple parts named "ZonePart"
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size
			if math.abs(relativePos.X) <= size.X/2 and math.abs(relativePos.Y) <= size.Y/2 and math.abs(relativePos.Z) <= size.Z/2 then
				return zonePart.Name -- Will return "ZonePart"
			end
		end
	end
	return "SafeZone"
end

-- [ MAIN LOGIC ]
local function checkZone()
	local char = player.Character
	if not char or not char.PrimaryPart then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return end

	local newZoneName = getCurrentZoneName(root.Position)

	if newZoneName ~= currentActiveZoneName then
		local wasInSafeZone = (currentActiveZoneName == "SafeZone" or currentActiveZoneName == "Init")
		local isNowInSafeZone = (newZoneName == "SafeZone")

		currentActiveZoneName = newZoneName

		if wasInSafeZone and not isNowInSafeZone then
			-- Entered danger zone: Disable backpack
			if Satchel.SetBackpackEnabled then Satchel:SetBackpackEnabled(false) end
		elseif not wasInSafeZone and isNowInSafeZone then
			-- Entered safe zone: Enable backpack
			if Satchel.SetBackpackEnabled then Satchel:SetBackpackEnabled(true) end
		end

		-- Ensure default Roblox backpack is always hidden since we use Satchel
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end
end

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
RunService.Heartbeat:Connect(checkZone)