--!strict
-- LOCATION: StarterPlayerScripts/MusicController

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- [ ASSETS ]
local CollectionZones = Workspace:WaitForChild("Zones")

-- [[ WAITING FOR SOUNDS ]]
local bgMusic = SoundService:WaitForChild("Background") :: Sound
local zoneMusic = SoundService:WaitForChild("CollectionZone") :: Sound

-- [ CONFIG ]
local FADE_TIME = 1.5 
local CHECK_RATE = 0.5 
local lastCheck = 0

-- [ STATE ]
local currentTrack: Sound? = nil

if bgMusic then bgMusic.Looped = true end
if zoneMusic then zoneMusic.Looped = true end

-- [ HELPERS ]
local function isInsideAnyZone(position: Vector3): boolean
	for _, zonePart in ipairs(CollectionZones:GetChildren()) do
		-- ## ADDED: Check specifically for "ZonePart"
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size

			local inside = math.abs(relativePos.X) <= size.X / 2 and
				math.abs(relativePos.Y) <= size.Y / 2 and
				math.abs(relativePos.Z) <= size.Z / 2

			if inside then return true end
		end
	end
	return false
end

local function playTrack(target: Sound)
	if currentTrack == target then return end

	local oldTrack = currentTrack
	currentTrack = target

	if target then
		if not target.IsPlaying then
			target.Volume = 0
			target:Play()
		end
		TweenService:Create(target, TweenInfo.new(FADE_TIME), {Volume = 0.5}):Play()
	end

	if oldTrack then
		local tween = TweenService:Create(oldTrack, TweenInfo.new(FADE_TIME), {Volume = 0})
		tween:Play()
		tween.Completed:Connect(function()
			if currentTrack ~= oldTrack then oldTrack:Stop() end
		end)
	end
end

-- [ MAIN LOOP ]
RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastCheck < CHECK_RATE then return end
	lastCheck = now

	local char = player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return end

	if isInsideAnyZone(root.Position) then
		playTrack(zoneMusic)
	else
		playTrack(bgMusic)
	end
end)

print("[MusicController] Initialized & Looping Enforced")