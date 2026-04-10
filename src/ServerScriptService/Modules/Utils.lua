--!strict
local Utils = {}

type RagdollState = {
	Token: number,
	AutoRotate: boolean,
	PlatformStand: boolean,
	GettingUpEnabled: boolean,
	RagdollEnabled: boolean,
	Motors: {Motor6D},
	Constraints: {BallSocketConstraint},
	Attachments: {Attachment},
	CollisionStates: {[BasePart]: boolean},
	Connections: {RBXScriptConnection},
}

local activeRagdolls: {[Model]: RagdollState} = {}

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

local function ensureRagdollState(character: Model, humanoid: Humanoid): RagdollState
	local existingState = activeRagdolls[character]
	if existingState then
		return existingState
	end

	local newState: RagdollState = {
		Token = 0,
		AutoRotate = humanoid.AutoRotate,
		PlatformStand = humanoid.PlatformStand,
		GettingUpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp),
		RagdollEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
		Motors = {},
		Constraints = {},
		Attachments = {},
		CollisionStates = {},
		Connections = {},
	}

	activeRagdolls[character] = newState
	return newState
end

local function disconnectConnections(state: RagdollState)
	for _, connection in ipairs(state.Connections) do
		connection:Disconnect()
	end

	table.clear(state.Connections)
end

local function destroyInstances<T>(instances: {T})
	for _, instance in ipairs(instances) do
		if typeof(instance) == "Instance" then
			(instance :: any):Destroy()
		end
	end

	table.clear(instances)
end

local function shouldRagdollMotor(motor: Motor6D): boolean
	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return false
	end

	if part0.Name == "HumanoidRootPart" or part1.Name == "HumanoidRootPart" then
		return false
	end

	if motor.Name == "Neck" then
		return false
	end

	return true
end

local function setRagdollPartCollisions(character: Model, enabled: boolean, state: RagdollState)
	for _, descendant in ipairs(character:GetDescendants()) do
		local isAccessoryPart = descendant.Parent and descendant.Parent:IsA("Accessory")
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" and not isAccessoryPart then
			if enabled then
				if state.CollisionStates[descendant] == nil then
					state.CollisionStates[descendant] = descendant.CanCollide
				end
				descendant.CanCollide = true
			else
				local originalCollision = state.CollisionStates[descendant]
				if originalCollision ~= nil then
					descendant.CanCollide = originalCollision
				end
			end
		end
	end

	if not enabled then
		table.clear(state.CollisionStates)
	end
end

local function buildRagdollRig(character: Model, state: RagdollState)
	if #state.Motors > 0 or #state.Constraints > 0 or #state.Attachments > 0 then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and shouldRagdollMotor(descendant) then
			local attachment0 = Instance.new("Attachment")
			attachment0.Name = "TemporaryRagdollAttachment0"
			attachment0.CFrame = descendant.C0
			attachment0.Parent = descendant.Part0

			local attachment1 = Instance.new("Attachment")
			attachment1.Name = "TemporaryRagdollAttachment1"
			attachment1.CFrame = descendant.C1
			attachment1.Parent = descendant.Part1

			local constraint = Instance.new("BallSocketConstraint")
			constraint.Name = "TemporaryRagdollConstraint"
			constraint.Attachment0 = attachment0
			constraint.Attachment1 = attachment1
			constraint.LimitsEnabled = true
			constraint.TwistLimitsEnabled = true
			constraint.UpperAngle = 35
			constraint.TwistLowerAngle = -30
			constraint.TwistUpperAngle = 30
			constraint.Parent = descendant.Parent

			descendant.Enabled = false
			table.insert(state.Motors, descendant)
			table.insert(state.Attachments, attachment0)
			table.insert(state.Attachments, attachment1)
			table.insert(state.Constraints, constraint)
		end
	end
end

local function teardownRagdollRig(state: RagdollState)
	for _, motor in ipairs(state.Motors) do
		if motor.Parent then
			motor.Enabled = true
		end
	end

	destroyInstances(state.Constraints)
	destroyInstances(state.Attachments)
	table.clear(state.Motors)
end

local function cleanupRagdoll(character: Model, restoreHumanoid: boolean)
	local state = activeRagdolls[character]
	if not state then
		return
	end

	disconnectConnections(state)
	setRagdollPartCollisions(character, false, state)
	teardownRagdollRig(state)

	local humanoid = getHumanoid(character)
	if restoreHumanoid and humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, state.GettingUpEnabled)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, state.RagdollEnabled)
		humanoid.PlatformStand = state.PlatformStand
		humanoid.AutoRotate = state.AutoRotate

		if humanoid.Health > 0 and character.Parent then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	activeRagdolls[character] = nil
end

local function ensureCleanupConnections(character: Model, humanoid: Humanoid, state: RagdollState)
	if #state.Connections > 0 then
		return
	end

	table.insert(state.Connections, humanoid.Died:Connect(function()
		cleanupRagdoll(character, false)
	end))

	table.insert(state.Connections, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupRagdoll(character, false)
		end
	end))
end

function Utils.ToggleRagdoll(character: Model, enabled: boolean)
	local humanoid = getHumanoid(character)
	if not humanoid then
		return
	end

	if enabled then
		local state = ensureRagdollState(character, humanoid)
		ensureCleanupConnections(character, humanoid, state)
		buildRagdollRig(character, state)
		setRagdollPartCollisions(character, true, state)

		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
		humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
	else
		cleanupRagdoll(character, true)
	end
end

function Utils.ApplyTemporaryRagdoll(character: Model, duration: number): boolean
	local humanoid = getHumanoid(character)
	if not humanoid then
		return false
	end

	local state = ensureRagdollState(character, humanoid)
	state.Token += 1
	local token = state.Token

	Utils.ToggleRagdoll(character, true)

	task.delay(math.max(0.1, duration), function()
		local currentState = activeRagdolls[character]
		if not currentState or currentState.Token ~= token then
			return
		end

		Utils.ToggleRagdoll(character, false)
	end)

	return true
end

return Utils
