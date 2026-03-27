local BombManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local zonesFolder = workspace:WaitForChild("Zones")
local soundsFolder = Workspace:FindFirstChild("Sounds")

local playerCooldowns = {}
local activeBombs = {}

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

local function isInsideBombZone(position: Vector3): boolean
	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
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
	if not bombPart.Parent then
		return
	end

	activeBombs[bombPart] = nil
	bombPart:Destroy()

	local terrainRadius = BombsConfigurations.GetBlastRadius(bombData, material)
	if terrainRadius > 0 then
		Terrain:FillBall(hitPosition, terrainRadius, Enum.Material.Air)
	end

	local explosion = Instance.new("Explosion")
	explosion.Position = hitPosition
	explosion.BlastRadius = 0
	explosion.BlastPressure = 0
	explosion.Parent = workspace

	playExplosionSound(hitPosition)

	local playerBlastRadius = math.max(bombData.ExplosionRadius, terrainRadius, 4)
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

local function createThrownBomb(player: Player, origin: Vector3, direction: Vector3, bombData, bombName: string)
	local bomb = Instance.new("Part")
	bomb.Shape = Enum.PartType.Ball
	bomb.Size = Vector3.new(2, 2, 2)
	bomb.Position = origin
	bomb.Color = Color3.fromRGB(0, 0, 0)
	bomb.Material = Enum.Material.SmoothPlastic
	bomb.Name = "BombInstance"
	bomb.CanCollide = false
	bomb.CanQuery = false
	bomb.CanTouch = true
	bomb.Massless = false
	bomb.Parent = workspace
	bomb:SetNetworkOwner(nil)

	bomb.AssemblyLinearVelocity = Vector3.zero

	activeBombs[bomb] = {
		Owner = player,
		Data = bombData,
		BombName = bombName,
		LastPosition = origin,
	}

	bomb.Touched:Connect(function(hit)
		local state = activeBombs[bomb]
		if not state or not hit then
			return
		end

		if hit == Terrain then
			explodeBomb(state.Owner, bomb, bomb.Position, getMaterialAtPosition(bomb.Position), state.Data, state.BombName)
		end
	end)

	Debris:AddItem(bomb, 8)
end

local function getThrowOrigin(root: BasePart): Vector3
	local character = root.Parent
	local rightHand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	local handPart = if rightHand and rightHand:IsA("BasePart") then rightHand else root
	return handPart.Position + root.CFrame.LookVector
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

	if not isInsideBombZone(root.Position) then
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

	local origin = getThrowOrigin(root)
	createThrownBomb(player, origin, root.CFrame.LookVector, bombData, bombName or bombTool.Name)
	TutorialService:HandleBombThrown(player)
	AnalyticsFunnelsService:HandleMineBombThrown(player)
end

function BombManager:Init()
	remote = ensureBombRemote()

	local events = ReplicatedStorage:FindFirstChild("Events")
	if events then
		notificationEvent = events:FindFirstChild("ShowNotification") :: RemoteEvent
		cashPopupEvent = events:FindFirstChild("ShowCashPopUp") :: RemoteEvent
	end

	remote.OnServerEvent:Connect(function(player)
		tryThrowBomb(player)
	end)
end

function BombManager:Start()
	RunService.Heartbeat:Connect(function()
		for bombPart, state in pairs(activeBombs) do
			if not bombPart.Parent then
				activeBombs[bombPart] = nil
				continue
			end

			local currentPosition = bombPart.Position
			local travel = currentPosition - state.LastPosition
			if travel.Magnitude > 0 then
				local raycastParams = RaycastParams.new()
				raycastParams.FilterType = Enum.RaycastFilterType.Exclude
				raycastParams.FilterDescendantsInstances = {bombPart, state.Owner.Character}

				local result = workspace:Raycast(state.LastPosition, travel, raycastParams)
				if result and result.Instance == Terrain and result.Material ~= Enum.Material.Air then
					explodeBomb(state.Owner, bombPart, result.Position, result.Material, state.Data, state.BombName)
					continue
				end
			end

			state.LastPosition = currentPosition
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerCooldowns[player] = nil
	end)
end

return BombManager
