--!strict
-- LOCATION: ServerScriptService/Modules/CarrySystem

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local CarrySystem = {}

-- [ MODULES ]
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local PlayerController = require(ServerScriptService.Controllers.PlayerController) 
local BadgeManager = require(ServerScriptService.Modules.BadgeManager)
local TutorialService = require(ServerScriptService.Modules.TutorialService)
local ItemManager -- Lazy Loaded
local PickaxeController -- ## ADDED ##

-- [ ASSETS ]
local CollectionZones = Workspace:WaitForChild("Zones")
local Templates = ReplicatedStorage:WaitForChild("Templates")
local ConfettiTemplate = Templates:WaitForChild("Confetti") 
local ItemsFolder = ReplicatedStorage:WaitForChild("Items")
local Events = ReplicatedStorage:WaitForChild("Events")
local GlobalSounds = Workspace:WaitForChild("Sounds")

-- [ DATA ]
local carryingData: {[Player]: {any}} = {}
local playersInZone: {[Player]: boolean} = {}
local lastLimitNotif: {[Player]: number} = {}

-- [ CONFIG ]
local CHECK_INTERVAL = 0.2 
local STACK_GAP = 0.5 

-- [ HELPERS ]
local function isInsideAnyZone(position: Vector3): boolean
	for _, zonePart in ipairs(CollectionZones:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size

			local inside = math.abs(relativePos.X) <= size.X / 2 and
				math.abs(relativePos.Y) <= size.Y / 2 and
				math.abs(relativePos.Z) <= size.Z / 2

			if inside then return true end
		end
	end
	return false
end

local function createStackItem(player: Player, itemName: string, mutation: string)
	local character = player.Character
	if not character then return nil end

	local headPart = character:FindFirstChild("Head") :: BasePart
	if not headPart then return nil end

	local mutationFolder = ItemsFolder:FindFirstChild(mutation) or ItemsFolder.Normal
	local template = mutationFolder:FindFirstChild(itemName) or ItemsFolder.Normal:FindFirstChild(itemName)
	if not template then return nil end

	local model = template:Clone() :: Model
	model.Name = "StackItem"

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then return nil end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.Massless = true
			desc.Anchored = false
		elseif desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	local currentItems = carryingData[player] or {}
	local itemSize = model:GetExtentsSize()

	model.Parent = character

	local totalHeight = (headPart.Size.Y / 2) + 0.8 + STACK_GAP

	for _, data in ipairs(currentItems) do
		if data.VisualModel and data.VisualModel:IsA("Model") then
			totalHeight = totalHeight + data.VisualModel:GetExtentsSize().Y + STACK_GAP
		end
	end
	totalHeight = totalHeight + (itemSize.Y / 2)

	model:PivotTo(headPart.CFrame * CFrame.new(0, totalHeight, 0))

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = headPart
	weld.Part1 = primary
	weld.Parent = primary

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Part0 = primary
			w.Part1 = part
			w.Parent = part
		end
	end

	return model
end

local function clearVisualStack(player: Player)
	local items = carryingData[player]
	if items then
		for _, data in ipairs(items) do
			if data.VisualModel and data.VisualModel.Parent then
				data.VisualModel:Destroy()
			end
		end
	end
end

-- [ PUBLIC API ]
function CarrySystem.IsPlayerInZone(player: Player): boolean
	return playersInZone[player] == true
end

function CarrySystem.CanCarryMore(player: Player): boolean
	local current = carryingData[player] or {}
	local profile = PlayerController:GetProfile(player)
	local limit = profile and profile.Data.CarryCapacity or 1
	return #current < limit
end

function CarrySystem.AddItemToCarry(player: Player, name: string, mutation: string, rarity: string)
	if not carryingData[player] then carryingData[player] = {} end

	if CarrySystem.CanCarryMore(player) then
		local visualModel = createStackItem(player, name, mutation)

		table.insert(carryingData[player], {
			Name = name,
			Mutation = mutation,
			Rarity = rarity,
			VisualModel = visualModel
		})
		return true
	end

	local currentTime = tick()
	if not lastLimitNotif[player] or (currentTime - lastLimitNotif[player] > 2) then
		lastLimitNotif[player] = currentTime
		local notif = Events:FindFirstChild("ShowNotification")
		if notif then notif:FireClient(player, "Carry limit reached!", "Error") end
	end

	return false
end

function CarrySystem.ClearAllItems(player: Player)
	clearVisualStack(player)
	carryingData[player] = {}
end

function CarrySystem.DropItemsAtFeet(player: Player)
	local items = carryingData[player]
	if not items or #items == 0 then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart

	if root then
		local dropPos = root.Position + (root.CFrame.LookVector * 4)
		local head = char:FindFirstChild("Head") :: BasePart
		local originPos = head and head.Position or root.Position

		for _, itemData in ipairs(items) do
			ItemManager.SpawnDroppedItem(
				itemData.Name,
				itemData.Mutation,
				itemData.Rarity,
				dropPos,
				originPos
			)
		end
	end

	CarrySystem.ClearAllItems(player)
end

function CarrySystem.HasCarriedItems(player: Player): boolean
	local items = carryingData[player]
	return items ~= nil and #items > 0
end

function CarrySystem.DropOneItemAtFeet(player: Player): boolean
	local items = carryingData[player]
	if not items or #items == 0 then
		return false
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then
		return false
	end

	local itemData = table.remove(items, #items)
	if not itemData then
		return false
	end

	if itemData.VisualModel and itemData.VisualModel.Parent then
		itemData.VisualModel:Destroy()
	end

	local head = char:FindFirstChild("Head") :: BasePart
	local originPos = head and head.Position or root.Position
	local dropPos = root.Position + (root.CFrame.LookVector * 3)

	ItemManager.SpawnDroppedItem(
		itemData.Name,
		itemData.Mutation,
		itemData.Rarity,
		dropPos,
		originPos
	)

	return true
end

-- [ ZONE LOGIC ]
local function processZoneExit(player: Player)
	local items = carryingData[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local isDead = not humanoid or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead
	local isAlive = not isDead

	if isAlive then
		TutorialService:HandleMineZoneExited(player)
	end

	if items and #items > 0 then
		if isAlive then
			local lastGivenTool = nil
			local profile = PlayerController:GetProfile(player)
			local totalCollected = profile and (profile.Data.TotalBrainrotsCollected or 0) or 0

			for _, itemData in ipairs(items) do
				-- Capture the returned tool
				local newTool = ItemManager.GiveItemToPlayer(player, itemData.Name, itemData.Mutation, itemData.Rarity, 1, false)
				if newTool then lastGivenTool = newTool end
				totalCollected += 1
				BadgeManager:EvaluateBrainrotMilestones(player, itemData.Rarity, totalCollected)
			end

			if profile then
				profile.Data.TotalBrainrotsCollected = totalCollected
			end

			-- Auto-Equip the newly received item
			if lastGivenTool and humanoid then
				humanoid:EquipTool(lastGivenTool)
			end

			local successSound = GlobalSounds:FindFirstChild("Success")
			if successSound then
				local s = successSound:Clone(); s.Parent = player:WaitForChild("PlayerGui"); s:Play(); Debris:AddItem(s, 3)
			end

			if character:FindFirstChild("HumanoidRootPart") then
				local confetti = ConfettiTemplate:Clone(); confetti.Parent = character.HumanoidRootPart
				for _, child in ipairs(confetti:GetChildren()) do
					if child:IsA("ParticleEmitter") then child:Emit(child:GetAttribute("EmitCount") or 20) end
				end
				Debris:AddItem(confetti, 3)
			end

			local notif = Events:FindFirstChild("ShowNotification")
			if notif then notif:FireClient(player, "Items Unlocked!", "Success") end

			local effectEvent = Events:FindFirstChild("TriggerUIEffect")
			if effectEvent then 
				effectEvent:FireClient(player, "FOVPop") 
			end
		end

		CarrySystem.ClearAllItems(player)
	end
end

local function processZoneEnter(player: Player)
	if not carryingData[player] then carryingData[player] = {} end
	TutorialService:HandleMineZoneEntered(player)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Hide any equipped carryable/tool item when the player goes back into the mine.
		humanoid:UnequipTools()
	end

	-- ## FIXED: Auto-Equip the player's Pickaxe when re-entering the mine! ##
	local profile = PlayerController:GetProfile(player)
	if profile and PickaxeController then
		local equippedPickaxe = profile.Data.EquippedPickaxe or "Bomb 1"
		PickaxeController.EquipPickaxe(player, equippedPickaxe)
	end
end

function CarrySystem:Init()
	local Modules = ServerScriptService:WaitForChild("Modules")
	ItemManager = require(Modules:WaitForChild("ItemManager"))

	-- ## ADDED: Pull the PickaxeController so we can use it to auto-equip ##
	local Controllers = ServerScriptService:WaitForChild("Controllers")
	PickaxeController = require(Controllers:WaitForChild("PickaxeController"))

	local dropEvent = Events:FindFirstChild("RequestDropItem")
	if not dropEvent then
		dropEvent = Instance.new("RemoteEvent")
		dropEvent.Name = "RequestDropItem"
		dropEvent.Parent = Events
	end

	dropEvent.OnServerEvent:Connect(function(player)
		if playersInZone[player] then
			CarrySystem.DropItemsAtFeet(player)
		end
	end)

	local clearEvent = Events:FindFirstChild("RequestClearCarry")
	if not clearEvent then
		clearEvent = Instance.new("RemoteEvent")
		clearEvent.Name = "RequestClearCarry"
		clearEvent.Parent = Events
	end

	clearEvent.OnServerEvent:Connect(function(player)
		CarrySystem.ClearAllItems(player)
	end)
end

function CarrySystem:Start()
	local function onPlayerAdded(player)
		player.CharacterAdded:Connect(function() carryingData[player] = {} end)
	end

	for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
	Players.PlayerAdded:Connect(onPlayerAdded)

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local foundPlayers = {}
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character then
					local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
					if rootPart and isInsideAnyZone(rootPart.Position) then
						foundPlayers[player] = true
					end
				end
			end
			for player, _ in pairs(playersInZone) do
				if not foundPlayers[player] then
					playersInZone[player] = nil
					processZoneExit(player)
				end
			end
			for player, _ in pairs(foundPlayers) do
				if not playersInZone[player] then
					playersInZone[player] = true
					processZoneEnter(player)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		carryingData[player] = nil
		playersInZone[player] = nil
		lastLimitNotif[player] = nil
	end)
end

return CarrySystem
