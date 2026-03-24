local BombManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = workspace.Terrain
local Players = game:GetService("Players")
local PlayerController

local remote = ReplicatedStorage.Remotes.Bomb.PlaceBomb
local Events = ReplicatedStorage:FindFirstChild("Events")
local notif = Events and Events:FindFirstChild("ShowNotification")

local COOLDOWN = 1.5
local BOMB_TIMER = 1
local EXPLOSION_RADIUS = 10
local PUSH_RADIUS = 20
local PUSH_FORCE = 80

-- кулдауны
local playerCooldowns = {}

local function spawnLoot(position)
	local amount = math.random(1, 5)

	for i = 1, amount do
		local part = Instance.new("Part")
		part.Size = Vector3.new(1,1,1)
		part.Position = position + Vector3.new(
			math.random(-10,10),
			math.random(2,5),
			math.random(-10,10)
		)
		part.Anchored = false
		part.Parent = workspace
	end
end

local function affectPlayers(owner, explosionPosition)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == owner then continue end

		local character = plr.Character
		if not character then continue end

		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChild("Humanoid")

		if not root or not humanoid then continue end

		local distance = (root.Position - explosionPosition).Magnitude
		if distance > PUSH_RADIUS then continue end

		local direction = (root.Position - explosionPosition).Unit
		local force = Instance.new("BodyVelocity")
		force.Velocity = direction * PUSH_FORCE + Vector3.new(0, 40, 0)
		force.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		force.P = 1e4
		force.Parent = root

		game.Debris:AddItem(force, 0.2)

		local brainrots = plr:FindFirstChild("Brainrots")
		if brainrots and brainrots:IsA("IntValue") then
			local drop = math.random(1, 3)
			brainrots.Value = math.max(0, brainrots.Value - drop)
		end
	end
end


local function destroyTerrain(position)
	Terrain:FillBall(position, EXPLOSION_RADIUS, Enum.Material.Air)
end

local function createBomb(player, position)
	print('1')
	local bomb = Instance.new("Part")
	bomb.Shape = Enum.PartType.Ball
	bomb.Size = Vector3.new(2,2,2)
	bomb.Position = position
	bomb.Anchored = false
	bomb.Color = Color3.fromRGB(0,0,0)
	bomb.Name = "BombInstance"
	bomb.Parent = workspace

	task.delay(BOMB_TIMER, function()
		if not bomb then return end

		local pos = bomb.Position
		bomb:Destroy()

		local explosion = Instance.new("Explosion")
		explosion.Position = pos
		explosion.BlastRadius = 0
		explosion.BlastPressure = 0
		explosion.Parent = workspace

		affectPlayers(player, pos)

		destroyTerrain(pos)
		
		if not PlayerController then PlayerController = require(game.ServerScriptService.Controllers.PlayerController) end		
		PlayerController:AddMoney(player, 1000)
		
		local popupEvent = Events:FindFirstChild("ShowCashPopUp")
		if popupEvent then
			popupEvent:FireClient(player, 1000)
		end

		--spawnLoot(pos)
	end)
end

remote.OnServerEvent:Connect(function(player, position)
	print(player, position)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	print(1)

	local root = character.HumanoidRootPart
	if (root.Position - position).Magnitude > 50 then return end
	print(2)

	if playerCooldowns[player] and tick() - playerCooldowns[player] < COOLDOWN then
		return
	end
	print(3)

	playerCooldowns[player] = tick()
	
	local region = Region3.new(
		position - Vector3.new(4,4,4),
		position + Vector3.new(4,4,4)
	):ExpandToGrid(4)
	print(4)

	local materials, occupancy = Terrain:ReadVoxels(region, 4)

	local isSand = false

	--for x = 1, #materials do
	--	for y = 1, #materials[x] do
	--		for z = 1, #materials[x][y] do
	--			if materials[x][y][z] == Enum.Material.Sand then
	--				isSand = true
	--				break
	--			end
	--		end
	--	end
	--end

	print(5)

	--if not isSand then return end

	createBomb(player, position)
end)


return BombManager
