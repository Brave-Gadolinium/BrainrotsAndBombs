local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ROTATE_DISTANCE_CULL = 200
local ROTATION_SPEED = 0.03
local FLOAT_SPEED = 2
local FLOAT_HEIGHT = 0.5

type RotateState = {
	StartingCFrame: CFrame,
	Rotation: number,
	Time: number,
}

local rotateStates: {[Model]: RotateState} = {}

local function addRotateModel(instance: Instance)
	if not instance:IsA("Model") or rotateStates[instance] then
		return
	end

	rotateStates[instance] = {
		StartingCFrame = instance:GetPivot(),
		Rotation = 0,
		Time = 0,
	}
end

local function removeRotateModel(instance: Instance)
	if instance:IsA("Model") then
		rotateStates[instance] = nil
	end
end

for _, instance in ipairs(CollectionService:GetTagged("Rotate")) do
	addRotateModel(instance)
end

CollectionService:GetInstanceAddedSignal("Rotate"):Connect(addRotateModel)
CollectionService:GetInstanceRemovedSignal("Rotate"):Connect(removeRotateModel)

RunService.RenderStepped:Connect(function(deltaTime)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraPosition = camera.CFrame.Position

	for model, state in pairs(rotateStates) do
		if not model.Parent then
			rotateStates[model] = nil
			continue
		end

		if (cameraPosition - state.StartingCFrame.Position).Magnitude > ROTATE_DISTANCE_CULL then
			continue
		end

		state.Rotation += ROTATION_SPEED
		state.Time += deltaTime

		local floatHeight = math.sin(state.Time * FLOAT_SPEED) * FLOAT_HEIGHT
		local nextCFrame = CFrame.new(state.StartingCFrame.Position + Vector3.new(0, floatHeight, 0))
			* CFrame.Angles(0, state.Rotation, 0)

		model:PivotTo(nextCFrame)
	end
end)
