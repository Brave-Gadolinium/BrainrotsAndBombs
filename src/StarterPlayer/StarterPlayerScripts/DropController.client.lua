--!strict
-- LOCATION: StarterPlayerScripts/DropController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- [ ASSETS ]
local Events = ReplicatedStorage:WaitForChild("Events")
local DropEvent = Events:WaitForChild("RequestDropItem")
local Zones = Workspace:WaitForChild("Zones") 

-- [ UI REFERENCES ]
local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")
local dropButton = hud:WaitForChild("Drop") :: GuiButton 

print("[DropController] Loaded (Smart Visibility Active)")

-- [ HELPERS ]
local function isInsideAnyZone(position: Vector3): boolean
	for _, zonePart in ipairs(Zones:GetChildren()) do
		-- ## Check specifically for "ZonePart"
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size
			if math.abs(relativePos.X) <= size.X / 2 and
				math.abs(relativePos.Y) <= size.Y / 2 and
				math.abs(relativePos.Z) <= size.Z / 2 then
				return true
			end
		end
	end
	return false
end

-- [ BUTTON LOGIC ]
dropButton.MouseButton1Click:Connect(function()
	if dropButton.Visible then
		DropEvent:FireServer()
	end
end)

-- [ UPDATE LOOP ]
RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char then 
		dropButton.Visible = false
		return 
	end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then 
		dropButton.Visible = false
		return 
	end

	local inside = isInsideAnyZone(root.Position)
	local isCarrying = char:FindFirstChild("StackItem") ~= nil

	if inside and isCarrying then
		if not dropButton.Visible then dropButton.Visible = true end
	else
		if dropButton.Visible then dropButton.Visible = false end
	end
end)
