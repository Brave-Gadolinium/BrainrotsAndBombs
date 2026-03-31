local BombManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = workspace.Terrain
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local TutorialService = require(game.ServerScriptService.Modules.TutorialService)
local AnalyticsFunnelsService = require(game.ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(game.ServerScriptService.Modules.AnalyticsEconomyService)

local PlayerController
local CarrySystem
local remote: RemoteEvent
local notificationEvent: RemoteEvent?
local cashPopupEvent: RemoteEvent?
local triggerUIEffectEvent: RemoteEvent?
local zonesFolder = workspace:WaitForChild("Zones")
local soundsFolder = Workspace:FindFirstChild("Sounds")

local playerCooldowns = {}
local activeBombs = {}
local SPAWN_FUSE_DELAY = 0.5
local BOMB_SPAWN_BACK_OFFSET = 1.25
local BOMB_SPAWN_UP_OFFSET = 2
local BOMB_SURFACE_CLEARANCE = 1.75

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

local function fireOwnerCameraEffect(player: Player, effectName: string, ...)
	local effectEvent = getTriggerUIEffectEvent()
	if effectEvent then
		effectEvent:FireClient(player, effectName, ...)
	end
end

local function getEquippedBomb(player: Player)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local bombData = BombsConfigurations.GetBombData(child.Name)
			if bombData then
				return child, bombData, child.Name
			end
		end
	end

	return nil, nil, nil
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

local function dropCarriedBrainrot(player: Player)
	if not CarrySystem then
		CarrySystem = require(game.ServerScriptService.Modules.CarrySystem)
	end

	if CarrySystem.HasCarriedItems(player) then
		CarrySystem.DropOneItemAtFeet(player)
	end
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

local function affectPlayers(owner: Player, explosionPosition: Vector3, blastRadius: number, knockbackForce: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == owner then
			continue
		end

		local character = plr.Character
		if not character then
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChild("Humanoid")
		if not root or not humanoid then
			continue
		end

		local offset = root.Position - explosionPosition
		local distance = offset.Magnitude
		if distance > blastRadius or distance == 0 then
			continue
		end

		local direction = offset.Unit
		local force = Instance.new("BodyVelocity")
		force.Velocity = direction * knockbackForce + Vector3.new(0, math.max(32, knockbackForce * 0.35), 0)
		force.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		force.P = 1e4
		force.Parent = root
		Debris:AddItem(force, 0.2)

		dropCarriedBrainrot(plr)
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

	local terrainRadius = BombsConfigurations.GetBlastRadius(bombData, material)
	local playerBlastRadius = math.max(bombData.ExplosionRadius, terrainRadius, 4)
	fireOwnerCameraEffect(player, "BombCameraBlast", hitPosition, playerBlastRadius)

	activeBombs[bombPart] = nil
	bombInstance:Destroy()

	if terrainRadius > 0 then
		Terrain:FillBall(hitPosition, terrainRadius, Enum.Material.Air)
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

local function createThrownBomb(player: Player, sourceTool: Tool, origin: Vector3, bombData, bombName: string, zonePart: BasePart?)
	local bomb, bombInstance = createThrownBombVisual(sourceTool, origin)
	bomb:SetNetworkOwner(nil)
	bomb.AssemblyLinearVelocity = Vector3.zero

	activeBombs[bomb] = {
		Owner = player,
		Data = bombData,
		BombName = bombName,
		Instance = bombInstance,
	}

	fireOwnerCameraEffect(player, "BombCameraStart", bomb, zonePart, SPAWN_FUSE_DELAY)

	task.delay(SPAWN_FUSE_DELAY, function()
		local state = activeBombs[bomb]
		if not state then
			return
		end

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

local function getThrowOrigin(root: BasePart): Vector3
	local character = root.Parent
	local rightHand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local handPart = if rightHand and rightHand:IsA("BasePart") then rightHand else root
	local lookVector = root.CFrame.LookVector
	local desiredOrigin = handPart.Position - (lookVector * BOMB_SPAWN_BACK_OFFSET) + Vector3.new(0, BOMB_SPAWN_UP_OFFSET, 0)

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

local function tryThrowBomb(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local zonePart = getBombZonePart(root.Position)
	if not zonePart then
		notifyPlayer(player, "You can throw bombs only inside the zone")
		return
	end

	local bombTool, bombData, bombName = getEquippedBomb(player)
	if not bombTool or not bombData then
		return
	end

	local now = tick()
	local cooldownStartedAt = playerCooldowns[player]
	if cooldownStartedAt and now - cooldownStartedAt < bombData.Cooldown then
		notifyPlayer(player, "Wait to blast here")
		return
	end

	playerCooldowns[player] = now
	markBombCooldown(bombTool, bombData.Cooldown)

	local origin = getThrowOrigin(root)
	createThrownBomb(player, bombTool, origin, bombData, bombName or bombTool.Name, zonePart)
	TutorialService:HandleBombThrown(player)
	AnalyticsFunnelsService:HandleMineBombThrown(player)
end

function BombManager:Init()
	remote = ensureBombRemote()

	local events = ReplicatedStorage:FindFirstChild("Events")
	if events then
		notificationEvent = events:FindFirstChild("ShowNotification") :: RemoteEvent
		cashPopupEvent = events:FindFirstChild("ShowCashPopUp") :: RemoteEvent
		triggerUIEffectEvent = events:FindFirstChild("TriggerUIEffect") :: RemoteEvent
	end

	remote.OnServerEvent:Connect(function(player)
		tryThrowBomb(player)
	end)
end

function BombManager:Start()
	Players.PlayerRemoving:Connect(function(player)
		playerCooldowns[player] = nil
	end)
end

return BombManager
