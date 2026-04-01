--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraShaker = require(ReplicatedStorage.Modules:WaitForChild("CameraShaker"))

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local triggerUIEffect = events:WaitForChild("TriggerUIEffect") :: RemoteEvent
local zonesFolder = Workspace:WaitForChild("Zones")

local HANDOFF_DURATION = 0.18
local HANDOFF_FOV_BOOST = 10
local ASSIST_FOV_BOOST = 6
local BLAST_FOV_PUNCH = 4
local ASSIST_SIDE_OFFSET = 2.5
local ASSIST_HEIGHT_OFFSET = 6
local BLAST_RETURN_DURATION = 0.35
local DEFAULT_ZONE_SIZE = Vector3.new(48, 32, 48)
local MIN_DIRECTION_MAGNITUDE = 0.001
local OCCLUSION_LIFT_STEP = 4
local OCCLUSION_ATTEMPTS = 3
local BLAST_GRACE_TIME = 0.75
local EARLY_BLAST_REPLICATION_GRACE = 0.2

type CameraBaseline = {
	CameraType: Enum.CameraType,
	CameraSubject: Instance?,
	FieldOfView: number,
	CameraOffset: Vector3,
}

type ActiveShotState = {
	Token: number,
	IsActive: boolean,
	BlastReceived: boolean,
	Baseline: CameraBaseline?,
	Humanoid: Humanoid?,
	Root: BasePart?,
	BombPart: BasePart?,
	BombContainer: Instance?,
	ZonePart: BasePart?,
	FuseDelay: number,
	ExpectedBlastAt: number,
	SideSign: number,
	HandoffValue: CFrameValue?,
	HandoffConnection: RBXScriptConnection?,
	MonitorConnection: RBXScriptConnection?,
	DeathConnection: RBXScriptConnection?,
	BombConnection: RBXScriptConnection?,
	Tweens: {Tween},
}

local state: ActiveShotState = {
	Token = 0,
	IsActive = false,
	BlastReceived = false,
	FuseDelay = 0,
	ExpectedBlastAt = 0,
	SideSign = 1,
	Tweens = {},
}

local cameraShaker = CameraShaker.new(Enum.RenderPriority.Camera.Value + 1, function(shakeCFrame: CFrame)
	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		currentCamera.CFrame = currentCamera.CFrame * shakeCFrame
	end
end)

cameraShaker:Start()

local function getCurrentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function getHumanoidAndRoot(): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		return humanoid, root
	end

	return nil, nil
end

local function isInsideZone(position: Vector3, zonePart: BasePart): boolean
	local relativePos = zonePart.CFrame:PointToObjectSpace(position)
	local size = zonePart.Size

	return math.abs(relativePos.X) <= size.X / 2
		and math.abs(relativePos.Y) <= size.Y / 2
		and math.abs(relativePos.Z) <= size.Z / 2
end

local function findContainingZonePart(position: Vector3): BasePart?
	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" and isInsideZone(position, zonePart) then
			return zonePart
		end
	end

	return nil
end

local function findClosestZonePart(position: Vector3): BasePart?
	local closestZone: BasePart? = nil
	local closestDistance = math.huge

	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local distance = (zonePart.Position - position).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestZone = zonePart
			end
		end
	end

	return closestZone
end

local function flattenDirection(direction: Vector3): Vector3?
	local flattened = Vector3.new(direction.X, 0, direction.Z)
	if flattened.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil
	end

	return flattened.Unit
end

local function registerTween(tween: Tween)
	table.insert(state.Tweens, tween)
	tween:Play()
end

local function cancelTweens()
	for _, tween in ipairs(state.Tweens) do
		tween:Cancel()
	end

	table.clear(state.Tweens)
end

local function cleanupHandoff()
	if state.HandoffConnection then
		state.HandoffConnection:Disconnect()
		state.HandoffConnection = nil
	end

	if state.HandoffValue then
		state.HandoffValue:Destroy()
		state.HandoffValue = nil
	end
end

local function disconnectMonitors()
	if state.MonitorConnection then
		state.MonitorConnection:Disconnect()
		state.MonitorConnection = nil
	end

	if state.DeathConnection then
		state.DeathConnection:Disconnect()
		state.DeathConnection = nil
	end

	if state.BombConnection then
		state.BombConnection:Disconnect()
		state.BombConnection = nil
	end
end

local function clearState()
	state.IsActive = false
	state.BlastReceived = false
	state.Baseline = nil
	state.Humanoid = nil
	state.Root = nil
	state.BombPart = nil
	state.BombContainer = nil
	state.ZonePart = nil
	state.FuseDelay = 0
	state.ExpectedBlastAt = 0
	state.SideSign = 1
	table.clear(state.Tweens)
end

local function restoreBaselineImmediate()
	local camera = getCurrentCamera()
	local baseline = state.Baseline
	local humanoid = state.Humanoid

	if humanoid and humanoid.Parent and baseline then
		humanoid.CameraOffset = baseline.CameraOffset
	end

	if camera and baseline then
		camera.FieldOfView = baseline.FieldOfView
		camera.CameraType = baseline.CameraType

		if baseline.CameraSubject and baseline.CameraSubject.Parent then
			camera.CameraSubject = baseline.CameraSubject
		elseif humanoid and humanoid.Parent then
			camera.CameraSubject = humanoid
		end
	end
end

local function forceRestoreImmediate()
	if not state.IsActive then
		return
	end

	state.Token += 1
	cancelTweens()
	cleanupHandoff()
	disconnectMonitors()
	restoreBaselineImmediate()
	clearState()
end

local function resolveShotPosition(focus: Vector3, desiredPosition: Vector3, bombContainer: Instance?, zonePart: BasePart?): Vector3
	local humanoid = state.Humanoid
	local character = humanoid and humanoid.Parent

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local filterInstances: {Instance} = {}
	if character then
		table.insert(filterInstances, character)
	end
	if bombContainer then
		table.insert(filterInstances, bombContainer)
	end
	if zonePart then
		table.insert(filterInstances, zonePart)
	end
	raycastParams.FilterDescendantsInstances = filterInstances

	local candidatePosition = desiredPosition
	for _ = 0, OCCLUSION_ATTEMPTS do
		local direction = focus - candidatePosition
		local result = Workspace:Raycast(candidatePosition, direction, raycastParams)
		if not result then
			return candidatePosition
		end

		candidatePosition += Vector3.new(0, OCCLUSION_LIFT_STEP, 0)
	end

	return candidatePosition
end

local function computeShot(root: BasePart, bombPart: BasePart, zonePart: BasePart?): (CFrame, number)
	local camera = getCurrentCamera()
	local currentCamera = if camera then camera.CFrame else CFrame.new(root.Position + Vector3.new(0, 10, -10), root.Position)
	local rootPosition = root.Position
	local bombPosition = bombPart.Position
	local focus = rootPosition:Lerp(bombPosition, 0.65)
	local zoneSize = if zonePart then zonePart.Size else DEFAULT_ZONE_SIZE

	local horizontalDirection = flattenDirection(bombPosition - rootPosition)
	if not horizontalDirection and zonePart then
		horizontalDirection = flattenDirection(zonePart.CFrame.LookVector)
	end
	if not horizontalDirection then
		horizontalDirection = flattenDirection(currentCamera.LookVector)
	end
	if not horizontalDirection then
		horizontalDirection = flattenDirection(root.CFrame.LookVector)
	end
	if not horizontalDirection then
		horizontalDirection = Vector3.new(0, 0, -1)
	end

	local sideVector = horizontalDirection:Cross(Vector3.yAxis)
	if sideVector.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		sideVector = Vector3.new(1, 0, 0)
	else
		sideVector = sideVector.Unit
	end

	if (currentCamera.Position - focus):Dot(sideVector) < 0 then
		sideVector = -sideVector
	end

	local height = math.clamp(zoneSize.Y * 0.75, 12, 20)
	local backOffset = math.clamp(zoneSize.Z * 0.22, 10, 16)
	local sideOffset = math.clamp(zoneSize.X * 0.12, 4, 8)
	local desiredPosition = focus - (horizontalDirection * backOffset) + (sideVector * sideOffset) + Vector3.new(0, height, 0)
	local finalPosition = resolveShotPosition(focus, desiredPosition, state.BombContainer, zonePart)
	local sideSign = if root.CFrame.RightVector:Dot(sideVector) >= 0 then 1 else -1

	return CFrame.lookAt(finalPosition, focus), sideSign
end

local function beginAssistPhase(token: number, assistOffset: Vector3)
	if token ~= state.Token or not state.IsActive then
		return
	end

	local camera = getCurrentCamera()
	local humanoid = state.Humanoid
	local baseline = state.Baseline
	if not camera or not humanoid or not humanoid.Parent or not baseline then
		forceRestoreImmediate()
		return
	end

	cleanupHandoff()
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid

	registerTween(TweenService:Create(
		camera,
		TweenInfo.new(HANDOFF_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{FieldOfView = math.min(baseline.FieldOfView + ASSIST_FOV_BOOST, 100)}
	))

	registerTween(TweenService:Create(
		humanoid,
		TweenInfo.new(HANDOFF_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{CameraOffset = assistOffset}
	))
end

local function startHandoff(token: number, targetCFrame: CFrame, assistOffset: Vector3)
	local camera = getCurrentCamera()
	local baseline = state.Baseline
	if not camera or not baseline then
		forceRestoreImmediate()
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local handoffValue = Instance.new("CFrameValue")
	handoffValue.Value = camera.CFrame
	state.HandoffValue = handoffValue

	state.HandoffConnection = handoffValue:GetPropertyChangedSignal("Value"):Connect(function()
		if token ~= state.Token or not state.IsActive then
			return
		end

		local currentCamera = getCurrentCamera()
		if currentCamera then
			currentCamera.CFrame = handoffValue.Value
		end
	end)

	local cameraTween = TweenService:Create(
		handoffValue,
		TweenInfo.new(HANDOFF_DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{Value = targetCFrame}
	)
	registerTween(cameraTween)

	registerTween(TweenService:Create(
		camera,
		TweenInfo.new(HANDOFF_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{FieldOfView = math.min(baseline.FieldOfView + HANDOFF_FOV_BOOST, 100)}
	))

	cameraTween.Completed:Connect(function(playbackState)
		if playbackState == Enum.PlaybackState.Cancelled then
			return
		end

		beginAssistPhase(token, assistOffset)
	end)
end

local function bindMonitors(token: number)
	local humanoid = state.Humanoid
	local root = state.Root
	local bombPart = state.BombPart
	if not humanoid or not root or not bombPart then
		forceRestoreImmediate()
		return
	end

	state.DeathConnection = humanoid.Died:Connect(function()
		if token == state.Token then
			forceRestoreImmediate()
		end
	end)

	state.BombConnection = bombPart.AncestryChanged:Connect(function(_, parent)
		if token ~= state.Token or not state.IsActive or state.BlastReceived or parent then
			return
		end

		task.delay(EARLY_BLAST_REPLICATION_GRACE, function()
			if token ~= state.Token or not state.IsActive or state.BlastReceived then
				return
			end

			if Workspace:GetServerTimeNow() < state.ExpectedBlastAt - 0.1 then
				forceRestoreImmediate()
			end
		end)
	end)

	state.MonitorConnection = RunService.Heartbeat:Connect(function()
		if token ~= state.Token or not state.IsActive then
			return
		end

		local currentHumanoid = state.Humanoid
		local currentRoot = state.Root
		if not currentHumanoid or not currentHumanoid.Parent or currentHumanoid.Health <= 0 or not currentRoot or not currentRoot.Parent then
			forceRestoreImmediate()
			return
		end

		local currentCamera = getCurrentCamera()
		if not currentCamera then
			return
		end

		local activeZone = state.ZonePart
		if activeZone then
			if not activeZone.Parent or not isInsideZone(currentRoot.Position, activeZone) then
				forceRestoreImmediate()
				return
			end
		elseif not findContainingZonePart(currentRoot.Position) then
			forceRestoreImmediate()
			return
		end

		if not state.HandoffValue then
			if currentCamera.CameraType ~= Enum.CameraType.Custom or currentCamera.CameraSubject ~= currentHumanoid then
				forceRestoreImmediate()
				return
			end
		end

		if not state.BlastReceived and Workspace:GetServerTimeNow() > state.ExpectedBlastAt + BLAST_GRACE_TIME then
			forceRestoreImmediate()
		end
	end)
end

local function startBombCamera(bombPart: BasePart, explicitZonePart: BasePart?, fuseDelay: number?)
	local camera = getCurrentCamera()
	local humanoid, root = getHumanoidAndRoot()
	if not camera or not humanoid or not root or not bombPart or not bombPart.Parent then
		return
	end

	if state.IsActive and state.Humanoid ~= humanoid then
		forceRestoreImmediate()
	end

	local baseline = state.Baseline
	if not baseline then
		baseline = {
			CameraType = camera.CameraType,
			CameraSubject = camera.CameraSubject,
			FieldOfView = camera.FieldOfView,
			CameraOffset = humanoid.CameraOffset,
		}
	end

	state.Token += 1
	local token = state.Token

	cancelTweens()
	cleanupHandoff()
	disconnectMonitors()

	state.IsActive = true
	state.BlastReceived = false
	state.Baseline = baseline
	state.Humanoid = humanoid
	state.Root = root
	state.BombPart = bombPart
	state.BombContainer = if bombPart.Parent and bombPart.Parent:IsA("Model") then bombPart.Parent else bombPart
	state.ZonePart = if explicitZonePart and explicitZonePart.Parent then explicitZonePart else (findContainingZonePart(root.Position) or findClosestZonePart(root.Position))
	state.FuseDelay = fuseDelay or 0.5
	state.ExpectedBlastAt = Workspace:GetServerTimeNow() + state.FuseDelay

	local shotCFrame, sideSign = computeShot(root, bombPart, state.ZonePart)
	state.SideSign = sideSign

	bindMonitors(token)
	startHandoff(token, shotCFrame, Vector3.new(sideSign * ASSIST_SIDE_OFFSET, ASSIST_HEIGHT_OFFSET, 0))
end

local function handleBlast(_explosionPosition: Vector3, blastRadius: number?)
	if not state.IsActive then
		return
	end

	state.BlastReceived = true
	cancelTweens()
	cleanupHandoff()
	disconnectMonitors()

	local camera = getCurrentCamera()
	local humanoid = state.Humanoid
	local baseline = state.Baseline
	if not camera or not baseline then
		forceRestoreImmediate()
		return
	end

	if humanoid and humanoid.Parent then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end

	local token = state.Token
	local punchTargetFov = math.min(baseline.FieldOfView + ASSIST_FOV_BOOST + BLAST_FOV_PUNCH, 100)
	local settleTween = TweenService:Create(
		camera,
		TweenInfo.new(BLAST_RETURN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{FieldOfView = baseline.FieldOfView}
	)

	registerTween(TweenService:Create(
		camera,
		TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{FieldOfView = punchTargetFov}
	))

	task.delay(0.08, function()
		if token ~= state.Token or not state.IsActive then
			return
		end

		registerTween(settleTween)
	end)

	if humanoid and humanoid.Parent then
		registerTween(TweenService:Create(
			humanoid,
			TweenInfo.new(BLAST_RETURN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{CameraOffset = baseline.CameraOffset}
		))
	end

	local shakeScale = math.clamp((blastRadius or 4) / 18, 0.6, 1.4)
	cameraShaker:ShakeOnce(
		1.8 * shakeScale,
		8,
		0.03,
		0.22,
		Vector3.new(0.18, 0.14, 0.18),
		Vector3.new(0.9, 0.9, 0.55)
	)

	task.delay(BLAST_RETURN_DURATION + 0.05, function()
		if token == state.Token then
			forceRestoreImmediate()
		end
	end)
end

triggerUIEffect.OnClientEvent:Connect(function(effectName: string, ...)
	if effectName == "BombCameraStart" then
		local bombPart, zonePart, fuseDelay = ...
		if bombPart and bombPart:IsA("BasePart") then
			local resolvedZonePart = if zonePart and zonePart:IsA("BasePart") then zonePart else nil
			local resolvedFuseDelay = if type(fuseDelay) == "number" then fuseDelay else 0.5

			if bombPart.Parent then
				startBombCamera(bombPart, resolvedZonePart, resolvedFuseDelay)
			else
				task.delay(0.05, function()
					if bombPart.Parent then
						startBombCamera(bombPart, resolvedZonePart, resolvedFuseDelay)
					end
				end)
			end
		end
	elseif effectName == "BombCameraBlast" then
		local explosionPosition, blastRadius = ...
		if typeof(explosionPosition) == "Vector3" then
			handleBlast(explosionPosition, if type(blastRadius) == "number" then blastRadius else nil)
		end
	end
end)

player.CharacterRemoving:Connect(function()
	forceRestoreImmediate()
end)
