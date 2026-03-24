--!strict
-- LOCATION: ServerScriptService/CollisionController

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local GROUP_NAME = "PlayerCharacters"

-- 1. Create the Collision Group
local function setupCollisionGroup()
	-- Register the group if it doesn't exist
	local success, _ = pcall(function()
		PhysicsService:RegisterCollisionGroup(GROUP_NAME)
	end)

	-- Make the group NOT collide with itself
	PhysicsService:CollisionGroupSetCollidable(GROUP_NAME, GROUP_NAME, false)
end

-- 2. Function to apply the group to parts
local function setCollisionGroup(object: Instance)
	if object:IsA("BasePart") then
		object.CollisionGroup = GROUP_NAME
	end
end

-- 3. Handler for when a character loads
local function onCharacterAdded(character: Model)
	-- Apply to existing parts (Head, Torso, Legs)
	for _, descendant in ipairs(character:GetDescendants()) do
		setCollisionGroup(descendant)
	end

	-- Listen for new parts (Tools, Hats/Accessories loaded after spawn)
	character.DescendantAdded:Connect(setCollisionGroup)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)

	-- If character already exists (edge case)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

-- Initialize
setupCollisionGroup()

Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players who might have joined before the script ran
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print("[CollisionController] Player collisions disabled.")