--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local currentCharacter: Model? = nil
local currentDesiredState = false
local descendantAddedConnection: RBXScriptConnection? = nil

local function disconnectCharacterConnection()
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		descendantAddedConnection = nil
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

local function bindCharacter(character: Model)
	disconnectCharacterConnection()
	currentCharacter = character
	setLocalFireEnabled(character, currentDesiredState and not isOnLocalCooldown(character))

	descendantAddedConnection = character.DescendantAdded:Connect(function(descendant)
		if descendant.Name == JETPACK_MODEL_NAME
			or descendant.Name == ROCKET_ATTACHMENT_NAME
			or descendant.Name == FIRE_EMITTER_NAME then
			setLocalFireEnabled(character, currentDesiredState and not isOnLocalCooldown(character))
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

	if currentCharacter == character then
		currentCharacter = nil
	end

	disconnectCharacterConnection()
end)

if player.Character then
	bindCharacter(player.Character)
end
