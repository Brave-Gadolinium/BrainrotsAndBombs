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
local TerrainGeneratorManager = require(ServerScriptService.Modules.TerrainGeneratorManager)

-- [ LAZY DEPENDENCIES ]
local CarrySystem 
local onItemPickedUp: (player: Player, itemModel: Model) -> ()
local isInsideAnyZone: (Vector3) -> boolean

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
local DEBUG_BRAINROT_TRACE = false
local FTUE_TOOL_PROTECTION_DURATION = 60
local MAX_FTUE_TOOL_RESTORE_ATTEMPTS = 12
type FtueProtectedToolState = {
	Player: Player,
	ExpiresAt: number,
	ShouldReequip: boolean,
	Destroying: boolean,
	RestoreQueued: boolean,
	RestoreAttempts: number,
}
local protectedFtueTools: {[Tool]: FtueProtectedToolState} = {}

local function summarizeTool(tool: Tool): string
	local originalName = tool:GetAttribute("OriginalName")
	local mutation = tool:GetAttribute("Mutation")
	local rarity = tool:GetAttribute("Rarity")
	local level = tool:GetAttribute("Level")
	local isLuckyBlock = tool:GetAttribute("IsLuckyBlock") == true
	local toolKind = if isLuckyBlock then "LuckyBlock" elseif mutation ~= nil then "Brainrot" else "Tool"
	return ("%s{name=%s,orig=%s,mut=%s,rar=%s,lvl=%s,parent=%s}"):format(
		toolKind,
		tostring(tool.Name),
		tostring(originalName),
		tostring(mutation),
		tostring(rarity),
		tostring(level),
		tostring(tool.Parent and tool.Parent.Name or "nil")
	)
end

local function summarizeToolContainer(container: Instance?): string
	if not container then
		return "[]"
	end

	local entries = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and (child:GetAttribute("OriginalName") ~= nil or child:GetAttribute("IsLuckyBlock") == true) then
			table.insert(entries, summarizeTool(child))
		end
	end

	table.sort(entries)
	return "[" .. table.concat(entries, ", ") .. "]"
end

local function summarizeWorldItem(itemModel: Model?): string
	if not itemModel then
		return "nil"
	end

	return ("WorldItem{name=%s,orig=%s,mut=%s,rar=%s,lvl=%s,parent=%s}"):format(
		tostring(itemModel.Name),
		tostring(itemModel:GetAttribute("OriginalName")),
		tostring(itemModel:GetAttribute("Mutation")),
		tostring(itemModel:GetAttribute("Rarity")),
		tostring(itemModel:GetAttribute("Level")),
		tostring(itemModel.Parent and itemModel.Parent:GetFullName() or "nil")
	)
end

local function logItemTrace(player: Player?, message: string)
	if not DEBUG_BRAINROT_TRACE then
		return
	end

	local backpack = if player then player:FindFirstChild("Backpack") else nil
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local inZone = root and root:IsA("BasePart") and isInsideAnyZone(root.Position) or false
	print(("[BrainrotTrace][ItemManager][%s][step=%s][inZone=%s][server=%.3f] %s | char=%s | backpack=%s"):format(
		tostring(player and player.Name or "nil"),
		tostring(player and player:GetAttribute("OnboardingStep") or nil),
		tostring(inZone),
		Workspace:GetServerTimeNow(),
		message,
		summarizeToolContainer(player and player.Character or nil),
		summarizeToolContainer(backpack)
	))
end

local function shouldTraceCriticalTutorialWindow(player: Player?): boolean
	if not player then
		return false
	end

	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep == 4 or onboardingStep == 5
end

local function logCriticalItemTrace(player: Player?, message: string)
	if not DEBUG_BRAINROT_TRACE or not shouldTraceCriticalTutorialWindow(player) then
		return
	end

	print(("[BrainrotTrace][ItemManager][%s][step=%s][server=%.3f] %s"):format(
		tostring(player and player.Name or "nil"),
		tostring(player and player:GetAttribute("OnboardingStep") or nil),
		Workspace:GetServerTimeNow(),
		message
	))
end

local function summarizeTraceInstance(instance: Instance?): string
	if not instance then
		return "nil"
	end

	if instance:IsA("Tool") then
		return summarizeTool(instance)
	end

	if instance:IsA("Model") then
		return summarizeWorldItem(instance)
	end

	return ("%s{name=%s,parent=%s}"):format(
		instance.ClassName,
		tostring(instance.Name),
		tostring(instance.Parent and instance.Parent.Name or "nil")
	)
end

local function traceDestroyCall(label: string, instance: Instance?)
	if not DEBUG_BRAINROT_TRACE or not instance then
		return
	end

	print(("[DESTROY CALL][ItemManager][%s] %s"):format(label, summarizeTraceInstance(instance)))
	warn(debug.traceback())
end

local function isFtueProtectableTool(tool: Tool): boolean
	if tool:GetAttribute("IsTemporary") == true then
		return false
	end

	local mutation = tool:GetAttribute("Mutation")
	local originalName = tool:GetAttribute("OriginalName")
	return type(mutation) == "string"
		and mutation ~= ""
		and type(originalName) == "string"
		and originalName ~= ""
end

local function discardFtueToolProtection(tool: Tool)
	protectedFtueTools[tool] = nil
end

local function shouldMaintainFtueToolForPlayer(player: Player): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep == 4 or onboardingStep == 5
end

local function queueFtueToolRestore(tool: Tool)
	local state = protectedFtueTools[tool]
	if not state or state.RestoreQueued or state.Destroying then
		return
	end

	state.RestoreQueued = true
	task.defer(function()
		local currentState = protectedFtueTools[tool]
		if currentState ~= state then
			return
		end

		state.RestoreQueued = false

		local player = state.Player
		if not player.Parent then
			discardFtueToolProtection(tool)
			return
		end

		if state.Destroying or tool.Parent ~= nil then
			return
		end

		if Workspace:GetServerTimeNow() > state.ExpiresAt then
			discardFtueToolProtection(tool)
			return
		end

		if not shouldMaintainFtueToolForPlayer(player) then
			discardFtueToolProtection(tool)
			return
		end

		if state.RestoreAttempts >= MAX_FTUE_TOOL_RESTORE_ATTEMPTS then
			discardFtueToolProtection(tool)
			return
		end

		local backpack = player:FindFirstChild("Backpack")
		if not backpack then
			return
		end

		local restored = pcall(function()
			tool.Parent = backpack
		end)
		if not restored or tool.Parent ~= backpack then
			state.RestoreAttempts += 1
			return
		end

		state.RestoreAttempts += 1

		if state.ShouldReequip and (tonumber(player:GetAttribute("OnboardingStep")) or 0) == 5 then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				task.defer(function()
					if protectedFtueTools[tool] ~= state then
						return
					end
					if tool.Parent == backpack and humanoid.Parent then
						humanoid:EquipTool(tool)
					end
				end)
			end
		end
	end)
end

local function attachToolLifetimeTrace(player: Player, tool: Tool)
	tool.Destroying:Connect(function()
		local state = protectedFtueTools[tool]
		if state then
			state.Destroying = true
		end
		discardFtueToolProtection(tool)
	end)

	tool:GetPropertyChangedSignal("Parent"):Connect(function()
		if tool.Parent == nil then
			queueFtueToolRestore(tool)
		end
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			queueFtueToolRestore(tool)
		end
	end)
end

function ItemManager.ProtectFtuePlacementTool(player: Player, tool: Tool, shouldReequip: boolean?)
	if not player or not tool or not isFtueProtectableTool(tool) then
		return
	end

	local state: FtueProtectedToolState = {
		Player = player,
		ExpiresAt = Workspace:GetServerTimeNow() + FTUE_TOOL_PROTECTION_DURATION,
		ShouldReequip = shouldReequip ~= false,
		Destroying = false,
		RestoreQueued = false,
		RestoreAttempts = 0,
	}
	protectedFtueTools[tool] = state

	task.delay(FTUE_TOOL_PROTECTION_DURATION + 1, function()
		local currentState = protectedFtueTools[tool]
		if currentState == state and Workspace:GetServerTimeNow() >= state.ExpiresAt then
			discardFtueToolProtection(tool)
		end
	end)
end

function ItemManager.SuppressFtueToolProtection(tool: Tool?)
	if not tool then
		return
	end

	local state = protectedFtueTools[tool]
	if state then
		state.Destroying = true
	end
	discardFtueToolProtection(tool)
end

type MineSpawnJob = {
	Key: string,
	Zone: BasePart,
	Mode: string,
	RequestedCount: number?,
	MinDepthRatio: number?,
	MaxDepthRatio: number?,
	OnCompleted: ((BasePart, number) -> ())?,
}

local queuedSpawnJobKeys: {[string]: boolean} = {}
local mineSpawnQueue: {MineSpawnJob} = {}
local spawnWorkerRunning = false
local pendingRoundRefill = false
local started = false
local startupFinalized = false
local startupSeededZones: {[string]: boolean} = {}
local startupAllZonesReadyQueued = false
local startupFinalReconcileJobsRemaining = 0
local STARTUP_ZONE_ORDER = if type(Constants.MINE_STARTUP_ZONE_ORDER) == "table"
	then Constants.MINE_STARTUP_ZONE_ORDER
	else {"Zone1", "Zone2", "Zone3", "Zone4", "Zone5"}
local STARTUP_INITIAL_SEED_RATIO = math.max(0, tonumber(Constants.MINE_STARTUP_INITIAL_SEED_RATIO) or 0.15)
local STARTUP_INITIAL_SEED_MINIMUM = math.max(1, math.floor(tonumber(Constants.MINE_STARTUP_INITIAL_SEED_MINIMUM) or 12))
local STARTUP_BACKFILL_CHUNK_RATIO = math.max(0, tonumber(Constants.MINE_STARTUP_BACKFILL_CHUNK_RATIO) or 0.05)
local STARTUP_BACKFILL_MINIMUM = 6
local STARTUP_DEPTH_BANDS = if type(Constants.MINE_STARTUP_DEPTH_BANDS) == "table"
	then Constants.MINE_STARTUP_DEPTH_BANDS
	else {
		{ MinDepthRatio = 0.00, MaxDepthRatio = 0.35 },
		{ MinDepthRatio = 0.35, MaxDepthRatio = 0.65 },
		{ MinDepthRatio = 0.65, MaxDepthRatio = 1.00 },
	}

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
function isInsideAnyZone(position: Vector3): boolean
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
	if not itemName then
		logItemTrace(player, "GiveItemToPlayer aborted missingItemName")
		return nil
	end

	local itemConf = ItemConfigurations.GetItemData(itemName)
	if isTemporary then
		logItemTrace(player, ("GiveItemToPlayer skipped temporary name=%s"):format(tostring(itemName)))
		return nil
	end

	logItemTrace(player, ("GiveItemToPlayer begin name=%s mut=%s rar=%s lvl=%s extra=%s"):format(
		tostring(itemName),
		tostring(mutation),
		tostring(rarity),
		tostring(level or 1),
		tostring(type(extraAttributes) == "table")
	))

	local model = createItemModel(itemName, mutation, rarity)
	if not model then
		logItemTrace(player, ("GiveItemToPlayer failed createItemModel name=%s"):format(tostring(itemName)))
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

	local strippedScripts = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			strippedScripts += 1
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

	newTool.Parent = player:WaitForChild("Backpack")
	attachToolLifetimeTrace(player, newTool)
	logCriticalItemTrace(player, ("GiveItemToPlayer success tool=%s strippedScripts=%d"):format(
		summarizeTool(newTool),
		strippedScripts
	))
	logItemTrace(player, ("GiveItemToPlayer success strippedScripts=%d tool=%s"):format(
		strippedScripts,
		summarizeTool(newTool)
	))
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
		traceDestroyCall("GiveLuckyBlockToPlayer.invalidRoot.newTool", newTool)
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
	attachToolLifetimeTrace(player, newTool)
	return newTool
end

-- [ PICKUP LOGIC ]
function onItemPickedUp(player: Player, itemModel: Model)
	if not CarrySystem then CarrySystem = require(ServerScriptService.Modules.CarrySystem) end
	if not itemModel or not itemModel.Parent then
		logItemTrace(player, "onItemPickedUp ignored missingItemModel")
		return
	end

	local spawnerPart = itemModel.Parent 

	local name = itemModel:GetAttribute("OriginalName")
	local mutation = itemModel:GetAttribute("Mutation")
	local rarity = itemModel:GetAttribute("Rarity")
	local level = itemModel:GetAttribute("Level") or 1 
	local eventAttributes = extractEventAttributes(itemModel)

	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	logItemTrace(player, ("onItemPickedUp begin item=%s"):format(summarizeWorldItem(itemModel)))

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
				logItemTrace(player, ("onItemPickedUp carryResult success=%s item=%s/%s/%s"):format(
					tostring(success),
					tostring(name),
					tostring(mutation),
					tostring(rarity)
				))
				if success then pickedUp = true end
			else
				local Events = ReplicatedStorage:FindFirstChild("Events")
				local notif = Events and Events:FindFirstChild("ShowNotification")
				if notif then notif:FireClient(player, "Carry limit reached!", "Error") end
				AnalyticsFunnelsService:LogFailure(player, "carry_limit_reached", {
					zone = "mine",
				})
				logItemTrace(player, ("onItemPickedUp blocked by carry limit item=%s/%s/%s"):format(
					tostring(name),
					tostring(mutation),
					tostring(rarity)
				))
			end
		else
			local newTool = ItemManager.GiveItemToPlayer(player, name, mutation, rarity, level, false, eventAttributes)
			logItemTrace(player, ("onItemPickedUp surfaceGive success=%s tool=%s"):format(
				tostring(newTool ~= nil),
				tostring(newTool and summarizeTool(newTool) or "nil")
			))
			pickedUp = true
		end

		if pickedUp then 
			TutorialService:HandleBrainrotPickedUp(player, inZone)
			AnalyticsFunnelsService:HandleMineBrainrotPickedUp(player)
			logItemTrace(player, ("onItemPickedUp destroying world item=%s"):format(summarizeWorldItem(itemModel)))
			traceDestroyCall("onItemPickedUp.worldItem", itemModel)
			itemModel:Destroy() 

			-- ## FIXED: Queue a replacement immediately when an item is picked up! ##
			if spawnerPart and spawnerPart:IsA("BasePart") and not eventAttributes then
				ItemManager.RespawnItem(spawnerPart)
			end
			logItemTrace(player, "onItemPickedUp complete")
		end
	else
		logItemTrace(player, ("onItemPickedUp aborted invalidData name=%s mut=%s rar=%s hasRoot=%s"):format(
			tostring(name),
			tostring(mutation),
			tostring(rarity),
			tostring(rootPart ~= nil)
		))
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

local function countMineItems(mineZonePart: BasePart): (number, {Vector3})
	local currentItems = 0
	local existingPositions = {}

	for _, child in ipairs(mineZonePart:GetChildren()) do
		if child.Name == "SpawnedItem" and child:IsA("Model") then
			currentItems += 1
			table.insert(existingPositions, child:GetPivot().Position)
		end
	end

	return currentItems, existingPositions
end

function ItemManager.SpawnInMine(mineZonePart: BasePart, options: {[string]: any}?)
	if not mineZonePart or not mineZonePart.Parent then
		return 0
	end

	local currentItems, existingPositions = countMineItems(mineZonePart)
	local targetItemCount = getTargetItemCountForMine(mineZonePart)
	local remainingCapacity = math.max(0, targetItemCount - currentItems)
	local explicitCount = if type(options) == "table" and type(options.RequestedCount) == "number"
		then math.max(0, math.floor(options.RequestedCount))
		else nil
	local itemsToSpawn = if explicitCount ~= nil
		then math.min(explicitCount, remainingCapacity)
		else remainingCapacity

	if itemsToSpawn <= 0 then
		return 0
	end

	local minDepthRatio = if type(options) == "table" and type(options.MinDepthRatio) == "number"
		then math.clamp(options.MinDepthRatio, 0, 1)
		else 0
	local maxDepthRatio = if type(options) == "table" and type(options.MaxDepthRatio) == "number"
		then math.clamp(options.MaxDepthRatio, minDepthRatio, 1)
		else 1
	local tier = mineZonePart.Name
	local rarity = getRarityFromTier(tier)
	local spawnedThisPass = 0

	local spawnCFrames = MineSpawnUtils.BuildSpawnCFrames(mineZonePart, itemsToSpawn, existingPositions, {
		MinSpacing = MIN_ITEM_SPACING,
		MinDepthRatio = minDepthRatio,
		MaxDepthRatio = maxDepthRatio,
	})

	for _, spawnCFrame in ipairs(spawnCFrames) do
		local mutationName = getMutationForMinePosition(mineZonePart, spawnCFrame.Position)
		local spawnableItems = getSpawnableItemsByRarity(rarity, mutationName)
		if #spawnableItems == 0 then
			warn("[ItemManager] No spawnable items found for rarity:", rarity)
			break
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

	return spawnedThisPass
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

local ensureSpawnWorker: () -> ()

local function getZoneOrderRank(zoneName: string): number
	for index, orderedZoneName in ipairs(STARTUP_ZONE_ORDER) do
		if orderedZoneName == zoneName then
			return index
		end
	end

	return math.huge
end

local function getSpawnJobPriority(mode: string): number
	if mode == "seed" then
		return 1
	end

	if mode == "backfill" then
		return 2
	end

	return 3
end

local function insertSpawnJobSorted(spawnJob: MineSpawnJob)
	local jobPriority = getSpawnJobPriority(spawnJob.Mode)
	local jobZoneRank = getZoneOrderRank(spawnJob.Zone.Name)

	for index, queuedJob in ipairs(mineSpawnQueue) do
		local queuedPriority = getSpawnJobPriority(queuedJob.Mode)
		local queuedZoneRank = getZoneOrderRank(queuedJob.Zone.Name)
		local shouldInsertFirst = jobPriority < queuedPriority
			or (jobPriority == queuedPriority and jobZoneRank < queuedZoneRank)
			or (jobPriority == queuedPriority and jobZoneRank == queuedZoneRank and spawnJob.Key < queuedJob.Key)

		if shouldInsertFirst then
			table.insert(mineSpawnQueue, index, spawnJob)
			return
		end
	end

	table.insert(mineSpawnQueue, spawnJob)
end

local function queueSpawnJob(spawnJob: MineSpawnJob): boolean
	if not spawnJob.Zone or not spawnJob.Zone.Parent then
		return false
	end

	if queuedSpawnJobKeys[spawnJob.Key] then
		return false
	end

	queuedSpawnJobKeys[spawnJob.Key] = true
	insertSpawnJobSorted(spawnJob)
	ensureSpawnWorker()
	return true
end

function ensureSpawnWorker()
	if spawnWorkerRunning or Workspace:GetAttribute("TerrainResetInProgress") == true then
		return
	end

	spawnWorkerRunning = true

	task.spawn(function()
		while #mineSpawnQueue > 0 do
			local spawnJob = table.remove(mineSpawnQueue, 1)
			if spawnJob then
				queuedSpawnJobKeys[spawnJob.Key] = nil
			end

			if spawnJob and spawnJob.Zone and spawnJob.Zone.Parent and spawnJob.Zone:IsA("BasePart") then
				local spawnedCount = 0
				if TerrainGeneratorManager.IsZoneReady(spawnJob.Zone.Name) then
					spawnedCount = ItemManager.SpawnInMine(spawnJob.Zone, {
						RequestedCount = spawnJob.RequestedCount,
						MinDepthRatio = spawnJob.MinDepthRatio,
						MaxDepthRatio = spawnJob.MaxDepthRatio,
					})
				end

				if spawnJob.OnCompleted then
					spawnJob.OnCompleted(spawnJob.Zone, spawnedCount)
				end
			end

			task.wait()
		end

		spawnWorkerRunning = false

		if #mineSpawnQueue > 0 and Workspace:GetAttribute("TerrainResetInProgress") ~= true then
			ensureSpawnWorker()
		end
	end)
end

local function getOrderedMineZoneParts(): {BasePart}
	local orderedParts = {}
	local seenNames: {[string]: boolean} = {}

	for _, zoneName in ipairs(STARTUP_ZONE_ORDER) do
		local zonePart = MinesFolder:FindFirstChild(zoneName)
		if zonePart and zonePart:IsA("BasePart") then
			seenNames[zoneName] = true
			table.insert(orderedParts, zonePart)
		end
	end

	local extraParts = {}
	for _, child in ipairs(MinesFolder:GetChildren()) do
		if child:IsA("BasePart") and not seenNames[child.Name] then
			table.insert(extraParts, child)
		end
	end

	table.sort(extraParts, function(left, right)
		return left.Name < right.Name
	end)

	for _, child in ipairs(extraParts) do
		table.insert(orderedParts, child)
	end

	return orderedParts
end

local function queueZoneReconcile(mineZonePart: BasePart, keySuffix: string?, onCompleted: ((BasePart, number) -> ())?): boolean
	local key = string.format("reconcile:%s:%s", mineZonePart.Name, keySuffix or "default")
	return queueSpawnJob({
		Key = key,
		Zone = mineZonePart,
		Mode = "reconcile",
		OnCompleted = onCompleted,
	})
end

local function queueAllMineSpawns()
	for _, mineZonePart in ipairs(getOrderedMineZoneParts()) do
		if TerrainGeneratorManager.IsZoneReady(mineZonePart.Name) then
			queueZoneReconcile(mineZonePart, "round", nil)
		end
	end
end

local function maybeFinalizeStartup()
	if startupFinalized or not startupAllZonesReadyQueued then
		return
	end

	if startupFinalReconcileJobsRemaining > 0 then
		return
	end

	startupFinalized = true
end

local function maybeQueueStartupFinalReconcile()
	if startupFinalized or startupAllZonesReadyQueued then
		return
	end

	local orderedZoneParts = getOrderedMineZoneParts()
	if #orderedZoneParts == 0 then
		startupFinalized = true
		return
	end

	for _, mineZonePart in ipairs(orderedZoneParts) do
		if not TerrainGeneratorManager.IsZoneReady(mineZonePart.Name) then
			return
		end
	end

	startupAllZonesReadyQueued = true

	for _, mineZonePart in ipairs(orderedZoneParts) do
		local queued = queueZoneReconcile(mineZonePart, "startup-final", function()
			startupFinalReconcileJobsRemaining = math.max(0, startupFinalReconcileJobsRemaining - 1)
			maybeFinalizeStartup()
		end)

		if queued then
			startupFinalReconcileJobsRemaining += 1
		end
	end

	maybeFinalizeStartup()
end

local function queueStartupBackfill(mineZonePart: BasePart)
	local targetItemCount = getTargetItemCountForMine(mineZonePart)
	local requestedCount = math.max(STARTUP_BACKFILL_MINIMUM, math.ceil(targetItemCount * STARTUP_BACKFILL_CHUNK_RATIO))

	for bandIndex, band in ipairs(STARTUP_DEPTH_BANDS) do
		local minDepthRatio = math.clamp(tonumber((band :: any).MinDepthRatio) or 0, 0, 1)
		local maxDepthRatio = math.clamp(tonumber((band :: any).MaxDepthRatio) or 1, minDepthRatio, 1)
		queueSpawnJob({
			Key = string.format("backfill:%s:%d", mineZonePart.Name, bandIndex),
			Zone = mineZonePart,
			Mode = "backfill",
			RequestedCount = requestedCount,
			MinDepthRatio = minDepthRatio,
			MaxDepthRatio = maxDepthRatio,
		})
	end
end

local function handleStartupSeedCompleted(mineZonePart: BasePart)
	startupSeededZones[mineZonePart.Name] = true
	queueStartupBackfill(mineZonePart)

	local playableZoneName = STARTUP_ZONE_ORDER[1]
	if mineZonePart.Name == playableZoneName then
		Workspace:SetAttribute("MineStartupProgress", 1)
		Workspace:SetAttribute("MineStartupPlayable", true)
	end

	maybeQueueStartupFinalReconcile()
end

local function queueStartupSeed(mineZonePart: BasePart)
	if startupSeededZones[mineZonePart.Name] then
		return
	end

	if not TerrainGeneratorManager.IsZoneReady(mineZonePart.Name) then
		return
	end

	local targetItemCount = getTargetItemCountForMine(mineZonePart)
	local requestedCount = math.min(
		targetItemCount,
		math.max(STARTUP_INITIAL_SEED_MINIMUM, math.ceil(targetItemCount * STARTUP_INITIAL_SEED_RATIO))
	)

	queueSpawnJob({
		Key = string.format("seed:%s", mineZonePart.Name),
		Zone = mineZonePart,
		Mode = "seed",
		RequestedCount = requestedCount,
		MinDepthRatio = 0,
		MaxDepthRatio = 0.35,
		OnCompleted = function(zonePart)
			handleStartupSeedCompleted(zonePart)
		end,
	})
end

local function bootstrapReadyZones()
	for _, mineZonePart in ipairs(getOrderedMineZoneParts()) do
		if TerrainGeneratorManager.IsZoneReady(mineZonePart.Name) then
			queueStartupSeed(mineZonePart)
		end
	end

	maybeQueueStartupFinalReconcile()
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
	if not startupFinalized then
		bootstrapReadyZones()
		return
	end

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

		queueZoneReconcile(mineZonePart, "respawn", nil)
	end)
end

function ItemManager.SpawnAllItems()
	queueAllMineSpawns()
end


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
function ItemManager:Start()
	if started then
		return
	end

	started = true
	validateRebirthRequirementTemplates()

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

	TerrainGeneratorManager.ZoneReadyChanged:Connect(function(zoneName: string)
		local zonePart = MinesFolder:FindFirstChild(zoneName)
		if zonePart and zonePart:IsA("BasePart") then
			queueStartupSeed(zonePart)
		end

		maybeQueueStartupFinalReconcile()
	end)

	task.spawn(function()
		local _events = ReplicatedStorage:WaitForChild("Events")
	end)

	bootstrapReadyZones()

	if type(Workspace:GetAttribute("SessionRoundId")) == "number" and Workspace:GetAttribute("SessionEnded") ~= true then
		pendingRoundRefill = true
		flushPendingRoundRefill()
	end
end

return ItemManager
