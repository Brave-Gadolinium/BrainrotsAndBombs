local BombManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Terrain = workspace.Terrain
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local TutorialService = require(ServerScriptService.Modules.TutorialService)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local DepthLevelUtils = require(ServerScriptService.Modules.DepthLevelUtils)
local TerrainGeneratorManager = require(ServerScriptService.Modules.TerrainGeneratorManager)
local Utils = require(ServerScriptService.Modules.Utils)

local PlayerController
local PickaxeController
local CarrySystem
local BoosterService
local remote: RemoteEvent
local notificationEvent: RemoteEvent?
local cashPopupEvent: RemoteEvent?
local triggerUIEffectEvent: RemoteEvent?
local zonesFolder = workspace:WaitForChild("Zones")
local soundsFolder = Workspace:FindFirstChild("Sounds")

local playerCooldowns = {}
local missingBombRepairAttempts = {}
local activeBombs = {}
local BOMB_SPAWN_FORWARD_OFFSET = 1.65
local BOMB_SPAWN_UP_OFFSET = 2
local BOMB_SURFACE_CLEARANCE = 1.75
local BOMB_RAGDOLL_DURATION = 1.35
local BOMB_HIT_EFFECT_NAME = "BombHitFOV"
local BOMB_THROW_SPEED_SCALE = 0.18
local BOMB_MIN_THROW_SPEED = 12
local BOMB_MAX_THROW_SPEED = 18
local BOMB_MIN_THROW_DOWNWARD = 0.18
local BOMB_MAX_THROW_DOWNWARD = 0.55
local BOMB_MAX_FLIGHT_TIME = 5
local BOMB_STUCK_EXPLODE_DELAY = 0.08
local BOMB_TERRAIN_STICK_PADDING = 0.05
local BOMB_TERRAIN_MONITOR_MIN_TRAVEL = 0.05
local BOMB_TERRAIN_DOWNWARD_PROBE_PADDING = 0.35
local BOMB_REPAIR_ATTEMPT_COOLDOWN = 0.75
local NUKE_BLAST_RADIUS_MULTIPLIER = 2

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isValidDirection(value: any): boolean
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
		and value.Magnitude > 0.001
end

local function getHorizontalDirection(direction: Vector3, fallbackDirection: Vector3): Vector3
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude > 0.001 then
		return flatDirection.Unit
	end

	local fallbackFlatDirection = Vector3.new(fallbackDirection.X, 0, fallbackDirection.Z)
	if fallbackFlatDirection.Magnitude > 0.001 then
		return fallbackFlatDirection.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function markBombCooldown(tool: Tool, duration: number)
	tool:SetAttribute("CooldownDuration", duration)
	tool:SetAttribute("CooldownEndsAt", Workspace:GetServerTimeNow() + duration)
end

local function ensureBombRemote(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local bombFolder = remotesFolder:FindFirstChild("Bomb")
	if not bombFolder then
		bombFolder = Instance.new("Folder")
		bombFolder.Name = "Bomb"
		bombFolder.Parent = remotesFolder
	end

	local placeBombRemote = bombFolder:FindFirstChild("PlaceBomb")
	if not placeBombRemote then
		placeBombRemote = Instance.new("RemoteEvent")
		placeBombRemote.Name = "PlaceBomb"
		placeBombRemote.Parent = bombFolder
	end

	return placeBombRemote :: RemoteEvent
end

local function ensureTimerFinishEvent(): BindableEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local timerFolder = remotesFolder:FindFirstChild("Timer")
	if not timerFolder then
		timerFolder = Instance.new("Folder")
		timerFolder.Name = "Timer"
		timerFolder.Parent = remotesFolder
	end

	local finishTime = timerFolder:FindFirstChild("FinishTime")
	if not finishTime then
		finishTime = Instance.new("BindableEvent")
		finishTime.Name = "FinishTime"
		finishTime.Parent = timerFolder
	end

	return finishTime :: BindableEvent
end

local FinishTime = ensureTimerFinishEvent()

local function getBombZonePart(position: Vector3): BasePart?
	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size

			local inside = math.abs(relativePos.X) <= size.X / 2
				and math.abs(relativePos.Y) <= size.Y / 2
				and math.abs(relativePos.Z) <= size.Z / 2

			if inside then
				return zonePart
			end
		end
	end

	return nil
end

local function isBombUseBlocked(): boolean
	return Workspace:GetAttribute("SessionEnded") == true
		or Workspace:GetAttribute("TerrainResetInProgress") == true
end

local function getTriggerUIEffectEvent(): RemoteEvent?
	if triggerUIEffectEvent and triggerUIEffectEvent.Parent then
		return triggerUIEffectEvent
	end

	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then
		return nil
	end

	local effectEvent = events:FindFirstChild("TriggerUIEffect")
	if effectEvent and effectEvent:IsA("RemoteEvent") then
		triggerUIEffectEvent = effectEvent
		return effectEvent
	end

	return nil
end

local function firePlayerUIEffect(player: Player, effectName: string, ...)
	local effectEvent = getTriggerUIEffectEvent()
	if effectEvent then
		effectEvent:FireClient(player, effectName, ...)
	end
end

local function getPickaxeController()
	if PickaxeController then
		return PickaxeController
	end

	local controllersFolder = ServerScriptService:FindFirstChild("Controllers")
	if not controllersFolder then
		return nil
	end

	local pickaxeModule = controllersFolder:FindFirstChild("PickaxeController")
	if pickaxeModule and pickaxeModule:IsA("ModuleScript") then
		PickaxeController = require(pickaxeModule)
	end

	return PickaxeController
end

local function getPlayerController()
	if PlayerController then
		return PlayerController
	end

	PlayerController = require(game.ServerScriptService.Controllers.PlayerController)
	return PlayerController
end

local function getBoosterService()
	if BoosterService then
		return BoosterService
	end

	BoosterService = require(ServerScriptService.Modules.BoosterService)
	return BoosterService
end

local function shallowClone<T>(source: T): T
	local clone = {}
	for key, value in pairs(source :: any) do
		clone[key] = value
	end

	return clone :: any
end

local function getResolvedBombDataForPlayer(player: Player, bombData)
	local resolvedBombData = bombData
	local boosterService = getBoosterService()
	if boosterService and boosterService:HasActiveMegaExplosion(player) then
		resolvedBombData = shallowClone(bombData)
		resolvedBombData.ExplosionRadius = BombsConfigurations.GetMaxExplosionRadius()
	end

	return resolvedBombData
end

local function getBombFromContainer(container: Instance?, preferredBombName: string?): (Tool?, any, string?)
	if not container then
		return nil, nil, nil
	end

	local fallbackTool: Tool? = nil
	local fallbackData = nil
	local fallbackName: string? = nil

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			local bombData = BombsConfigurations.GetBombData(child.Name)
			if bombData then
				if preferredBombName and child.Name == preferredBombName then
					return child, bombData, child.Name
				end

				if not fallbackTool then
					fallbackTool = child
					fallbackData = bombData
					fallbackName = child.Name
				end
			end
		end
	end

	return fallbackTool, fallbackData, fallbackName
end

local function getPreferredBombName(player: Player): string?
	local pickaxeController = getPickaxeController()
	if pickaxeController and pickaxeController.GetPreferredPickaxeName then
		return pickaxeController.GetPreferredPickaxeName(player)
	end

	local playerController = getPlayerController()
	local profile = playerController and playerController:GetProfile(player)
	local equippedPickaxe = profile and profile.Data and profile.Data.EquippedPickaxe
	if type(equippedPickaxe) == "string" and BombsConfigurations.GetBombData(equippedPickaxe) then
		return equippedPickaxe
	end

	return nil
end

local function resolveAvailableBomb(player: Player): (Tool?, any, string?)
	local pickaxeController = getPickaxeController()
	if pickaxeController and pickaxeController.ResolvePreferredBombTool then
		local resolvedTool = pickaxeController.ResolvePreferredBombTool(player)
		if resolvedTool then
			local bombData = BombsConfigurations.GetBombData(resolvedTool.Name)
			if bombData then
				return resolvedTool, bombData, resolvedTool.Name
			end
		end
	end

	local preferredBombName = getPreferredBombName(player)
	local character = player.Character
	local tool, bombData, bombName = getBombFromContainer(character, preferredBombName)
	if tool and bombData then
		return tool, bombData, bombName
	end

	local backpack = player:FindFirstChild("Backpack")
	return getBombFromContainer(backpack, preferredBombName)
end

local function tryRepairMissingBomb(player: Player): boolean
	local pickaxeController = getPickaxeController()
	if not pickaxeController or not pickaxeController.EnsureBombEquipped then
		return false
	end

	local now = tick()
	local lastAttempt = missingBombRepairAttempts[player] or 0
	if now - lastAttempt < BOMB_REPAIR_ATTEMPT_COOLDOWN then
		return false
	end

	missingBombRepairAttempts[player] = now
	pickaxeController.EnsureBombEquipped(player)
	return true
end

local function getMaterialAtPosition(position: Vector3): Enum.Material
	local region = Region3.new(position - Vector3.new(2, 2, 2), position + Vector3.new(2, 2, 2)):ExpandToGrid(4)
	local materials = Terrain:ReadVoxels(region, 4)

	for x = 1, #materials do
		for y = 1, #materials[x] do
			for z = 1, #materials[x][y] do
				local material = materials[x][y][z]
				if material ~= Enum.Material.Air then
					return material
				end
			end
		end
	end

	return Enum.Material.Air
end

local function notifyPlayer(player: Player, message: string)
	if notificationEvent then
		notificationEvent:FireClient(player, message, "Error")
	end
end

local function dropCarriedBrainrot(player: Player): boolean
	if not CarrySystem then
		CarrySystem = require(game.ServerScriptService.Modules.CarrySystem)
	end

	if CarrySystem.HasCarriedItems(player) then
		return CarrySystem.DropOneItemAtFeet(player)
	end

	return false
end

local function playExplosionSound(position: Vector3)
	if not soundsFolder then
		return
	end

	local soundTemplate = soundsFolder:FindFirstChild("Explosion")
		or soundsFolder:FindFirstChild("Explode")
		or soundsFolder:FindFirstChild("BombExplosion")

	if not soundTemplate or not soundTemplate:IsA("Sound") then
		return
	end

	local soundPart = Instance.new("Part")
	soundPart.Name = "BombExplosionSoundPart"
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanQuery = false
	soundPart.CanTouch = false
	soundPart.Transparency = 1
	soundPart.Size = Vector3.new(1, 1, 1)
	soundPart.Position = position
	soundPart.Parent = Workspace

	local sound = soundTemplate:Clone()
	sound.Parent = soundPart
	sound:Play()

	Debris:AddItem(soundPart, math.max(sound.TimeLength, 2))
end

local function disconnectTerrainMonitor(state)
	local monitorConnection = state and state.TerrainMonitorConnection
	if monitorConnection then
		monitorConnection:Disconnect()
		state.TerrainMonitorConnection = nil
	end
end

local function disconnectTouchMonitor(state)
	local touchConnections = state and state.TouchConnections
	if not touchConnections then
		return
	end

	for _, connection in ipairs(touchConnections) do
		connection:Disconnect()
	end

	state.TouchConnections = nil
end

local function destroyActiveBombState(bombPart: BasePart, state)
	disconnectTerrainMonitor(state)
	disconnectTouchMonitor(state)

	activeBombs[bombPart] = nil

	local bombInstance = state and state.Instance
	if bombInstance and bombInstance.Parent then
		bombInstance:Destroy()
	end
end

local function clearActiveBombs()
	for bombPart, state in pairs(activeBombs) do
		if bombPart and state then
			destroyActiveBombState(bombPart, state)
		end
	end
end

local function setBombAnchored(bombInstance: Instance, anchored: boolean)
	if bombInstance:IsA("BasePart") then
		bombInstance.Anchored = anchored
		return
	end

	for _, descendant in ipairs(bombInstance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = anchored
		end
	end
end

local function getTerrainStickPosition(bomb: BasePart, hitPosition: Vector3, hitNormal: Vector3): Vector3
	local surfaceOffset = (math.max(bomb.Size.X, bomb.Size.Y, bomb.Size.Z) * 0.5) + BOMB_TERRAIN_STICK_PADDING
	return hitPosition + (hitNormal * surfaceOffset)
end

local function isStickableInstance(instance: Instance?): boolean
	if not instance then
		return false
	end

	if instance == Terrain then
		return true
	end

	if not instance:IsA("BasePart") then
		return false
	end

	if instance:IsDescendantOf(zonesFolder) then
		return false
	end

	return instance.Anchored and instance.CanCollide
end

local function isStickableHit(result: RaycastResult?): boolean
	if not result then
		return false
	end

	if result.Instance == Terrain then
		return result.Material ~= Enum.Material.Air
	end

	return isStickableInstance(result.Instance)
end

local function findTerrainContact(
	bomb: BasePart,
	lastPosition: Vector3,
	currentPosition: Vector3,
	raycastParams: RaycastParams
): RaycastResult?
	local travel = currentPosition - lastPosition
	if travel.Magnitude >= BOMB_TERRAIN_MONITOR_MIN_TRAVEL then
		local travelHit = Workspace:Raycast(lastPosition, travel, raycastParams)
		if isStickableHit(travelHit) then
			return travelHit
		end
	end

	local bombRadius = math.max(bomb.Size.X, bomb.Size.Y, bomb.Size.Z) * 0.5
	local downwardOrigin = currentPosition + Vector3.new(0, bombRadius * 0.25, 0)
	local downwardHit = Workspace:Raycast(
		downwardOrigin,
		Vector3.new(0, -(bombRadius + BOMB_TERRAIN_DOWNWARD_PROBE_PADDING), 0),
		raycastParams
	)

	if isStickableHit(downwardHit) then
		return downwardHit
	end

	return nil
end

local function applyBlastToPlayer(
	owner: Player?,
	plr: Player,
	explosionPosition: Vector3,
	blastRadius: number,
	knockbackForce: number,
	options: {[string]: any}?
): boolean
	options = options or {}

	if owner and plr == owner and options.AllowSelf ~= true then
		return false
	end

	local character = plr.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end

	if options.RequireMineZone ~= false and not getBombZonePart(root.Position) then
		return false
	end

	local boosterService = getBoosterService()
	if owner and boosterService and boosterService:HasActiveShield(plr) then
		return false
	end

	local offset = root.Position - explosionPosition
	local distance = offset.Magnitude
	if options.ForceHit ~= true and (distance > blastRadius or distance == 0) then
		return false
	end

	local direction = if distance > 0.001 then offset.Unit else Vector3.new(0, 0, -1)
	local force = Instance.new("BodyVelocity")
	force.Velocity = direction * knockbackForce + Vector3.new(0, math.max(32, knockbackForce * 0.35), 0)
	force.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	force.P = 1e4
	force.Parent = root
	Debris:AddItem(force, 0.2)

	Utils.ApplyTemporaryRagdoll(character, BOMB_RAGDOLL_DURATION)
	firePlayerUIEffect(plr, BOMB_HIT_EFFECT_NAME)

	local lostBrainrot = dropCarriedBrainrot(plr)
	if owner and lostBrainrot and boosterService then
		boosterService:PromptShieldOffer(plr)
	end

	return true
end

local function affectPlayers(owner: Player, explosionPosition: Vector3, blastRadius: number, knockbackForce: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		applyBlastToPlayer(owner, plr, explosionPosition, blastRadius, knockbackForce)
	end
end

local function explodeBomb(player: Player, bombPart: BasePart, hitPosition: Vector3, material: Enum.Material, bombData, bombName: string)
	local state = activeBombs[bombPart]
	if not state then
		return
	end

	local bombInstance = state.Instance
	if not bombInstance or not bombInstance.Parent then
		return
	end

	disconnectTerrainMonitor(state)
	disconnectTouchMonitor(state)

	local terrainRadius = BombsConfigurations.GetBlastRadius(bombData, material)
	local impactDepthLevel = DepthLevelUtils.GetDepthLevelAtPosition(hitPosition)
	local maxDepthLevel = tonumber(bombData.MaxDepthLevel) or math.huge
	local isDepthBlocked = impactDepthLevel > 0 and impactDepthLevel > maxDepthLevel
	if isDepthBlocked then
		terrainRadius = 0
		notifyPlayer(player, "Upgrade your bomb to destroy terrain on this layer")
		local boosterService = getBoosterService()
		if boosterService and boosterService.RecordDepthBlocked then
			boosterService:RecordDepthBlocked(player)
		end
	end

	local playerBlastRadius = math.max(bombData.ExplosionRadius, terrainRadius, 4)
	firePlayerUIEffect(player, "BombCameraBlast", hitPosition, playerBlastRadius)

	activeBombs[bombPart] = nil
	bombInstance:Destroy()

	if terrainRadius > 0 then
		Terrain:FillBall(hitPosition, terrainRadius, Enum.Material.Air)
		TerrainGeneratorManager.MarkSphereDirty(hitPosition, terrainRadius)
	end

	local explosion = Instance.new("Explosion")
	explosion.Position = hitPosition
	explosion.BlastRadius = 0
	explosion.BlastPressure = 0
	explosion.Parent = workspace

	playExplosionSound(hitPosition)

	affectPlayers(player, hitPosition, playerBlastRadius * 2, bombData.KnockbackForce)

	if not PlayerController then
		PlayerController = require(game.ServerScriptService.Controllers.PlayerController)
	end

	PlayerController:AddMoney(player, bombData.ExplosionIncome)
	AnalyticsEconomyService:BufferBombIncome(player, bombName, bombData.ExplosionIncome)

	if cashPopupEvent then
		cashPopupEvent:FireClient(player, bombData.ExplosionIncome)
	end
end

local function stripThrownBombInstance(instance: Instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("TouchTransmitter")
			or descendant:IsA("Weld")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("ManualWeld")
			or descendant:IsA("Motor6D")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
			or descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end
end

local function createFallbackBombPart(origin: Vector3): (BasePart, Instance)
	local bomb = Instance.new("Part")
	bomb.Shape = Enum.PartType.Ball
	bomb.Size = Vector3.new(2, 2, 2)
	bomb.CFrame = CFrame.new(origin)
	bomb.Color = Color3.fromRGB(0, 0, 0)
	bomb.Material = Enum.Material.SmoothPlastic
	bomb.Name = "BombInstance"
	bomb.CanCollide = true
	bomb.CanQuery = true
	bomb.CanTouch = true
	bomb.Massless = false
	bomb.Parent = workspace
	return bomb, bomb
end

local function createThrownBombVisual(sourceTool: Tool, origin: Vector3): (BasePart, Instance)
	local sourceHandle = sourceTool:FindFirstChild("Handle")
	if not sourceHandle or not sourceHandle:IsA("BasePart") then
		return createFallbackBombPart(origin)
	end

	local sourceParts = {}
	for _, descendant in ipairs(sourceTool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(sourceParts, descendant)
		end
	end

	if #sourceParts == 0 then
		return createFallbackBombPart(origin)
	end

	local bombModel = Instance.new("Model")
	bombModel.Name = "BombInstance"

	local rootCFrame = CFrame.fromMatrix(
		origin,
		sourceHandle.CFrame.XVector,
		sourceHandle.CFrame.YVector,
		sourceHandle.CFrame.ZVector
	)

	local rootPart: BasePart? = nil

	for _, sourcePart in ipairs(sourceParts) do
		local clone = sourcePart:Clone()
		stripThrownBombInstance(clone)

		local relativeCFrame = sourceHandle.CFrame:ToObjectSpace(sourcePart.CFrame)
		clone.CFrame = rootCFrame * relativeCFrame
		clone.Anchored = false
		clone.CanCollide = true
		clone.CanQuery = true
		clone.CanTouch = true
		clone.Massless = sourcePart ~= sourceHandle
		clone.Parent = bombModel

		if sourcePart == sourceHandle then
			rootPart = clone
		end
	end

	if not rootPart then
		bombModel:Destroy()
		return createFallbackBombPart(origin)
	end

	for _, child in ipairs(bombModel:GetChildren()) do
		if child:IsA("BasePart") and child ~= rootPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = child
			weld.Parent = rootPart
		end
	end

	bombModel.PrimaryPart = rootPart
	bombModel.Parent = workspace

	return rootPart, bombModel
end

local stickBombToTerrain: (bomb: BasePart, hitPosition: Vector3, hitNormal: Vector3) -> boolean

local function scheduleStuckExplosion(bomb: BasePart)
	task.delay(BOMB_STUCK_EXPLODE_DELAY, function()
		local stuckState = activeBombs[bomb]
		if not stuckState then
			return
		end

		local hitPosition = bomb.Position
		local material = getMaterialAtPosition(hitPosition)
		explodeBomb(stuckState.Owner, bomb, hitPosition, material, stuckState.Data, stuckState.BombName)
	end)
end

local function tryStickBombToSurface(bomb: BasePart, hitPosition: Vector3, hitNormal: Vector3): boolean
	if not stickBombToTerrain(bomb, hitPosition, hitNormal) then
		return false
	end

	scheduleStuckExplosion(bomb)
	return true
end

stickBombToTerrain = function(bomb: BasePart, hitPosition: Vector3, hitNormal: Vector3): boolean
	local state = activeBombs[bomb]
	if not state or state.Stuck then
		return false
	end

	local bombInstance = state.Instance
	if not bombInstance or not bombInstance.Parent then
		return false
	end

	state.Stuck = true
	disconnectTerrainMonitor(state)
	disconnectTouchMonitor(state)

	bomb.AssemblyLinearVelocity = Vector3.zero
	bomb.AssemblyAngularVelocity = Vector3.zero
	setBombAnchored(bombInstance, true)

	local stuckPosition = getTerrainStickPosition(bomb, hitPosition, hitNormal)
	local currentCFrame = bomb.CFrame
	local stuckCFrame = CFrame.fromMatrix(
		stuckPosition,
		currentCFrame.XVector,
		currentCFrame.YVector,
		currentCFrame.ZVector
	)

	if bombInstance:IsA("Model") then
		bombInstance:PivotTo(stuckCFrame)
	else
		bombInstance.CFrame = stuckCFrame
	end

	return true
end

local function getApproximateSurfaceContact(bomb: BasePart, hitInstance: Instance): (Vector3, Vector3)
	local bombRadius = math.max(bomb.Size.X, bomb.Size.Y, bomb.Size.Z) * 0.5

	if hitInstance == Terrain then
		local velocity = bomb.AssemblyLinearVelocity
		local normal = if velocity.Magnitude > 0.1 then (-velocity.Unit) else Vector3.yAxis
		if normal.Magnitude <= 0.001 then
			normal = Vector3.yAxis
		else
			normal = normal.Unit
		end

		return bomb.Position - (normal * bombRadius), normal
	end

	if hitInstance:IsA("BasePart") then
		local localPosition = hitInstance.CFrame:PointToObjectSpace(bomb.Position)
		local halfSize = hitInstance.Size * 0.5
		local xRatio = math.abs(localPosition.X) / math.max(halfSize.X, 0.001)
		local yRatio = math.abs(localPosition.Y) / math.max(halfSize.Y, 0.001)
		local zRatio = math.abs(localPosition.Z) / math.max(halfSize.Z, 0.001)

		local normalLocal: Vector3
		if yRatio >= xRatio and yRatio >= zRatio then
			normalLocal = Vector3.new(0, if localPosition.Y >= 0 then 1 else -1, 0)
		elseif xRatio >= zRatio then
			normalLocal = Vector3.new(if localPosition.X >= 0 then 1 else -1, 0, 0)
		else
			normalLocal = Vector3.new(0, 0, if localPosition.Z >= 0 then 1 else -1)
		end

		local normalWorld = hitInstance.CFrame:VectorToWorldSpace(normalLocal).Unit
		local contactPointLocal = Vector3.new(
			normalLocal.X * halfSize.X,
			normalLocal.Y * halfSize.Y,
			normalLocal.Z * halfSize.Z
		)
		local hitPosition = hitInstance.CFrame:PointToWorldSpace(contactPointLocal)
		return hitPosition, normalWorld
	end

	return bomb.Position - Vector3.new(0, bombRadius, 0), Vector3.yAxis
end

local function startBombTouchMonitor(bomb: BasePart, ownerCharacter: Model?)
	local state = activeBombs[bomb]
	if not state then
		return
	end

	disconnectTouchMonitor(state)

	local filterInstances = { state.Instance }
	if ownerCharacter then
		table.insert(filterInstances, ownerCharacter)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filterInstances

	local touchConnections = {}
	local partsToWatch = {}

	if state.Instance:IsA("BasePart") then
		table.insert(partsToWatch, state.Instance)
	else
		for _, descendant in ipairs(state.Instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(partsToWatch, descendant)
			end
		end
	end

	local function handleTouch(hitInstance)
		local currentState = activeBombs[bomb]
		if currentState ~= state or currentState.Stuck or not hitInstance then
			return
		end

		if not isStickableInstance(hitInstance) then
			return
		end

		if currentState.Instance and hitInstance:IsDescendantOf(currentState.Instance) then
			return
		end

		local currentPosition = bomb.Position
		local lastPosition = currentState.LastPosition or currentPosition
		local hitResult = findTerrainContact(bomb, lastPosition, currentPosition, raycastParams)
		if hitResult and tryStickBombToSurface(bomb, hitResult.Position, hitResult.Normal) then
			return
		end

		local fallbackPosition, fallbackNormal = getApproximateSurfaceContact(bomb, hitInstance)
		tryStickBombToSurface(bomb, fallbackPosition, fallbackNormal)
	end

	for _, part in ipairs(partsToWatch) do
		table.insert(touchConnections, part.Touched:Connect(handleTouch))
	end

	state.TouchConnections = touchConnections
end

local function startBombTerrainMonitor(bomb: BasePart, ownerCharacter: Model?)
	local state = activeBombs[bomb]
	if not state then
		return
	end

	local filterInstances = { state.Instance }
	if ownerCharacter then
		table.insert(filterInstances, ownerCharacter)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filterInstances

	state.LastPosition = bomb.Position
	state.TerrainMonitorConnection = RunService.Heartbeat:Connect(function()
		local currentState = activeBombs[bomb]
		if currentState ~= state then
			disconnectTerrainMonitor(state)
			return
		end

		local bombInstance = currentState.Instance
		if currentState.Stuck or not bomb.Parent or not bombInstance or not bombInstance.Parent then
			disconnectTerrainMonitor(currentState)
			return
		end

		local currentPosition = bomb.Position
		local lastPosition = currentState.LastPosition or currentPosition

		local hitResult = findTerrainContact(bomb, lastPosition, currentPosition, raycastParams)
		if hitResult then
			tryStickBombToSurface(bomb, hitResult.Position, hitResult.Normal)
			return
		end

		currentState.LastPosition = currentPosition
	end)
end

local function createThrownBomb(
	player: Player,
	sourceTool: Tool,
	origin: Vector3,
	throwVelocity: Vector3,
	bombData,
	bombName: string,
	zonePart: BasePart?
)
	local bomb, bombInstance = createThrownBombVisual(sourceTool, origin)
	bomb:SetNetworkOwner(nil)
	bomb.AssemblyLinearVelocity = throwVelocity

	activeBombs[bomb] = {
		Owner = player,
		Data = bombData,
		BombName = bombName,
		Instance = bombInstance,
		Stuck = false,
		LastPosition = origin,
	}

	startBombTerrainMonitor(bomb, player.Character)
	startBombTouchMonitor(bomb, player.Character)
	firePlayerUIEffect(player, "BombCameraStart", bomb, zonePart, BOMB_MAX_FLIGHT_TIME)

	task.delay(BOMB_MAX_FLIGHT_TIME, function()
		local state = activeBombs[bomb]
		if not state then
			return
		end

		disconnectTerrainMonitor(state)

		local bombStateInstance = state.Instance
		if not bombStateInstance or not bombStateInstance.Parent then
			return
		end

		local hitPosition = bomb.Position
		local material = getMaterialAtPosition(hitPosition)
		explodeBomb(state.Owner, bomb, hitPosition, material, state.Data, state.BombName)
	end)

	Debris:AddItem(bombInstance, 8)
end

local function resolveThrowDirection(root: BasePart, cameraLookVector: Vector3?, bombData): (Vector3, Vector3)
	local rootLookVector = root.CFrame.LookVector
	local requestedDirection = if isValidDirection(cameraLookVector) then cameraLookVector.Unit else rootLookVector
	local horizontalDirection = getHorizontalDirection(requestedDirection, rootLookVector)

	local configuredArc = bombData and bombData.ThrowArc or BombsConfigurations.Defaults.ThrowArc
	local configuredDownward = math.sin(math.rad(configuredArc))
	local cameraDownward = math.max(0, -requestedDirection.Y)
	local downwardAmount = math.clamp(
		math.max(configuredDownward, cameraDownward),
		BOMB_MIN_THROW_DOWNWARD,
		BOMB_MAX_THROW_DOWNWARD
	)

	local throwDirection = Vector3.new(horizontalDirection.X, -downwardAmount, horizontalDirection.Z).Unit
	return throwDirection, horizontalDirection
end

local function getThrowVelocity(root: BasePart, throwDirection: Vector3, bombData): Vector3
	local configuredThrowSpeed = bombData and bombData.ThrowSpeed or BombsConfigurations.Defaults.ThrowSpeed
	local throwSpeed = math.clamp(configuredThrowSpeed * BOMB_THROW_SPEED_SCALE, BOMB_MIN_THROW_SPEED, BOMB_MAX_THROW_SPEED)
	local inheritedVelocity = root.AssemblyLinearVelocity * 0.15
	return (throwDirection * throwSpeed) + inheritedVelocity
end

local function getThrowOrigin(root: BasePart, horizontalDirection: Vector3): Vector3
	local character = root.Parent
	local rightHand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local handPart = if rightHand and rightHand:IsA("BasePart") then rightHand else root
	local desiredOrigin = handPart.Position
		+ (horizontalDirection * BOMB_SPAWN_FORWARD_OFFSET)
		+ Vector3.new(0, BOMB_SPAWN_UP_OFFSET, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	local surfaceResult = Workspace:Raycast(
		desiredOrigin + Vector3.new(0, 6, 0),
		Vector3.new(0, -14, 0),
		raycastParams
	)

	if surfaceResult then
		local minAllowedY = surfaceResult.Position.Y + BOMB_SURFACE_CLEARANCE
		if desiredOrigin.Y < minAllowedY then
			desiredOrigin = Vector3.new(desiredOrigin.X, minAllowedY, desiredOrigin.Z)
		end
	end

	return desiredOrigin
end

local function tryThrowBomb(player: Player, cameraLookVector: Vector3?, options: {[string]: any}?): boolean
	options = options or {}
	local silent = options.Silent == true

	if isBombUseBlocked() then
		if not silent then
			notifyPlayer(player, "Bombs are unavailable right now")
		end
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local zonePart = getBombZonePart(root.Position)
	if not zonePart then
		if not silent then
			notifyPlayer(player, "You can throw bombs only inside the zone")
		end
		return false
	end

	local bombTool, bombData, bombName = resolveAvailableBomb(player)
	if not bombTool or not bombData then
		tryRepairMissingBomb(player)
		if not silent then
			notifyPlayer(player, "Bomb unavailable, try again")
		end
		return false
	end

	local now = tick()
	local cooldownStartedAt = playerCooldowns[player]
	if cooldownStartedAt and now - cooldownStartedAt < bombData.Cooldown then
		if not silent then
			notifyPlayer(player, "Wait to blast here")
		end
		return false
	end

	local resolvedBombData = getResolvedBombDataForPlayer(player, bombData)
	playerCooldowns[player] = now
	markBombCooldown(bombTool, resolvedBombData.Cooldown)

	local throwDirection, horizontalDirection = resolveThrowDirection(root, cameraLookVector, resolvedBombData)
	local origin = getThrowOrigin(root, horizontalDirection)
	local throwVelocity = getThrowVelocity(root, throwDirection, resolvedBombData)
	createThrownBomb(player, bombTool, origin, throwVelocity, resolvedBombData, bombName or bombTool.Name, zonePart)
	TutorialService:HandleBombThrown(player)
	AnalyticsFunnelsService:HandleMineBombThrown(player)
	return true
end

local function triggerNukeBlast(player: Player): boolean
	if isBombUseBlocked() then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local zonePart = getBombZonePart(root.Position)
	if not zonePart then
		return false
	end

	local _, bombData = resolveAvailableBomb(player)
	if not bombData then
		return false
	end

	local resolvedBombData = getResolvedBombDataForPlayer(player, bombData)
	local blastRadius = math.max(6, (tonumber(resolvedBombData.ExplosionRadius) or 0) * NUKE_BLAST_RADIUS_MULTIPLIER)
	local knockbackForce = tonumber(resolvedBombData.KnockbackForce) or 0
	local hitAny = false

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			local hit = applyBlastToPlayer(player, plr, root.Position, blastRadius, knockbackForce, {
				AllowSelf = false,
				RequireMineZone = true,
			})
			hitAny = hitAny or hit
		end
	end

	if hitAny then
		playExplosionSound(root.Position)
	end

	return hitAny
end

function BombManager:Init()
	remote = ensureBombRemote()

	local events = ReplicatedStorage:FindFirstChild("Events")
	if events then
		notificationEvent = events:FindFirstChild("ShowNotification") :: RemoteEvent
		cashPopupEvent = events:FindFirstChild("ShowCashPopUp") :: RemoteEvent
		triggerUIEffectEvent = events:FindFirstChild("TriggerUIEffect") :: RemoteEvent
	end

	remote.OnServerEvent:Connect(function(player, cameraLookVector)
		local resolvedCameraLookVector = if typeof(cameraLookVector) == "Vector3" then cameraLookVector else nil
		tryThrowBomb(player, resolvedCameraLookVector)
	end)
end

function BombManager:Start()
	FinishTime.Event:Connect(clearActiveBombs)

	Players.PlayerRemoving:Connect(function(player)
		playerCooldowns[player] = nil
		missingBombRepairAttempts[player] = nil
	end)
end

function BombManager.TryThrowBomb(player: Player, cameraLookVector: Vector3?, options: {[string]: any}?): boolean
	return tryThrowBomb(player, cameraLookVector, options)
end

function BombManager.TriggerNukeBlast(player: Player): boolean
	return triggerNukeBlast(player)
end

return BombManager
