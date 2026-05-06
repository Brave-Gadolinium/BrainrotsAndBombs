--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local CandyEventConfiguration = require(ReplicatedStorage.Modules.CandyEventConfiguration)
local Constants = require(ReplicatedStorage.Modules.Constants)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local UpgradesConfigurations = require(ReplicatedStorage.Modules.UpgradesConfigurations)

local BadgeManager = require(ServerScriptService.Modules.BadgeManager)
local GlobalEventLightingService = require(ServerScriptService.Modules.GlobalEventLightingService)
local MineSpawnUtils = require(ServerScriptService.Modules.MineSpawnUtils)
local TerrainGeneratorManager = require(ServerScriptService.Modules.TerrainGeneratorManager)

type CandyReward = CandyEventConfiguration.CandyReward
type CandyEventState = CandyEventConfiguration.CandyEventState

local CandyEventService = {}

local MinesFolder = Workspace:WaitForChild("Mines")
local RandomObject = Random.new()
local ROTATE_TAG = "Rotate"
local CANDY_SKYBOX_NAME = "SkyCandy"
local LIGHTING_OWNER_KEY = "CandyEvent"
local LIGHTING_PRIORITY = 100
local SCHEDULE_STARTED_ATTRIBUTE = "TimedGlobalEventScheduleStartedAt"

local PlayerController
local ItemManager

local candyEventRemotes: Folder
local getStateRemote: RemoteFunction
local spinRemote: RemoteFunction
local stateUpdatedRemote: RemoteEvent

local finishEvent: BindableEvent
local roundStartedEvent: BindableEvent

local currentState: CandyEventState
local scheduleStartedAt = 0
local pendingRoundSpawn = false
local spawnedCandies: {Model} = {}
local spawnedCandyZones: {[string]: boolean} = {}
local spinRequestsInFlight: {[number]: boolean} = {}
local started = false
local cachedCandyTemplate: Model? = nil
local forcedState: {
	Mode: "active" | "inactive",
	EndsAt: number,
}? = nil

local function ensureScheduleStartedAt(): number
	local existingValue = Workspace:GetAttribute(SCHEDULE_STARTED_ATTRIBUTE)
	if type(existingValue) == "number" and existingValue > 0 then
		scheduleStartedAt = existingValue
		return scheduleStartedAt
	end

	scheduleStartedAt = Workspace:GetServerTimeNow()
	Workspace:SetAttribute(SCHEDULE_STARTED_ATTRIBUTE, scheduleStartedAt)
	return scheduleStartedAt
end

local function applyCandyEventSkybox(isActive: boolean)
	if isActive then
		GlobalEventLightingService:SetEffect(LIGHTING_OWNER_KEY, {
			Priority = LIGHTING_PRIORITY,
			SkyboxName = CANDY_SKYBOX_NAME,
		})
	else
		GlobalEventLightingService:ClearEffect(LIGHTING_OWNER_KEY)
	end
end

local function syncCandyWorkspaceAttributes()
	Workspace:SetAttribute("CandyEventActive", currentState.isActive)
	Workspace:SetAttribute("CandyEventEndsAt", currentState.endsAt)
end

local function ensureTimerFolder(): Folder
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

	return timerFolder
end

local function ensureBindableEvent(name: string): BindableEvent
	local timerFolder = ensureTimerFolder()
	local eventInstance = timerFolder:FindFirstChild(name)
	if not eventInstance then
		eventInstance = Instance.new("BindableEvent")
		eventInstance.Name = name
		eventInstance.Parent = timerFolder
	end

	return eventInstance :: BindableEvent
end

local function getNotificationRemote(): RemoteEvent?
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local remote = eventsFolder and eventsFolder:FindFirstChild("ShowNotification")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function getCandyPopUpRemote(): RemoteEvent?
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local remote = eventsFolder and eventsFolder:FindFirstChild("ShowCandyPopUp")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function showNotification(player: Player, message: string, messageType: string)
	local remote = getNotificationRemote()
	if remote then
		remote:FireClient(player, message, messageType)
	end
end

local function showCandyPickupPopUp(player: Player, amount: number)
	local remote = getCandyPopUpRemote()
	if remote then
		remote:FireClient(player, math.max(1, math.floor(tonumber(amount) or 1)))
	end
end

local function getSearchRootByName(rootName: string): Instance?
	if rootName == "ReplicatedStorage" then
		return ReplicatedStorage
	end
	if rootName == "Workspace" then
		return Workspace
	end

	return nil
end

local function resolveCandyTemplate(): Model?
	if cachedCandyTemplate and cachedCandyTemplate.Parent then
		return cachedCandyTemplate
	end

	for _, rootName in ipairs(CandyEventConfiguration.TemplateSearchRoots or {}) do
		local searchRoot = getSearchRootByName(rootName)
		if searchRoot then
			for _, templateName in ipairs(CandyEventConfiguration.TemplateSearchNames or {}) do
				local candidate = searchRoot:FindFirstChild(templateName, true)
				if candidate and candidate:IsA("Model") then
					cachedCandyTemplate = candidate
					return candidate
				end
			end
		end
	end

	return nil
end

local function createFallbackCandyVisual(): Model
	local visualModel = Instance.new("Model")
	visualModel.Name = "Candy"

	local candyPart = Instance.new("Part")
	candyPart.Name = "Candy"
	candyPart.Shape = Enum.PartType.Ball
	candyPart.Size = Vector3.new(3, 3, 3)
	candyPart.Material = Enum.Material.Neon
	candyPart.Color = Color3.fromRGB(255, 124, 178)
	candyPart.TopSurface = Enum.SurfaceType.Smooth
	candyPart.BottomSurface = Enum.SurfaceType.Smooth
	candyPart.Parent = visualModel

	local accentPart = Instance.new("Part")
	accentPart.Name = "Wrap"
	accentPart.Size = Vector3.new(3.8, 1.2, 1.2)
	accentPart.Material = Enum.Material.Neon
	accentPart.Color = Color3.fromRGB(255, 236, 92)
	accentPart.TopSurface = Enum.SurfaceType.Smooth
	accentPart.BottomSurface = Enum.SurfaceType.Smooth
	accentPart.CFrame = candyPart.CFrame * CFrame.Angles(0, 0, math.rad(90))
	accentPart.Parent = visualModel

	visualModel.PrimaryPart = candyPart
	return visualModel
end

local function buildCandyModel(): Model?
	local template = resolveCandyTemplate()
	local visual = if template then template:Clone() else createFallbackCandyVisual()
	local visualPrimaryPart = visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart", true)
	if not visualPrimaryPart then
		visual:Destroy()
		return nil
	end

	local visualExtents = visual:GetExtentsSize()
	local visualBottomOffset = visual:GetPivot().Position.Y - (visual:GetBoundingBox().Position.Y - (visualExtents.Y * 0.5))

	local wrapper = Instance.new("Model")
	wrapper.Name = "CandyEventCandy"
	wrapper:SetAttribute("IsCandyEventCandy", true)
	wrapper:SetAttribute("VisualBottomOffset", visualBottomOffset)

	local rootPart = Instance.new("Part")
	rootPart.Name = "Root"
	rootPart.Size = Vector3.new(
		math.max(3, visualExtents.X * 0.7),
		math.max(3, visualExtents.Y),
		math.max(3, visualExtents.Z * 0.7)
	)
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.CanQuery = false
	rootPart.CanTouch = true
	rootPart.Anchored = true
	rootPart.Massless = true
	rootPart.Parent = wrapper
	wrapper.PrimaryPart = rootPart

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Anchored = false
			descendant.Massless = true

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	visual.Name = "Visual"
	visual.Parent = wrapper
	visual:PivotTo(rootPart.CFrame)

	return wrapper
end

local function removeSpawnedCandy(model: Model)
	for index = #spawnedCandies, 1, -1 do
		if spawnedCandies[index] == model then
			table.remove(spawnedCandies, index)
			break
		end
	end

	if model.Parent then
		model:Destroy()
	end
end

local function clearAllCandies()
	for _, model in ipairs(spawnedCandies) do
		if model and model.Parent then
			model:Destroy()
		end
	end
	table.clear(spawnedCandies)
	table.clear(spawnedCandyZones)

	for _, mineZonePart in ipairs(MinesFolder:GetChildren()) do
		if mineZonePart:IsA("BasePart") then
			for _, child in ipairs(mineZonePart:GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("IsCandyEventCandy") == true then
					child:Destroy()
				end
			end
		end
	end
end

local function hasLiveRound(): boolean
	return type(Workspace:GetAttribute("SessionRoundId")) == "number" and Workspace:GetAttribute("SessionEnded") ~= true
end

local function chooseRewardIndex(): number?
	local totalWeight = CandyEventConfiguration.GetTotalWeight()
	if totalWeight <= 0 then
		return nil
	end

	local roll = RandomObject:NextInteger(1, totalWeight)
	local currentWeight = 0

	for index, reward in ipairs(CandyEventConfiguration.Rewards) do
		currentWeight += math.max(0, tonumber(reward.Weight) or 0)
		if roll <= currentWeight then
			return index
		end
	end

	return nil
end

local function getUpgradeConfigById(upgradeId: string)
	for _, config in ipairs(UpgradesConfigurations.Upgrades) do
		if config.Id == upgradeId then
			return config
		end
	end

	return nil
end

local function grantItemReward(player: Player, itemName: string): boolean
	local itemData = ItemConfigurations.GetItemData(itemName)
	if not itemData then
		return false
	end

	local tool = ItemManager.GiveItemToPlayer(player, itemName, "Normal", itemData.Rarity, 1)
	if not tool then
		return false
	end

	local totalCollected = PlayerController:IncrementBrainrotsCollected(player, 1)
	BadgeManager:EvaluateBrainrotMilestones(player, itemData.Rarity, totalCollected)
	showNotification(player, "You got " .. (itemData.DisplayName or itemName) .. "!", "Success")
	return true
end

local function grantRandomRarityReward(player: Player, rarity: string): boolean
	local itemNames = ItemConfigurations.GetItemsByRarity(rarity)
	if #itemNames == 0 then
		return false
	end

	local itemName = itemNames[RandomObject:NextInteger(1, #itemNames)]
	return grantItemReward(player, itemName)
end

local function grantMoneyReward(player: Player, amount: number): boolean
	if amount <= 0 then
		return false
	end

	PlayerController:AddMoney(player, amount)
	showNotification(player, "You got $" .. NumberFormatter.Format(amount) .. "!", "Success")
	return true
end

local function grantUpgradeReward(player: Player, upgradeId: string, amount: number): boolean
	local config = getUpgradeConfigById(upgradeId)
	if not config or type(config.StatId) ~= "string" or config.StatId == "" then
		return false
	end

	PlayerController:AddUpgradeStat(player, config.StatId, amount)
	showNotification(player, "You got " .. (config.DisplayName or "+1 upgrade") .. "!", "Success")
	return true
end

local function applyReward(player: Player, reward: CandyReward): boolean
	if reward.Type == "Item" and type(reward.ItemName) == "string" then
		return grantItemReward(player, reward.ItemName)
	end

	if reward.Type == "RandomItemByRarity" and type(reward.Rarity) == "string" then
		return grantRandomRarityReward(player, reward.Rarity)
	end

	if reward.Type == "Money" and type(reward.Amount) == "number" then
		return grantMoneyReward(player, reward.Amount)
	end

	if reward.Type == "UpgradeStat" and type(reward.UpgradeId) == "string" then
		return grantUpgradeReward(player, reward.UpgradeId, math.max(1, math.floor(tonumber(reward.Amount) or 1)))
	end

	return false
end

local function getPublicState(nowOverride: number?): CandyEventState
	local serverNow = math.max(0, tonumber(nowOverride) or Workspace:GetServerTimeNow())
	local state = CandyEventConfiguration.GetCurrentState(serverNow, ensureScheduleStartedAt())

	if forcedState and serverNow >= forcedState.EndsAt then
		forcedState = nil
	end

	if forcedState then
		if forcedState.Mode == "active" then
			state.isActive = true
			state.endsAt = forcedState.EndsAt
		else
			state.isActive = false
			state.endsAt = nil
			state.nextStartAt = math.max(state.nextStartAt, forcedState.EndsAt)
		end
	end

	state.serverNow = serverNow
	return state
end

local function statesDiffer(left: CandyEventState, right: CandyEventState): boolean
	if left.isActive ~= right.isActive then
		return true
	end

	if math.abs((left.nextStartAt or 0) - (right.nextStartAt or 0)) >= 1 then
		return true
	end

	local leftEndsAt = left.endsAt or 0
	local rightEndsAt = right.endsAt or 0
	return math.abs(leftEndsAt - rightEndsAt) >= 1
end

local function pushState()
	if stateUpdatedRemote then
		stateUpdatedRemote:FireAllClients(getPublicState())
	end
end

local function attachCandyTouch(model: Model)
	local rootPart = model.PrimaryPart
	if not rootPart then
		return
	end

	local touchLocked = false

	rootPart.Touched:Connect(function(hit)
		if touchLocked or not model.Parent then
			return
		end

		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or not character or player.Character ~= character then
			return
		end

		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end

		if not PlayerController or not PlayerController:GetProfile(player) then
			return
		end

		touchLocked = true
		PlayerController:AddCandies(player, 1)
		showCandyPickupPopUp(player, 1)
		removeSpawnedCandy(model)
	end)
end

local function spawnCandiesForZone(mineZonePart: BasePart)
	if not currentState.isActive or not hasLiveRound() then
		return
	end

	if spawnedCandyZones[mineZonePart.Name] then
		return
	end

	if not TerrainGeneratorManager.IsZoneReady(mineZonePart.Name) then
		return
	end

	local zoneCandyCount = math.max(0, math.floor(tonumber(CandyEventConfiguration.ZoneCandyCounts[mineZonePart.Name]) or 0))
	if zoneCandyCount <= 0 then
		spawnedCandyZones[mineZonePart.Name] = true
		return
	end

	local spawnCFrames = MineSpawnUtils.BuildSpawnCFrames(mineZonePart, zoneCandyCount, nil, {
		MinSpacing = Constants.MIN_ITEM_SPACING,
	})

	for _, spawnCFrame in ipairs(spawnCFrames) do
		local candyModel = buildCandyModel()
		if candyModel then
			local visualBottomOffset = tonumber(candyModel:GetAttribute("VisualBottomOffset")) or 0
			local yawDegrees = tonumber(CandyEventConfiguration.WorldVisualYawDegrees) or 90
			local spawnPivot = (spawnCFrame + Vector3.new(0, visualBottomOffset, 0))
				* CFrame.Angles(0, math.rad(yawDegrees), 0)
			candyModel:PivotTo(spawnPivot)
			candyModel.Parent = mineZonePart
			CollectionService:AddTag(candyModel, ROTATE_TAG)
			table.insert(spawnedCandies, candyModel)
			attachCandyTouch(candyModel)
		end
	end

	spawnedCandyZones[mineZonePart.Name] = true
end

local function spawnPendingCandyZones()
	local waitingForReadyZone = false

	for _, mineZonePart in ipairs(MinesFolder:GetChildren()) do
		if mineZonePart:IsA("BasePart") then
			local zoneCandyCount = math.max(0, math.floor(tonumber(CandyEventConfiguration.ZoneCandyCounts[mineZonePart.Name]) or 0))
			if zoneCandyCount > 0 and not spawnedCandyZones[mineZonePart.Name] then
				if TerrainGeneratorManager.IsZoneReady(mineZonePart.Name) then
					spawnCandiesForZone(mineZonePart)
				else
					waitingForReadyZone = true
				end
			end
		end
	end

	return waitingForReadyZone == false
end

local function beginRoundCandySpawn()
	clearAllCandies()
	pendingRoundSpawn = true
	spawnPendingCandyZones()
end

local function flushPendingRoundSpawn()
	if not pendingRoundSpawn then
		return
	end

	if not currentState.isActive or not hasLiveRound() then
		return
	end

	if Workspace:GetAttribute("TerrainResetInProgress") == true then
		return
	end

	if spawnPendingCandyZones() then
		pendingRoundSpawn = false
	end
end

local function handleRoundStarted()
	if currentState.isActive then
		beginRoundCandySpawn()
		flushPendingRoundSpawn()
	end
end

local function handleRoundFinished()
	pendingRoundSpawn = false
	clearAllCandies()
end

local function refreshState(forcePush: boolean?)
	local nextState = getPublicState()
	local didChange = statesDiffer(currentState, nextState)
	local wasActive = currentState.isActive
	currentState = nextState
	syncCandyWorkspaceAttributes()

	if didChange or forcePush == true then
		applyCandyEventSkybox(currentState.isActive)
	end

	if didChange then
		if currentState.isActive and not wasActive then
			beginRoundCandySpawn()
			flushPendingRoundSpawn()
		elseif not currentState.isActive and wasActive then
			pendingRoundSpawn = false
			clearAllCandies()
		end
	end

	if didChange or forcePush == true then
		pushState()
	end
end

function CandyEventService:GetStateForPlayer(_player: Player)
	return {
		Success = true,
		State = getPublicState(),
	}
end

function CandyEventService:IsActive(): boolean
	return getPublicState().isActive
end

function CandyEventService:HandleSpin(player: Player)
	if spinRequestsInFlight[player.UserId] then
		return {
			Success = false,
			Error = "SpinInProgress",
			Message = CandyEventConfiguration.Text.SpinInProgress,
		}
	end

	if not PlayerController or not PlayerController:GetProfile(player) then
		return {
			Success = false,
			Error = "ProfileNotLoaded",
		}
	end

	local didConsume, usedPaidSpin = PlayerController:ConsumeCandySpinCost(player, CandyEventConfiguration.SpinCost)
	if not didConsume then
		return {
			Success = false,
			Error = "NotEnoughCandies",
			Message = CandyEventConfiguration.Text.NotEnoughCandies,
		}
	end

	local rewardIndex = chooseRewardIndex()
	local reward = rewardIndex and CandyEventConfiguration.GetRewardByIndex(rewardIndex) or nil
	if not rewardIndex or not reward then
		if usedPaidSpin then
			PlayerController:AddPaidCandySpins(player, 1)
		else
			PlayerController:AddCandies(player, CandyEventConfiguration.SpinCost)
		end

		return {
			Success = false,
			Error = "RewardUnavailable",
		}
	end

	spinRequestsInFlight[player.UserId] = true

	task.delay(CandyEventConfiguration.SpinAnimationSeconds, function()
		spinRequestsInFlight[player.UserId] = nil

		local currentProfile = PlayerController and PlayerController:GetProfile(player)
		if not player.Parent or not currentProfile then
			return
		end

		if not applyReward(player, reward) then
			warn("[CandyEventService] Failed to apply reward", reward.DisplayName)
		end
	end)

	return {
		Success = true,
		Index = rewardIndex,
		UsedPaidSpin = usedPaidSpin,
	}
end

function CandyEventService:ForceStartForTesting(): (boolean, string)
	local now = Workspace:GetServerTimeNow()
	forcedState = {
		Mode = "active",
		EndsAt = now + CandyEventConfiguration.ActiveDurationSeconds,
	}

	refreshState(true)
	return true, "Forced candy event active."
end

function CandyEventService:ForceStopForTesting(): (boolean, string)
	local now = Workspace:GetServerTimeNow()
	local scheduleState = CandyEventConfiguration.GetCurrentState(now, ensureScheduleStartedAt())
	forcedState = {
		Mode = "inactive",
		EndsAt = math.max(scheduleState.nextStartAt, now + 1),
	}

	refreshState(true)
	return true, "Forced candy event inactive."
end

function CandyEventService:Init(controllers)
	PlayerController = controllers.PlayerController
	ItemManager = require(ServerScriptService.Modules.ItemManager)

	candyEventRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CandyEvent")
	getStateRemote = candyEventRemotes:WaitForChild("GetState") :: RemoteFunction
	spinRemote = candyEventRemotes:WaitForChild("Spin") :: RemoteFunction
	stateUpdatedRemote = candyEventRemotes:WaitForChild("StateUpdated") :: RemoteEvent

	getStateRemote.OnServerInvoke = function(player)
		return self:GetStateForPlayer(player)
	end

	spinRemote.OnServerInvoke = function(player)
		return self:HandleSpin(player)
	end

	finishEvent = ensureBindableEvent("FinishTime")
	roundStartedEvent = ensureBindableEvent("RoundStarted")

	roundStartedEvent.Event:Connect(handleRoundStarted)
	finishEvent.Event:Connect(handleRoundFinished)

	Workspace:GetAttributeChangedSignal("TerrainResetInProgress"):Connect(function()
		if Workspace:GetAttribute("TerrainResetInProgress") == false then
			flushPendingRoundSpawn()
		end
	end)

	TerrainGeneratorManager.ZoneReadyChanged:Connect(function()
		flushPendingRoundSpawn()
	end)

	Players.PlayerRemoving:Connect(function(player)
		spinRequestsInFlight[player.UserId] = nil
	end)

	currentState = getPublicState()
	syncCandyWorkspaceAttributes()
end

function CandyEventService:Start()
	if started then
		return
	end

	started = true
	currentState = getPublicState()
	syncCandyWorkspaceAttributes()
	applyCandyEventSkybox(currentState.isActive)

	if currentState.isActive then
		beginRoundCandySpawn()
		flushPendingRoundSpawn()
	end

	task.spawn(function()
		while true do
			refreshState(false)
			task.wait(1)
		end
	end)
end

currentState = CandyEventConfiguration.GetCurrentState(Workspace:GetServerTimeNow(), Workspace:GetServerTimeNow())

return CandyEventService
