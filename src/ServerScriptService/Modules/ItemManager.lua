--!strict
-- LOCATION: ServerScriptService/Modules/ItemManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- [ MODULES ]
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)
local MutationConfigurations = require(ReplicatedStorage.Modules.MutationConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local LuckyBlockManager = require(ServerScriptService.Modules.LuckyBlockManager)
local TutorialService = require(ServerScriptService.Modules.TutorialService)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local ConfigItems = require(ReplicatedStorage.Modules.ItemConfigurations)
local Constants = require(ReplicatedStorage.Modules.Constants)

-- [ LAZY DEPENDENCIES ]
local CarrySystem 

-- [ ASSETS ]
local LuckyBlocksFolder = ReplicatedStorage:WaitForChild("Luckyblocks")
local ItemsFolder = ReplicatedStorage:WaitForChild("Items")
local MinesFolder = Workspace:WaitForChild("Mines")
local Templates = ReplicatedStorage:WaitForChild("Templates")
local InfoGUI_Template = Templates:WaitForChild("InfoGUI")
local CollectionZones = Workspace:WaitForChild("Zones")

-- [ CONFIGURATION ]
local INCOME_SCALING = Constants.INCOME_SCALING
local RECYCLE_MIN_TIME = Constants.RECYCLE_MIN_TIME
local RECYCLE_MAX_TIME = Constants.RECYCLE_MIN_TIME
local RESPAWN_TIME = Constants.RESPAWN_TIME
local DROPPED_LIFETIME = Constants.DROPPED_LIFETIME
local MAX_ITEMS_PER_MINE = Constants.MAX_ITEMS_PER_MINE 
local MIN_ITEM_SPACING = Constants.MIN_ITEM_SPACING

local SPAWNER_TIERS = Constants.SPAWNER_TIERS

local DEFAULT_CHANCE = Constants.DEFAULT_CHANCE

local MUTATIONS = Constants.MUTATIONS

local MUTATION_MULTIPLIERS = Constants.MUTATION_MULTIPLIERS

local ItemManager = {}

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

-- Read Event State 
local function getMutation(): string
	local isGoldEvent = false --Workspace:GetAttribute("GoldEventActive") == true

	for _, mutation in ipairs(MUTATIONS) do
		local roll = math.random(1, mutation.Chance)
		if roll == 1 then return mutation.Name end
	end

	-- If the event is active, the lowest possible rarity is Golden! 
	return isGoldEvent and "Golden" or "Normal"
end

local function getRarityFromTier(tierName: string): string
	local chances = SPAWNER_TIERS[tierName] or DEFAULT_CHANCE
	local totalWeight = 0

	for _, weight in pairs(chances) do totalWeight += weight end

	local roll = math.random(0, totalWeight)
	local current = 0

	for rarity, weight in pairs(chances) do
		current += weight
		if roll <= current then return rarity end
	end
	return "Common"
end

-- [ VISUALS & GUI ]
local function setupItemGUI(target: Instance, level: number?, rebirths: number?, isVip: boolean?)
	local rootPart: BasePart?

	if target:IsA("Model") then
		rootPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	elseif target:IsA("Tool") then
		rootPart = target:FindFirstChild("Handle") :: BasePart
	end

	if not rootPart then return end
	if target:FindFirstChild("InfoGUI") then target.InfoGUI:Destroy() end

	local infoGui = InfoGUI_Template:Clone()
	infoGui.Name = "InfoGUI"
	local labelsFrame = infoGui:WaitForChild("TextLabels")

	local lblEarnings = labelsFrame:WaitForChild("Earnings") :: TextLabel
	local lblRarity = labelsFrame:WaitForChild("Rarity") :: TextLabel
	local lblName = labelsFrame:WaitForChild("Name") :: TextLabel
	local lblMutation = labelsFrame:WaitForChild("Mutation") :: TextLabel
--~!
	local itemName = target:GetAttribute("OriginalName") or "Unknown"
	local rarityName = target:GetAttribute("Rarity") or "Common"
	local mutationName = target:GetAttribute("Mutation") or "Normal"

	lblName.Text = ConfigItems.Items[target:GetAttribute("OriginalName") or "Unknown"].DisplayName


	local itemData = ItemConfigurations.GetItemData(itemName)
	local baseIncome = itemData and itemData.Income or 0

	local reb = rebirths or 0
	local rebMult = 1 + (reb * 0.5)
	local vipMult = isVip and 1.5 or 1

	local totalIncome = baseIncome * (MUTATION_MULTIPLIERS[mutationName] or 1) * (INCOME_SCALING ^ ((level or 1) - 1)) * rebMult * vipMult

	lblEarnings.Text = "+" .. NumberFormatter.Format(totalIncome) .. "/s"

	local rarityConfig = RarityConfigurations[rarityName]
	if rarityConfig then
		lblRarity.Text = rarityConfig.DisplayName
		lblRarity.TextColor3 = rarityConfig.TextColor
		local stroke = lblRarity:FindFirstChild("UIStroke") or lblRarity:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = rarityConfig.StrokeColor; stroke.Thickness = rarityConfig.StrokeThickness end
		local gradient = lblRarity:FindFirstChild("UIGradient") or lblRarity:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Color = rarityConfig.GradientColor end
	end

	local mutationConfig = MutationConfigurations[mutationName]
	if mutationConfig then
		lblMutation.Text = mutationConfig.DisplayName
		lblMutation.TextColor3 = mutationConfig.TextColor
		local stroke = lblMutation:FindFirstChild("UIStroke") or lblMutation:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = mutationConfig.StrokeColor; stroke.Thickness = mutationConfig.StrokeThickness end
		local gradient = lblMutation:FindFirstChild("UIGradient") or lblMutation:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Color = mutationConfig.GradientColor end
	end

	infoGui.Adornee = rootPart
	infoGui.Parent = target

end

-- [ TOOL CREATION ]
function ItemManager.GiveItemToPlayer(player: Player, itemName: string, mutation: string, rarity: string, level: number?, isTemporary: boolean?)
	if not itemName then return nil end

	local itemConf = ItemConfigurations.GetItemData(itemName)
	local mutationFolder = ItemsFolder:FindFirstChild(mutation) or ItemsFolder.Normal
	local itemTemplate = mutationFolder:FindFirstChild(itemName) or ItemsFolder.Normal:FindFirstChild(itemName)

	if not itemTemplate then return nil end
	if isTemporary then return nil end

	local newTool = Instance.new("Tool")
	newTool.Name = itemName
	if itemConf then newTool.TextureId = itemConf.ImageId end

	newTool:SetAttribute("IsTemporary", false)
	newTool:SetAttribute("OriginalName", itemName)
	newTool:SetAttribute("Mutation", mutation)
	newTool:SetAttribute("Rarity", rarity)
	newTool:SetAttribute("Level", level or 1)
	newTool:SetAttribute("IsSpawnedItem", false) 

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Transparency = 1
	handle.Size = Vector3.new(1, 1, 1)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = newTool

	local model = itemTemplate:Clone()
	model.Name = "StackedItem"
	model:SetAttribute("OriginalName", itemName)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Level", level or 1)
	model:SetAttribute("IsSpawnedItem", false)

	model.Parent = newTool
	model:PivotTo(handle.CFrame)

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle
			w.Part1 = p
			w.Parent = p
		end
	end

	newTool.Parent = player:WaitForChild("Backpack")
	return newTool
end
function ItemManager.GiveLuckyBlockToPlayer(player: Player, blockId: string)
	if not player then
		warn("[ItemManager] GiveLuckyBlockToPlayer called without a player")
		return nil
	end

	local blockConfig = LuckyBlockManager.GetBlockConfig(blockId)
	if not blockConfig then
		warn("[ItemManager] Lucky block config not found:", blockId)
		return nil
	end

	local blockTemplate = LuckyBlocksFolder:FindFirstChild(blockConfig.ModelName)
	if not blockTemplate or not blockTemplate:IsA("Model") then
		warn("[ItemManager] Lucky block model not found:", blockConfig.ModelName)
		return nil
	end

	local newTool = Instance.new("Tool")
	newTool.Name = blockConfig.DisplayName
	newTool.CanBeDropped = false
	newTool.RequiresHandle = true
	newTool.TextureId = blockConfig.Image

	newTool:SetAttribute("LuckyBlockId", blockConfig.Id)
	newTool:SetAttribute("Rarity", blockConfig.Rarity)
	newTool:SetAttribute("DisplayName", blockConfig.DisplayName)
	newTool:SetAttribute("IsLuckyBlock", true)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Transparency = 1
	handle.Size = Vector3.new(1, 1, 1)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = newTool

	local model = blockTemplate:Clone()
	model.Name = "StackedItem"
	model:ScaleTo(blockConfig.Scale)
	model:SetAttribute("LuckyBlockId", blockConfig.Id)
	model:SetAttribute("Rarity", blockConfig.Rarity)
	model:SetAttribute("IsLuckyBlock", true)
	model.Parent = newTool

	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not rootPart then
		warn("[ItemManager] Lucky block model has no root part:", blockConfig.ModelName)
		newTool:Destroy()
		return nil
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	model:PivotTo(handle.CFrame)
	newTool.Parent = player:WaitForChild("Backpack")
	return newTool
end

-- [ PICKUP LOGIC ]
local function onItemPickedUp(player: Player, itemModel: Model)
	if not CarrySystem then CarrySystem = require(ServerScriptService.Modules.CarrySystem) end
	if not itemModel or not itemModel.Parent then return end

	local spawnerPart = itemModel.Parent 

	local name = itemModel:GetAttribute("OriginalName")
	local mutation = itemModel:GetAttribute("Mutation")
	local rarity = itemModel:GetAttribute("Rarity")
	local level = itemModel:GetAttribute("Level") or 1 

	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")

	if name and mutation and rarity and rootPart then
		local inZone = isInsideAnyZone(rootPart.Position)
		local pickedUp = false

		if inZone then
			local source = if spawnerPart:IsA("BasePart") then spawnerPart else nil

			if CarrySystem.CanCarryMore(player) then
				local success = CarrySystem.AddItemToCarry(player, name, mutation, rarity, source)
				if success then pickedUp = true end
			else
				local Events = ReplicatedStorage:FindFirstChild("Events")
				local notif = Events and Events:FindFirstChild("ShowNotification")
				if notif then notif:FireClient(player, "Carry limit reached!", "Error") end
				AnalyticsFunnelsService:LogFailure(player, "carry_limit_reached", {
					zone = "mine",
				})
			end
		else
			ItemManager.GiveItemToPlayer(player, name, mutation, rarity, level, false)
			pickedUp = true
		end

		if pickedUp then 
			TutorialService:HandleBrainrotPickedUp(player)
			AnalyticsFunnelsService:HandleMineBrainrotPickedUp(player)
			itemModel:Destroy() 

			-- ## FIXED: Queue a replacement immediately when an item is picked up! ##
			if spawnerPart and spawnerPart:IsA("BasePart") then
				ItemManager.RespawnItem(spawnerPart)
			end
		end
	end
end

-- [ SPAWNING LOGIC ]
function ItemManager.SpawnVisualItem(parentPart: BasePart, itemName: string, mutation: string, rarity: string, level: number, rebirths: number?, isVip: boolean?)
	local mutationFolder = ItemsFolder:FindFirstChild(mutation) or ItemsFolder:FindFirstChild("Normal")
	local itemTemplate = mutationFolder:FindFirstChild(itemName) or ItemsFolder.Normal:FindFirstChild(itemName)

	if not itemTemplate then return end

	local model = itemTemplate:Clone() :: Model
	model.Name = "VisualItem"
	model:SetAttribute("OriginalName", itemName)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Level", level)
	model:SetAttribute("IsSpawnedItem", false)

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true; part.CanCollide = false
		end
	end

	local extents = model:GetExtentsSize()
	local offset = Vector3.new(0, extents.Y/2, 0)
	model:PivotTo(parentPart.CFrame + offset)
	model.Parent = parentPart

	setupItemGUI(model, level, rebirths, isVip)

	CollectionService:AddTag(model, "FloatingItem")
end

function ItemManager.SpawnInMine(mineZonePart: BasePart)
	if not mineZonePart or not mineZonePart.Parent then return end

	local currentItems = 0
	local existingPositions = {}
	for _, child in ipairs(mineZonePart:GetChildren()) do
		if child.Name == "SpawnedItem" and child:IsA("Model") then
			currentItems += 1
			table.insert(existingPositions, child:GetPivot().Position)
		end
	end

	-- ## Calculates exactly how many are missing to hit MAX_ITEMS_PER_MINE ##
	local itemsToSpawn = MAX_ITEMS_PER_MINE - currentItems
	if itemsToSpawn <= 0 then return end

	local tier = mineZonePart.Name 
	local rarity = getRarityFromTier(tier)
	local possibleItems = ItemConfigurations.GetItemsByRarity(rarity)
	if #possibleItems == 0 then return end

	for i = 1, itemsToSpawn do
		local randomItemName = nil
		local mutationName = getMutation()
		local itemTemplate = nil

		for j = 1, 5 do
			randomItemName = possibleItems[math.random(1, #possibleItems)]
			local mutationFolder = ItemsFolder:FindFirstChild(mutationName) or ItemsFolder.Normal
			itemTemplate = mutationFolder:FindFirstChild(randomItemName) or ItemsFolder.Normal:FindFirstChild(randomItemName)

			if itemTemplate then break end
		end

		if not itemTemplate then continue end

		local newItem = itemTemplate:Clone() :: Model
		newItem.Name = "SpawnedItem"

		CollectionService:AddTag(newItem, "HelicopterIgnore")

		newItem:SetAttribute("IsSpawnedItem", true)
		newItem:SetAttribute("OriginalName", randomItemName)
		newItem:SetAttribute("Rarity", rarity)
		newItem:SetAttribute("Mutation", mutationName)
		newItem:SetAttribute("Level", 1)

		newItem:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + math.random(RECYCLE_MIN_TIME, RECYCLE_MAX_TIME))

		for _, part in ipairs(newItem:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Anchored = true
			end
		end

		local itemExtents = newItem:GetExtentsSize()
		local distToBottom = newItem:GetPivot().Position.Y - (newItem:GetBoundingBox().Position.Y - (itemExtents.Y / 2))

		local maxAttempts = 15
		local spawnCFrame
		local randomRot = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)

		for attempt = 1, maxAttempts do
			--local randomX = (math.random() - 0.5) * (mineZonePart.Size.X * 0.9)
			--local randomZ = (math.random() - 0.5) * (mineZonePart.Size.Z * 0.9)

			local randomX = (math.random() - 0.5) * (mineZonePart.Size.X * 0.9)
			local randomY = (math.random() - 0.5) * mineZonePart.Size.Y
			local randomZ = (math.random() - 0.5) * (mineZonePart.Size.Z * 0.9)


			spawnCFrame = CFrame.new((mineZonePart.CFrame * CFrame.new(randomX, randomY, randomZ)).Position)

			local tooClose = false
			for _, pos in ipairs(existingPositions) do
				local dist = Vector2.new(spawnCFrame.Position.X - pos.X, spawnCFrame.Position.Z - pos.Z).Magnitude
				if dist < MIN_ITEM_SPACING then
					tooClose = true
					break
				end
			end

			if not tooClose then break end
		end

		if spawnCFrame then
			table.insert(existingPositions, spawnCFrame.Position)

			newItem:PivotTo(spawnCFrame * randomRot + Vector3.new(0, distToBottom, 0))
			newItem.Parent = mineZonePart

			setupItemGUI(newItem, 1, 0, false)

			CollectionService:AddTag(newItem, "FloatingItem")

			if newItem.PrimaryPart then
				local prompt = Instance.new("ProximityPrompt")
				prompt.ObjectText = randomItemName
				prompt.ActionText = "Pick Up"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false 
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 8 
				prompt.Style = Enum.ProximityPromptStyle.Custom
				prompt.Parent = newItem.PrimaryPart

				prompt.Triggered:Connect(function(player) onItemPickedUp(player, newItem) end)
			end

			local expireTime = newItem:GetAttribute("ExpiresAt")
			local lifetime = expireTime - Workspace:GetServerTimeNow()

			task.delay(lifetime, function()
				if newItem and newItem.Parent then
					newItem:Destroy()
					ItemManager.SpawnInMine(mineZonePart)
				end
			end)
		end
	end
end

function ItemManager.SpawnDroppedItem(itemName: string, mutation: string, rarity: string, targetPos: Vector3, originPos: Vector3?)
	local mutationFolder = ItemsFolder:FindFirstChild(mutation) or ItemsFolder.Normal
	local itemTemplate = mutationFolder:FindFirstChild(itemName) or ItemsFolder.Normal:FindFirstChild(itemName)

	if not itemTemplate then return end

	local newItem = itemTemplate:Clone() :: Model
	newItem.Name = "SpawnedItem"

	CollectionService:AddTag(newItem, "HelicopterIgnore")

	newItem:SetAttribute("IsSpawnedItem", true)
	newItem:SetAttribute("OriginalName", itemName)
	newItem:SetAttribute("Mutation", mutation)
	newItem:SetAttribute("Rarity", rarity)
	newItem:SetAttribute("Level", 1)

	newItem:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + DROPPED_LIFETIME)

	for _, part in ipairs(newItem:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = true
		end
	end

	local rayOrigin = targetPos + Vector3.new(0, 5, 0)
	local rayDirection = Vector3.new(0, -20, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {newItem}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local floorY = result and result.Position.Y or targetPos.Y

	local itemExtents = newItem:GetExtentsSize()
	local distToBottom = newItem:GetPivot().Position.Y - (newItem:GetBoundingBox().Position.Y - (itemExtents.Y / 2))

	local finalCFrame = CFrame.new(targetPos.X, floorY + distToBottom, targetPos.Z) * CFrame.Angles(0, math.random(0,360), 0)

	newItem.Parent = Workspace

	if originPos then
		newItem:PivotTo(CFrame.new(originPos))

		local cfValue = Instance.new("CFrameValue")
		cfValue.Value = CFrame.new(originPos)
		cfValue.Parent = newItem 

		cfValue.Changed:Connect(function(val)
			if newItem.Parent then newItem:PivotTo(val) end
		end)

		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(cfValue, tweenInfo, {Value = finalCFrame})
		tween:Play()

		tween.Completed:Connect(function() 
			cfValue:Destroy() 
			CollectionService:AddTag(newItem, "FloatingItem")
		end)
	else
		newItem:PivotTo(finalCFrame)
		CollectionService:AddTag(newItem, "FloatingItem")
	end

	setupItemGUI(newItem, 1, 0, false)

	if newItem.PrimaryPart then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = itemName
		prompt.ActionText = "Pick Up"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false 
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 16 

		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Parent = newItem.PrimaryPart

		prompt.Triggered:Connect(function(player) onItemPickedUp(player, newItem) end)
	end

	local lifetime = DROPPED_LIFETIME
	task.delay(lifetime, function()
		if newItem and newItem.Parent then newItem:Destroy() end
	end)
end

function ItemManager.RespawnItem(mineZonePart: BasePart)
	task.delay(RESPAWN_TIME, function() ItemManager.SpawnInMine(mineZonePart) end)
end

function ItemManager.SpawnAllItems()
	for _, spawner in ipairs(MinesFolder:GetChildren()) do
		if spawner:IsA("BasePart") then ItemManager.SpawnInMine(spawner) end
	end
end

Players.PlayerAdded:Connect(function(player) if not RunService:IsRunning() then return end ItemManager.SpawnAllItems() end)

-- =========================================================================
-- ## GOLD EVENT GLOBAL LOOP ##
-- =========================================================================
--local GOLD_EVENT_COOLDOWN = 300 -- 5 Minutes wait time
--local GOLD_EVENT_DURATION = 60  -- 1 Minute active time

task.spawn(function()
	local Events = ReplicatedStorage:WaitForChild("Events")

	--while true do
	--	-- 1. COOLDOWN STATE
	--	--Workspace:SetAttribute("GoldEventActive", false)
	--	--Workspace:SetAttribute("GoldEventTime", os.time() + GOLD_EVENT_COOLDOWN)

	--	task.wait(GOLD_EVENT_COOLDOWN)

	--	-- 2. ACTIVE STATE
	--	--Workspace:SetAttribute("GoldEventActive", true)
	--	--Workspace:SetAttribute("GoldEventTime", os.time() + GOLD_EVENT_DURATION)

	--	-- Notify all players the event started
	--	local notif = Events:FindFirstChild("ShowNotification")
	--	if notif then
	--		notif:FireAllClients("🌟 Gold Event Started! 🌟", "Success")
	--	end

	--	--task.wait(GOLD_EVENT_DURATION)

	--	-- Notify all players the event ended
	--	if notif then
	--		notif:FireAllClients("Gold Event Ended!", "Error")
	--	end
	--end
end)

-- =========================================================================
-- ## MAINTENANCE LOOP (Guarantees mines stay perfectly full) ##
-- =========================================================================
task.spawn(function()
	if not RunService:IsRunning() then return end
	while true do
		task.wait(10) -- Checks all mines every 10 seconds
		ItemManager.SpawnAllItems()
	end
end)

return ItemManager
