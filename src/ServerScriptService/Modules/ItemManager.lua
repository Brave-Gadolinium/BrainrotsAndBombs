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
local BrainrotEventConfiguration = require(ReplicatedStorage.Modules.BrainrotEventConfiguration)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)
local RarityUtils = require(ReplicatedStorage.Modules.RarityUtils)
local MutationConfigurations = require(ReplicatedStorage.Modules.MutationConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local LuckyBlockManager = require(ServerScriptService.Modules.LuckyBlockManager)
local TutorialService = require(ServerScriptService.Modules.TutorialService)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local Constants = require(ReplicatedStorage.Modules.Constants)
local RebirthRequirements = require(ReplicatedStorage.Modules.RebirthRequirements)
local MineSpawnUtils = require(ServerScriptService.Modules.MineSpawnUtils)

-- [ LAZY DEPENDENCIES ]
local CarrySystem 
local onItemPickedUp: (player: Player, itemModel: Model) -> ()

-- [ ASSETS ]
local LuckyBlocksFolder = ReplicatedStorage:WaitForChild("Luckyblocks")
local ItemsFolder = ReplicatedStorage:WaitForChild("Items")
local MinesFolder = Workspace:WaitForChild("Mines")
local Templates = ReplicatedStorage:WaitForChild("Templates")
local InfoGUI_Template = Templates:WaitForChild("InfoGUI")
local CollectionZones = Workspace:WaitForChild("Zones")

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

local function ensureRoundStartedEvent(): BindableEvent
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

	local roundStarted = timerFolder:FindFirstChild("RoundStarted")
	if not roundStarted then
		roundStarted = Instance.new("BindableEvent")
		roundStarted.Name = "RoundStarted"
		roundStarted.Parent = timerFolder
	end

	return roundStarted :: BindableEvent
end

-- [ CONFIGURATION ]
local INCOME_SCALING = Constants.INCOME_SCALING
local RESPAWN_TIME = Constants.RESPAWN_TIME
local SESSION_DURATION = Constants.SESSION_DURATION
local SESSION_END_MESSAGE_DURATION = Constants.SESSION_END_MESSAGE_DURATION
local MIN_ITEM_SPACING = Constants.MIN_ITEM_SPACING
local ZONE_ITEM_CAPS = Constants.ZONE_ITEM_CAPS or {}
local ITEM_SPAWN_BATCH_SIZE = math.max(1, tonumber(Constants.ITEM_SPAWN_BATCH_SIZE) or 8)
local ITEM_SPAWN_BATCH_YIELD = math.max(0, tonumber(Constants.ITEM_SPAWN_BATCH_YIELD) or 0.03)
local FinishTime = ensureTimerFinishEvent()
local RoundStarted = ensureRoundStartedEvent()

local SPAWNER_TIERS = Constants.SPAWNER_TIERS

local DEFAULT_CHANCE = Constants.DEFAULT_CHANCE

local MUTATION_DEPTH_BANDS = Constants.MUTATION_DEPTH_BANDS or {}

local MUTATION_MULTIPLIERS = Constants.MUTATION_MULTIPLIERS

local ItemManager = {}
local itemAttributes = BrainrotEventConfiguration.ItemAttributes
local fallbackItemTemplates: {[string]: Model} = {}
local VISUAL_ITEM_VERTICAL_OFFSET = -0.75
local FALLBACK_ITEM_SIZE = Vector3.new(2.4, 2.4, 2.4)
local WORLD_ITEM_PICKUP_DISTANCE = 16
local LUCKY_BLOCK_TOOL_FORWARD_OFFSET = 2.25
local EVENT_WORLD_ITEM_TAG = "EventBrainrotWorldItem"
local queuedMineZones: {[BasePart]: boolean} = {}
local mineSpawnQueue: {BasePart} = {}
local spawnWorkerRunning = false
local pendingRoundRefill = false

local function getConcreteItemTemplate(itemName: string, mutation: string?): Model?
	local normalFolder = ItemsFolder:FindFirstChild("Normal")
	local mutationFolder = if type(mutation) == "string" and mutation ~= "" then ItemsFolder:FindFirstChild(mutation) else nil

	local mutationTemplate = mutationFolder and mutationFolder:FindFirstChild(itemName)
	if mutationTemplate and mutationTemplate:IsA("Model") then
		return mutationTemplate
	end

	local normalTemplate = normalFolder and normalFolder:FindFirstChild(itemName)
	if normalTemplate and normalTemplate:IsA("Model") then
		return normalTemplate
	end

	return nil
end

local function hasItemTemplate(itemName: string, mutation: string?): boolean
	return getConcreteItemTemplate(itemName, mutation) ~= nil
end

local function canBuildFallbackItem(itemName: string): boolean
	return (ItemConfigurations.GetItemData(itemName) :: any) ~= nil
end

local function getFallbackItemColor(mutation: string, rarity: string): Color3
	local mutationConfig = (MutationConfigurations :: any)[mutation]
	if mutation ~= "Normal" and mutationConfig and mutationConfig.TextColor then
		return mutationConfig.TextColor
	end

	local normalizedRarity = RarityUtils.Normalize(rarity) or rarity
	local rarityConfig = (RarityConfigurations :: any)[normalizedRarity]
	if rarityConfig and rarityConfig.TextColor then
		return rarityConfig.TextColor
	end

	return Color3.fromRGB(255, 255, 255)
end

local function createFallbackItemTemplate(itemName: string, mutation: string, rarity: string): Model?
	local templateKey = `{itemName}:{mutation}:{RarityUtils.Normalize(rarity) or rarity}`
	local cachedTemplate = fallbackItemTemplates[templateKey]
	if cachedTemplate then
		return cachedTemplate:Clone()
	end

	local itemData = ItemConfigurations.GetItemData(itemName) :: any
	if not itemData then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = itemName

	local rootPart = Instance.new("Part")
	rootPart.Name = "Root"
	rootPart.Shape = Enum.PartType.Ball
	rootPart.Size = FALLBACK_ITEM_SIZE
	rootPart.Material = if mutation ~= "Normal" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	rootPart.Color = getFallbackItemColor(mutation, rarity)
	rootPart.TopSurface = Enum.SurfaceType.Smooth
	rootPart.BottomSurface = Enum.SurfaceType.Smooth
	rootPart.Parent = model

	model.PrimaryPart = rootPart
	fallbackItemTemplates[templateKey] = model

	return model:Clone()
end

local function createItemModel(itemName: string, mutation: string, rarity: string): Model?
	local concreteTemplate = getConcreteItemTemplate(itemName, mutation)
	if concreteTemplate then
		return concreteTemplate:Clone()
	end

	return createFallbackItemTemplate(itemName, mutation, rarity)
end

local function getSpawnableItemsByRarity(rarity: string, mutation: string): {string}
	local spawnableItems = {}

	for _, itemName in ipairs(ItemConfigurations.GetItemsByRarity(rarity)) do
		if hasItemTemplate(itemName, mutation) or canBuildFallbackItem(itemName) then
			table.insert(spawnableItems, itemName)
		end
	end

	return spawnableItems
end

local function validateRebirthRequirementTemplates()
	local checkedItems: {[string]: boolean} = {}

	for _, requirement in ipairs(RebirthRequirements.GetAll()) do
		for _, itemName in ipairs(requirement.item_required or {}) do
			if type(itemName) == "string" and itemName ~= "" and not checkedItems[itemName] then
				checkedItems[itemName] = true
				if not hasItemTemplate(itemName, "Normal") and not canBuildFallbackItem(itemName) then
					warn("[ItemManager] Missing rebirth-required item configuration:", itemName)
				end
			end
		end
	end
end

local function getRemainingSessionLifetime(): number
	local remaining = tonumber(Workspace:GetAttribute("SessionTimeRemaining"))
	if remaining and remaining > 0 then
		return remaining
	end

	return SESSION_DURATION
end

local function isSpawnedWorldItem(instance: Instance): boolean
	return instance:IsA("Model")
		and instance.Name == "SpawnedItem"
		and instance:GetAttribute("IsSpawnedItem") == true
end

local function syncWorldItemTags(itemModel: Model)
	if itemModel:GetAttribute(itemAttributes.IsEventBrainrot) == true then
		CollectionService:AddTag(itemModel, EVENT_WORLD_ITEM_TAG)
	else
		CollectionService:RemoveTag(itemModel, EVENT_WORLD_ITEM_TAG)
	end
end

local function clearSessionWorldItems()
	for _, mineZonePart in ipairs(MinesFolder:GetChildren()) do
		if mineZonePart:IsA("BasePart") then
			for _, child in ipairs(mineZonePart:GetChildren()) do
				if isSpawnedWorldItem(child) then
					child:Destroy()
				end
			end
		end
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if isSpawnedWorldItem(child) then
			child:Destroy()
		end
	end
end

local function applyExtraAttributes(instance: Instance, extraAttributes: {[string]: any}?)
	if type(extraAttributes) ~= "table" then
		return
	end

	for attributeName, attributeValue in pairs(extraAttributes) do
		instance:SetAttribute(attributeName, attributeValue)
	end
end

local function extractEventAttributes(instance: Instance?): {[string]: any}?
	if not instance then
		return nil
	end

	if instance:GetAttribute(itemAttributes.IsEventBrainrot) ~= true then
		return nil
	end

	local token = instance:GetAttribute(itemAttributes.Token)
	local rarity = instance:GetAttribute(itemAttributes.Rarity)
	local itemName = instance:GetAttribute(itemAttributes.ItemName)
	if type(token) ~= "string" or token == "" then
		return nil
	end

	return {
		[itemAttributes.IsEventBrainrot] = true,
		[itemAttributes.Token] = token,
		[itemAttributes.Rarity] = if type(rarity) == "string" then rarity else nil,
		[itemAttributes.ItemName] = if type(itemName) == "string" then itemName else nil,
	}
end

local function createPickupPrompt(itemModel: Model, objectText: string, maxDistance: number)
	if not itemModel.PrimaryPart then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = objectText
	prompt.ActionText = "Pick Up"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = maxDistance
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = itemModel.PrimaryPart

	prompt.Triggered:Connect(function(player)
		onItemPickedUp(player, itemModel)
	end)
end

local function createWorldItemModel(itemName: string, mutation: string, rarity: string, level: number?, extraAttributes: {[string]: any}?): Model?
	local newItem = createItemModel(itemName, mutation, rarity)
	if not newItem then
		return nil
	end

	newItem.Name = "SpawnedItem"

	CollectionService:AddTag(newItem, "HelicopterIgnore")

	newItem:SetAttribute("IsSpawnedItem", true)
	newItem:SetAttribute("OriginalName", itemName)
	newItem:SetAttribute("Mutation", mutation)
	newItem:SetAttribute("Rarity", rarity)
	newItem:SetAttribute("Level", level or 1)
	newItem:SetAttribute("ExpiresAt", Workspace:GetServerTimeNow() + getRemainingSessionLifetime())
	applyExtraAttributes(newItem, extraAttributes)
	syncWorldItemTags(newItem)

	for _, part in ipairs(newItem:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = true
		end
	end

	return newItem
end

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
local function rollWeightedMutation(weights: {[string]: number}?): string
	if type(weights) ~= "table" then
		return "Normal"
	end

	local totalWeight = 0
	for _, weight in pairs(weights) do
		totalWeight += weight
	end

	if totalWeight <= 0 then
		return "Normal"
	end

	local roll = math.random(1, totalWeight)
	local current = 0

	for mutationName, weight in pairs(weights) do
		current += weight
		if roll <= current then
			return mutationName
		end
	end

	return "Normal"
end

local function getDepthRatioForPosition(mineZonePart: BasePart, worldPosition: Vector3): number
	local localPosition = mineZonePart.CFrame:PointToObjectSpace(worldPosition)
	local halfHeight = mineZonePart.Size.Y * 0.5
	if halfHeight <= 0 then
		return 0
	end

	return math.clamp((halfHeight - localPosition.Y) / (halfHeight * 2), 0, 1)
end

local function getMutationForMinePosition(mineZonePart: BasePart, worldPosition: Vector3): string
	local isGoldEvent = false --Workspace:GetAttribute("GoldEventActive") == true
	local depthRatio = getDepthRatioForPosition(mineZonePart, worldPosition)

	for _, band in ipairs(MUTATION_DEPTH_BANDS) do
		local maxDepthRatio = tonumber((band :: any).MaxDepthRatio) or 1
		if depthRatio <= maxDepthRatio then
			return rollWeightedMutation((band :: any).Weights)
		end
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

local function getTargetItemCountForMine(mineZonePart: BasePart): number
	return math.max(0, math.floor(tonumber(ZONE_ITEM_CAPS[mineZonePart.Name]) or 0))
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
	local rawItemName = target:GetAttribute("OriginalName")
	local rawRarity = target:GetAttribute("Rarity")
	local rawMutation = target:GetAttribute("Mutation")
	local itemName = if type(rawItemName) == "string" and rawItemName ~= "" then rawItemName else target.Name
	local rarityName = RarityUtils.Normalize(if type(rawRarity) == "string" then rawRarity else nil) or "Common"
	local mutationName = if type(rawMutation) == "string" and rawMutation ~= "" then rawMutation else "Normal"
	local itemData = ItemConfigurations.GetItemData(itemName)
	lblName.Text = (itemData and itemData.DisplayName) or itemName or target.Name
	local baseIncome = itemData and itemData.Income or 0

	local reb = rebirths or 0
	local rebMult = 1 + (reb * 0.5)
	local vipMult = isVip and 1.5 or 1

	local totalIncome = baseIncome * (MUTATION_MULTIPLIERS[mutationName] or 1) * (INCOME_SCALING ^ ((level or 1) - 1)) * rebMult * vipMult

	lblEarnings.Text = "+" .. NumberFormatter.Format(totalIncome) .. "/s"

	local rarityConfig = RarityConfigurations[rarityName]
	lblRarity.Text = rarityName
	lblRarity.TextColor3 = Color3.fromRGB(255, 255, 255)
	if rarityConfig then
		lblRarity.Text = rarityConfig.DisplayName
		lblRarity.TextColor3 = rarityConfig.TextColor
		local stroke = lblRarity:FindFirstChild("UIStroke") or lblRarity:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = rarityConfig.StrokeColor; stroke.Thickness = rarityConfig.StrokeThickness end
		local gradient = lblRarity:FindFirstChild("UIGradient") or lblRarity:FindFirstChildOfClass("UIGradient")
		if gradient then gradient.Color = rarityConfig.GradientColor end
	end

	local mutationConfig = MutationConfigurations[mutationName]
	lblMutation.Text = mutationName
	lblMutation.TextColor3 = Color3.fromRGB(255, 255, 255)
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
function ItemManager.CreateItemModel(itemName: string, mutation: string, rarity: string): Model?
	return createItemModel(itemName, mutation, rarity)
end

function ItemManager.GiveItemToPlayer(
	player: Player,
	itemName: string,
	mutation: string,
	rarity: string,
	level: number?,
	isTemporary: boolean?,
	extraAttributes: {[string]: any}?
)
	if not itemName then return nil end

	local itemConf = ItemConfigurations.GetItemData(itemName)
	if isTemporary then return nil end

	local model = createItemModel(itemName, mutation, rarity)
	if not model then
		return nil
	end

	local newTool = Instance.new("Tool")
	newTool.Name = itemName
	newTool.CanBeDropped = false
	if itemConf then newTool.TextureId = itemConf.ImageId end

	newTool:SetAttribute("IsTemporary", false)
	newTool:SetAttribute("OriginalName", itemName)
	newTool:SetAttribute("Mutation", mutation)
	newTool:SetAttribute("Rarity", rarity)
	newTool:SetAttribute("Level", level or 1)
	newTool:SetAttribute("IsSpawnedItem", false) 
	applyExtraAttributes(newTool, extraAttributes)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Transparency = 1
	handle.Size = Vector3.new(1, 1, 1)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = newTool

	model.Name = "StackedItem"
	model:SetAttribute("OriginalName", itemName)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Level", level or 1)
	model:SetAttribute("IsSpawnedItem", false)
	applyExtraAttributes(model, extraAttributes)

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

	model:PivotTo(handle.CFrame * CFrame.new(0, 0, -LUCKY_BLOCK_TOOL_FORWARD_OFFSET))
	newTool.Parent = player:WaitForChild("Backpack")
	return newTool
end

-- [ PICKUP LOGIC ]
function onItemPickedUp(player: Player, itemModel: Model)
	if not CarrySystem then CarrySystem = require(ServerScriptService.Modules.CarrySystem) end
	if not itemModel or not itemModel.Parent then return end

	local spawnerPart = itemModel.Parent 

	local name = itemModel:GetAttribute("OriginalName")
	local mutation = itemModel:GetAttribute("Mutation")
	local rarity = itemModel:GetAttribute("Rarity")
	local level = itemModel:GetAttribute("Level") or 1 
	local eventAttributes = extractEventAttributes(itemModel)

	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")

	if name and mutation and rarity and rootPart then
		local inZone = isInsideAnyZone(rootPart.Position)
		local pickedUp = false

		if inZone then
			local source = if spawnerPart:IsA("BasePart") then spawnerPart else nil

			if CarrySystem.CanCarryMore(player) then
				local success = CarrySystem.AddItemToCarry(player, name, mutation, rarity, source, {
					Level = level,
					EventAttributes = eventAttributes,
				})
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
			ItemManager.GiveItemToPlayer(player, name, mutation, rarity, level, false, eventAttributes)
			pickedUp = true
		end

		if pickedUp then 
			TutorialService:HandleBrainrotPickedUp(player, inZone)
			AnalyticsFunnelsService:HandleMineBrainrotPickedUp(player)
			itemModel:Destroy() 

			-- ## FIXED: Queue a replacement immediately when an item is picked up! ##
			if spawnerPart and spawnerPart:IsA("BasePart") and not eventAttributes then
				ItemManager.RespawnItem(spawnerPart)
			end
		end
	end
end

-- [ SPAWNING LOGIC ]
function ItemManager.SpawnVisualItem(parentPart: BasePart, itemName: string, mutation: string, rarity: string, level: number, rebirths: number?, isVip: boolean?)
	local model = createItemModel(itemName, mutation, rarity)
	if not model then
		return
	end

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
	local offset = Vector3.new(0, (extents.Y / 2) + VISUAL_ITEM_VERTICAL_OFFSET, 0)
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

	local targetItemCount = getTargetItemCountForMine(mineZonePart)
	local itemsToSpawn = targetItemCount - currentItems
	if itemsToSpawn <= 0 then return end

	local tier = mineZonePart.Name 
	local rarity = getRarityFromTier(tier)
	local spawnedThisPass = 0

	local spawnCFrames = MineSpawnUtils.BuildSpawnCFrames(mineZonePart, itemsToSpawn, existingPositions, {
		MinSpacing = MIN_ITEM_SPACING,
	})

	for _, spawnCFrame in ipairs(spawnCFrames) do
		local mutationName = getMutationForMinePosition(mineZonePart, spawnCFrame.Position)
		local spawnableItems = getSpawnableItemsByRarity(rarity, mutationName)
		if #spawnableItems == 0 then
			warn("[ItemManager] No spawnable items found for rarity:", rarity)
			return
		end

		local randomItemName = spawnableItems[math.random(1, #spawnableItems)]
		local newItem = createWorldItemModel(randomItemName, mutationName, rarity, 1, nil)
		if not newItem then
			continue
		end

		local itemExtents = newItem:GetExtentsSize()
		local distToBottom = newItem:GetPivot().Position.Y - (newItem:GetBoundingBox().Position.Y - (itemExtents.Y / 2))

		newItem:PivotTo(spawnCFrame + Vector3.new(0, distToBottom, 0))
		newItem.Parent = mineZonePart

		setupItemGUI(newItem, 1, 0, false)

		if newItem.PrimaryPart then
			createPickupPrompt(newItem, randomItemName, WORLD_ITEM_PICKUP_DISTANCE)
		end

		spawnedThisPass += 1
		if spawnedThisPass % ITEM_SPAWN_BATCH_SIZE == 0 then
			task.wait(ITEM_SPAWN_BATCH_YIELD)
		end
	end
end

function ItemManager.SpawnWorldItemAtPosition(
	itemName: string,
	mutation: string,
	rarity: string,
	targetPos: Vector3,
	options: {[string]: any}?
): Model?
	local level = if type(options) == "table" and type(options.Level) == "number" then options.Level else 1
	local parentInstance = if type(options) == "table" and typeof(options.Parent) == "Instance" then options.Parent else Workspace
	local extraAttributes = if type(options) == "table" and type(options.ExtraAttributes) == "table" then options.ExtraAttributes else nil
	local originPos = if type(options) == "table" and typeof(options.OriginPos) == "Vector3" then options.OriginPos else nil
	local maxPickupDistance = if type(options) == "table" and type(options.MaxPickupDistance) == "number" then options.MaxPickupDistance else WORLD_ITEM_PICKUP_DISTANCE

	local newItem = createWorldItemModel(itemName, mutation, rarity, level, extraAttributes)
	if not newItem then
		return nil
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

	local finalCFrame = CFrame.new(targetPos.X, floorY + distToBottom, targetPos.Z) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)

	newItem.Parent = parentInstance

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
		end)
	else
		newItem:PivotTo(finalCFrame)
	end

	setupItemGUI(newItem, level, 0, false)

	if newItem.PrimaryPart then
		createPickupPrompt(newItem, itemName, maxPickupDistance)
	end

	local lifetime = getRemainingSessionLifetime() + 0.1
	task.delay(lifetime, function()
		if newItem and newItem.Parent then newItem:Destroy() end
	end)

	return newItem
end

function ItemManager.SpawnDroppedItem(
	itemName: string,
	mutation: string,
	rarity: string,
	targetPos: Vector3,
	originPos: Vector3?,
	options: {[string]: any}?
): Model?
	local spawnOptions = if type(options) == "table" then options else {}
	spawnOptions.OriginPos = originPos
	spawnOptions.MaxPickupDistance = spawnOptions.MaxPickupDistance or WORLD_ITEM_PICKUP_DISTANCE
	return ItemManager.SpawnWorldItemAtPosition(itemName, mutation, rarity, targetPos, spawnOptions)
end

local function ensureSpawnWorker()
	if spawnWorkerRunning or Workspace:GetAttribute("TerrainResetInProgress") == true then
		return
	end

	spawnWorkerRunning = true

	task.spawn(function()
		while #mineSpawnQueue > 0 do
			local mineZonePart = table.remove(mineSpawnQueue, 1)
			if mineZonePart and mineZonePart.Parent and mineZonePart:IsA("BasePart") then
				queuedMineZones[mineZonePart] = nil
				ItemManager.SpawnInMine(mineZonePart)
			end

			task.wait()
		end

		spawnWorkerRunning = false
	end)
end

local function queueMineSpawn(mineZonePart: BasePart?)
	if not mineZonePart or not mineZonePart.Parent then
		return
	end

	if queuedMineZones[mineZonePart] then
		return
	end

	queuedMineZones[mineZonePart] = true
	table.insert(mineSpawnQueue, mineZonePart)
	ensureSpawnWorker()
end

local function queueAllMineSpawns()
	for _, spawner in ipairs(MinesFolder:GetChildren()) do
		if spawner:IsA("BasePart") then
			queueMineSpawn(spawner)
		end
	end
end

local function flushPendingRoundRefill()
	if not pendingRoundRefill then
		return
	end

	if Workspace:GetAttribute("SessionEnded") == true then
		return
	end

	if Workspace:GetAttribute("TerrainResetInProgress") == true then
		return
	end

	pendingRoundRefill = false
	queueAllMineSpawns()
end

function ItemManager.RespawnItem(mineZonePart: BasePart)
	task.delay(RESPAWN_TIME, function()
		if not RunService:IsRunning() then
			return
		end

		if Workspace:GetAttribute("SessionEnded") == true then
			return
		end

		queueMineSpawn(mineZonePart)
	end)
end

function ItemManager.SpawnAllItems()
	queueAllMineSpawns()
end

FinishTime.Event:Connect(function()
	clearSessionWorldItems()
end)

RoundStarted.Event:Connect(function()
	if not RunService:IsRunning() then
		return
	end

	pendingRoundRefill = true
	flushPendingRoundRefill()
end)

Workspace:GetAttributeChangedSignal("TerrainResetInProgress"):Connect(function()
	if Workspace:GetAttribute("TerrainResetInProgress") == false then
		ensureSpawnWorker()
		flushPendingRoundRefill()
	end
end)

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
-- ## INITIAL ROUND FILL ##
-- =========================================================================
task.defer(function()
	if not RunService:IsRunning() then
		return
	end

	if type(Workspace:GetAttribute("SessionRoundId")) == "number" and Workspace:GetAttribute("SessionEnded") ~= true then
		pendingRoundRefill = true
		flushPendingRoundRefill()
	end
end)

validateRebirthRequirementTemplates()

return ItemManager
