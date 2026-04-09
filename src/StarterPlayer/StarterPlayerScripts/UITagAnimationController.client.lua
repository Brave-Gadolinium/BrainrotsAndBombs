--!strict
-- LOCATION: StarterPlayerScripts/UITagAnimationController

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ROTATE_TAG = "RotateGui"
local SIZE_TAG = "SizeGui"
local SHAKE_TAG = "ShakeGui"
local SCALE_NAME = "TagAnimationScale"
local ROTATE_DEGREES_PER_SPEED = 18
local SIZE_FREQUENCY = 2.2
local SHAKE_FREQUENCY = 6
local ROTATE_SPEED_MIN = 5
local ROTATE_SPEED_MAX = 10
local SHAKE_ACTIVE_CYCLES = 5
local SHAKE_PAUSE_DURATION = 10

type GuiAnimState = {
	BaseRotation: number,
	HasRotate: boolean,
	HasSize: boolean,
	HasShake: boolean,
	RotateSpeed: number,
	RotateAngle: number,
	SizeSpeed: number,
	SizeAmplitude: number,
	SizePhase: number,
	SizeScale: UIScale,
	ShakeSpeed: number,
	ShakeAmplitude: number,
	ShakePhase: number,
	ShakeCycleProgress: number,
	ShakePauseRemaining: number,
}

local guiStates: {[GuiObject]: GuiAnimState} = {}

local function randomSpeed(minValue: number?, maxValue: number?): number
	local minSpeed = minValue or 1
	local maxSpeed = maxValue or 10
	if maxSpeed <= minSpeed then
		return minSpeed
	end

	return math.random(math.floor(minSpeed * 10), math.floor(maxSpeed * 10)) / 10
end

local function randomRotateSpeed(): number
	return randomSpeed(ROTATE_SPEED_MIN, ROTATE_SPEED_MAX)
end

local function resetShakeState(state: GuiAnimState)
	state.ShakePhase = math.random() * math.pi * 2
	state.ShakeCycleProgress = 0
	state.ShakePauseRemaining = 0
end

local function beginShakePause(state: GuiAnimState)
	state.ShakeCycleProgress = 0
	state.ShakePauseRemaining = SHAKE_PAUSE_DURATION
end

local function ensureScale(guiObject: GuiObject): UIScale
	local existing = guiObject:FindFirstChild(SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = SCALE_NAME
	scale.Scale = 1
	scale.Parent = guiObject
	return scale
end

local function ensureState(guiObject: GuiObject): GuiAnimState
	local existing = guiStates[guiObject]
	if existing then
		return existing
	end

	local state: GuiAnimState = {
		BaseRotation = guiObject.Rotation,
		HasRotate = false,
		HasSize = false,
		HasShake = false,
		RotateSpeed = randomRotateSpeed(),
		RotateAngle = 0,
		SizeSpeed = randomSpeed(),
		SizeAmplitude = math.random(4, 12) / 100,
		SizePhase = math.random() * math.pi * 2,
		SizeScale = ensureScale(guiObject),
		ShakeSpeed = randomSpeed(),
		ShakeAmplitude = math.random(2, 8),
		ShakePhase = math.random() * math.pi * 2,
		ShakeCycleProgress = 0,
		ShakePauseRemaining = 0,
	}

	guiStates[guiObject] = state
	return state
end

local function cleanupState(guiObject: GuiObject)
	local state = guiStates[guiObject]
	if not state then
		return
	end

	if guiObject.Parent then
		guiObject.Rotation = state.BaseRotation
	end

	if state.SizeScale and state.SizeScale.Parent then
		state.SizeScale.Scale = 1
	end

	guiStates[guiObject] = nil
end

local function refreshGuiObject(instance: Instance)
	if not instance:IsA("GuiObject") or not instance:IsDescendantOf(playerGui) then
		return
	end

	local hasRotate = CollectionService:HasTag(instance, ROTATE_TAG)
	local hasSize = CollectionService:HasTag(instance, SIZE_TAG)
	local hasShake = CollectionService:HasTag(instance, SHAKE_TAG)

	if not hasRotate and not hasSize and not hasShake then
		cleanupState(instance)
		return
	end

	local state = ensureState(instance)
	local hadRotate = state.HasRotate
	local hadShake = state.HasShake
	state.HasRotate = hasRotate
	state.HasSize = hasSize
	state.HasShake = hasShake

	if hasRotate and not hadRotate then
		state.RotateSpeed = randomRotateSpeed()
	end

	if hasShake and not hadShake then
		resetShakeState(state)
	elseif not hasShake then
		state.ShakeCycleProgress = 0
		state.ShakePauseRemaining = 0
	end

	if not hasSize then
		state.SizeScale.Scale = 1
	end
end

local function refreshDescendant(instance: Instance)
	if not instance:IsA("GuiObject") then
		return
	end

	refreshGuiObject(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		refreshGuiObject(descendant)
	end
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
	refreshGuiObject(descendant)
end

for _, tagName in ipairs({ROTATE_TAG, SIZE_TAG, SHAKE_TAG}) do
	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
		refreshGuiObject(instance)
	end

	CollectionService:GetInstanceAddedSignal(tagName):Connect(function(instance)
		refreshGuiObject(instance)
	end)

	CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(instance)
		if instance:IsA("GuiObject") then
			refreshGuiObject(instance)
		end
	end)
end

playerGui.DescendantAdded:Connect(function(descendant)
	refreshDescendant(descendant)
end)

playerGui.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("GuiObject") then
		cleanupState(descendant)
	end
end)

RunService.Heartbeat:Connect(function(dt: number)
	for guiObject, state in pairs(guiStates) do
		if not guiObject.Parent or not guiObject:IsDescendantOf(playerGui) then
			cleanupState(guiObject)
			continue
		end

		local rotation = state.BaseRotation

		if state.HasRotate then
			state.RotateAngle = (state.RotateAngle + (state.RotateSpeed * ROTATE_DEGREES_PER_SPEED * dt)) % 360
			rotation += state.RotateAngle
		end

		if state.HasShake then
			if state.ShakePauseRemaining > 0 then
				state.ShakePauseRemaining = math.max(0, state.ShakePauseRemaining - dt)
				if state.ShakePauseRemaining <= 0 then
					resetShakeState(state)
				end
			else
				local phaseDelta = dt * state.ShakeSpeed * SHAKE_FREQUENCY
				state.ShakePhase += phaseDelta
				state.ShakeCycleProgress += phaseDelta / (math.pi * 2)
				rotation += math.sin(state.ShakePhase) * state.ShakeAmplitude

				if state.ShakeCycleProgress >= SHAKE_ACTIVE_CYCLES then
					beginShakePause(state)
				end
			end
		end

		guiObject.Rotation = rotation

		if state.HasSize then
			state.SizePhase += dt * state.SizeSpeed * SIZE_FREQUENCY
			state.SizeScale.Scale = 1 + math.sin(state.SizePhase) * state.SizeAmplitude
		else
			state.SizeScale.Scale = 1
		end
	end
end)
