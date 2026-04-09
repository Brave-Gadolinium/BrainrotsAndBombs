--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local zonesFolder = Workspace:WaitForChild("Zones")

local CHECK_INTERVAL = 0.2
local MIN_MOVE_DISTANCE = 2

local ClientZoneService = {}

local changedEvent = Instance.new("BindableEvent")
local currentZone: BasePart? = nil
local lastRootPosition: Vector3? = nil
local lastCheckAt = 0

ClientZoneService.Changed = changedEvent.Event

local function resolveRootPart(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function findZoneAtPosition(position: Vector3): BasePart?
	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size

			local inside = math.abs(relativePos.X) <= size.X * 0.5
				and math.abs(relativePos.Y) <= size.Y * 0.5
				and math.abs(relativePos.Z) <= size.Z * 0.5

			if inside then
				return zonePart
			end
		end
	end

	return nil
end

local function publishZone(position: Vector3?)
	local nextZone = if position then findZoneAtPosition(position) else nil
	if nextZone == currentZone then
		return
	end

	local previousZone = currentZone
	currentZone = nextZone
	changedEvent:Fire(nextZone, previousZone)
end

local function refreshZone(force: boolean?)
	local root = resolveRootPart()
	if not root then
		lastRootPosition = nil
		publishZone(nil)
		return
	end

	local now = os.clock()
	local position = root.Position
	local lastPosition = lastRootPosition
	local movedEnough = not lastPosition or (position - lastPosition).Magnitude >= MIN_MOVE_DISTANCE
	if not force and not movedEnough and (now - lastCheckAt) < CHECK_INTERVAL then
		return
	end

	lastCheckAt = now
	lastRootPosition = position
	publishZone(position)
end

function ClientZoneService.GetCurrentZone(): BasePart?
	refreshZone(true)
	return currentZone
end

function ClientZoneService.IsInMineZone(): boolean
	return ClientZoneService.GetCurrentZone() ~= nil
end

player.CharacterAdded:Connect(function(character)
	lastRootPosition = nil

	character:WaitForChild("HumanoidRootPart", 5)
	refreshZone(true)
end)

player.CharacterRemoving:Connect(function()
	lastRootPosition = nil
	publishZone(nil)
end)

zonesFolder.ChildAdded:Connect(function()
	refreshZone(true)
end)

zonesFolder.ChildRemoved:Connect(function()
	refreshZone(true)
end)

RunService.Heartbeat:Connect(function()
	refreshZone(false)
end)

task.defer(function()
	refreshZone(true)
end)

return ClientZoneService
