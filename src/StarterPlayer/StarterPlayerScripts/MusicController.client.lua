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

-- [ CONFIG ]
local FADE_TIME = 1.5
local CHECK_RATE = 0.5
local TARGET_VOLUME = 0.5

-- [ STATE ]
local lastCheck = 0
local currentTrack: Sound? = nil
local currentMusicGroup = ""

local function isInsideAnyZone(position: Vector3): boolean
	for _, zonePart in ipairs(CollectionZones:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size

			local inside = math.abs(relativePos.X) <= size.X / 2
				and math.abs(relativePos.Y) <= size.Y / 2
				and math.abs(relativePos.Z) <= size.Z / 2

			if inside then
				return true
			end
		end
	end

	return false
end

local function getTracksByPrefix(prefix: string): {Sound}
	local tracks = {}

	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("Sound") and string.match(child.Name, "^" .. prefix .. "%d*$") then
			child.Looped = true
			table.insert(tracks, child)
		end
	end

	table.sort(tracks, function(a, b)
		return a.Name < b.Name
	end)

	return tracks
end

local function chooseRandomTrack(tracks: {Sound}, previousTrack: Sound?): Sound?
	if #tracks == 0 then
		return nil
	end

	if #tracks == 1 then
		return tracks[1]
	end

	local candidates = {}
	for _, track in ipairs(tracks) do
		if track ~= previousTrack then
			table.insert(candidates, track)
		end
	end

	if #candidates == 0 then
		return tracks[1]
	end

	return candidates[math.random(1, #candidates)]
end

local function stopOtherTracks(activeTrack: Sound?)
	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("Sound") and child ~= activeTrack then
			child.Volume = 0
			child:Stop()
		end
	end
end

local function playTrack(target: Sound?)
	if not target or currentTrack == target then
		return
	end

	local oldTrack = currentTrack
	currentTrack = target

	if not target.IsPlaying then
		target.Volume = 0
		target:Play()
	end

	TweenService:Create(target, TweenInfo.new(FADE_TIME), {Volume = TARGET_VOLUME}):Play()

	if oldTrack then
		local tween = TweenService:Create(oldTrack, TweenInfo.new(FADE_TIME), {Volume = 0})
		tween:Play()
		tween.Completed:Connect(function()
			if currentTrack ~= oldTrack then
				oldTrack:Stop()
			end
		end)
	end

	stopOtherTracks(target)
end

local function switchMusicGroup(groupName: string)
	if currentMusicGroup == groupName then
		return
	end

	currentMusicGroup = groupName

	local prefix = if groupName == "CollectionZone" then "CollectionZone" else "Background"
	local tracks = getTracksByPrefix(prefix)
	local nextTrack = chooseRandomTrack(tracks, currentTrack)

	if nextTrack then
		playTrack(nextTrack)
	end
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastCheck < CHECK_RATE then
		return
	end
	lastCheck = now

	local char = player.Character
	if not char then
		return
	end

	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then
		return
	end

	if isInsideAnyZone(root.Position) then
		switchMusicGroup("CollectionZone")
	else
		switchMusicGroup("Background")
	end
end)

print("[MusicController] Random music switching initialized")
