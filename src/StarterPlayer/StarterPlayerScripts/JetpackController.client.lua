--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestJetpackState = events:WaitForChild("RequestJetpackState") :: RemoteEvent

local ACTION_NAME = "JetpackJumpOverride"
local JETPACK_MODEL_NAME = "PlayerJetpack"
local ROCKET_ATTACHMENT_NAME = "RocketAttachment"
local FIRE_EMITTER_NAME = "Fire"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value + 1
local COOLDOWN_ATTRIBUTE_NAME = "JetpackCooldownEndsAt"
local MOBILE_JUMP_HOLD_TIMEOUT = 0.18

local currentCharacter: Model? = nil
local currentHumanoid: Humanoid? = nil
local currentDesiredState = false
local descendantAddedConnection: RBXScriptConnection? = nil
local humanoidJumpConnection: RBXScriptConnection? = nil
local humanoidAncestryConnection: RBXScriptConnection? = nil
local mobileHoldHeartbeatConnection: RBXScriptConnection? = nil
local lastMobileJumpPulseAt = 0

local function disconnectCharacterConnection()
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		descendantAddedConnection = nil
	end
end

local function disconnectHumanoidConnections()
	if humanoidJumpConnection then
		humanoidJumpConnection:Disconnect()
		humanoidJumpConnection = nil
	end

	if humanoidAncestryConnection then
		humanoidAncestryConnection:Disconnect()
		humanoidAncestryConnection = nil
	end
end

local function setLocalFireEnabled(character: Model?, enabled: boolean)
	if not character then
		return
	end

	local rocket = character:FindFirstChild(JETPACK_MODEL_NAME)
	if not rocket then
		return
	end

	local rocketAttachment = rocket:FindFirstChild(ROCKET_ATTACHMENT_NAME, true)
	if not rocketAttachment or not rocketAttachment:IsA("Attachment") then
		return
	end

	local fire = rocketAttachment:FindFirstChild(FIRE_EMITTER_NAME)
	if fire and fire:IsA("ParticleEmitter") then
		fire.Enabled = enabled
	end
end

local function isOnLocalCooldown(character: Model?): boolean
	if not character then
		return false
	end

	local cooldownEndsAt = character:GetAttribute(COOLDOWN_ATTRIBUTE_NAME)
	if type(cooldownEndsAt) ~= "number" then
		return false
	end

	return cooldownEndsAt - Workspace:GetServerTimeNow() > 0
end

local function requestState(enabled: boolean)
	if enabled and isOnLocalCooldown(currentCharacter) then
		currentDesiredState = false
		setLocalFireEnabled(currentCharacter, false)
		return
	end

	if currentDesiredState == enabled then
		setLocalFireEnabled(currentCharacter, enabled)
		return
	end

	currentDesiredState = enabled
	requestJetpackState:FireServer(enabled)
	setLocalFireEnabled(currentCharacter, enabled)
end

local function isUsingTouchOnlyControls(): boolean
	return UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
		and not UserInputService.MouseEnabled
end

local function refreshMobileHoldState()
	if not isUsingTouchOnlyControls() then
		return
	end

	if currentDesiredState and (os.clock() - lastMobileJumpPulseAt) > MOBILE_JUMP_HOLD_TIMEOUT then
		requestState(false)
	end
end

local function ensureMobileHoldHeartbeat()
	if mobileHoldHeartbeatConnection then
		return
	end

	mobileHoldHeartbeatConnection = RunService.Heartbeat:Connect(function()
		refreshMobileHoldState()
	end)
end

local function bindHumanoid(humanoid: Humanoid?)
	disconnectHumanoidConnections()
	currentHumanoid = humanoid
	lastMobileJumpPulseAt = 0

	if not humanoid then
		return
	end

	humanoidJumpConnection = humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if not isUsingTouchOnlyControls() then
			return
		end

		if humanoid.Jump ~= true then
			return
		end

		lastMobileJumpPulseAt = os.clock()
		requestState(true)
	end)

	humanoidAncestryConnection = humanoid.AncestryChanged:Connect(function(_, parent)
		if parent == nil and currentHumanoid == humanoid then
			currentHumanoid = nil
		end
	end)
end

local function bindCharacter(character: Model)
	disconnectCharacterConnection()
	currentCharacter = character
	setLocalFireEnabled(character, currentDesiredState and not isOnLocalCooldown(character))
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:IsA("Humanoid") then
		bindHumanoid(humanoid)
	else
		bindHumanoid(nil)
	end

	descendantAddedConnection = character.DescendantAdded:Connect(function(descendant)
		if descendant.Name == JETPACK_MODEL_NAME
			or descendant.Name == ROCKET_ATTACHMENT_NAME
			or descendant.Name == FIRE_EMITTER_NAME then
			setLocalFireEnabled(character, currentDesiredState and not isOnLocalCooldown(character))
		end

		if descendant:IsA("Humanoid") and currentHumanoid ~= descendant then
			bindHumanoid(descendant)
		end
	end)
end

local function onJumpAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		requestState(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		requestState(false)
	end

	return Enum.ContextActionResult.Sink
end

ContextActionService:BindActionAtPriority(
	ACTION_NAME,
	onJumpAction,
	false,
	ACTION_PRIORITY,
	Enum.PlayerActions.CharacterJump
)

ensureMobileHoldHeartbeat()

player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
	if currentDesiredState and not isOnLocalCooldown(character) then
		requestJetpackState:FireServer(true)
	end
end)

player.CharacterRemoving:Connect(function(character)
	requestJetpackState:FireServer(false)
	setLocalFireEnabled(character, false)
	currentDesiredState = false
	currentHumanoid = nil
	lastMobileJumpPulseAt = 0

	if currentCharacter == character then
		currentCharacter = nil
	end

	disconnectCharacterConnection()
	disconnectHumanoidConnections()
end)

if player.Character then
	bindCharacter(player.Character)
end
