--!strict
-- LOCATION: StarterPlayerScripts/JoinLikeStandController

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)

local localPlayer = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestGroupReward = events:WaitForChild("RequestGroupReward") :: RemoteFunction

local GROUP_ID = ProductConfigurations.Group.Id
local STAND_NAME = "JoinLikeStand"
local MANAGED_PROMPT_NAME = "JoinLikeStandPrompt"
local PROMPT_DISTANCE = 8
local JOIN_ACTION_TEXT = "Join Group"
local CLAIM_ACTION_TEXT = "Claim Reward"
local LOADING_ACTION_TEXT = "Loading..."
local DEFAULT_IDLE_ANIMATION_ID = "rbxassetid://117364235771341"
local STAND_TOUCH_COOLDOWN = 2
local rewardClaimedOverride = localPlayer:GetAttribute("GroupRewardClaimed") == true

type AnimationPlaybackController = Humanoid | AnimationController

type PlotRecord = {
	Plot: Model?,
	Stand: Instance?,
	Prompt: ProximityPrompt?,
	PromptConnection: RBXScriptConnection?,
	TouchPart: BasePart?,
	TouchConnection: RBXScriptConnection?,
	Connections: {RBXScriptConnection},
	OriginalProperties: {[Instance]: {[string]: any}},
	IdleTrack: AnimationTrack?,
	IsInGroup: boolean,
	Busy: boolean,
	IsHidden: boolean,
	ManagedPromptCreated: boolean,
	UseProximityPrompt: boolean,
	IsStandalone: boolean,
	LastTouchAt: number,
}

local recordsByPlot: {[Model]: PlotRecord} = {}
local standaloneRecord: PlotRecord? = nil

local function isPlotModel(instance: Instance): boolean
	return instance:IsA("Model") and string.match(instance.Name, "^Plot_.+") ~= nil
end

local function findAncestorPlot(instance: Instance?): Model?
	local current = instance
	while current do
		if isPlotModel(current) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function isOwnPlot(plot: Model): boolean
	local ownerUserId = tonumber(plot:GetAttribute("OwnerUserId"))
	if ownerUserId and ownerUserId > 0 then
		return ownerUserId == localPlayer.UserId
	end

	return plot.Name == ("Plot_" .. localPlayer.Name)
end

local function getRewardDisplayName(): string
	local rewardConfig = ProductConfigurations.Group.Reward
	local itemData = ItemConfigurations.GetItemData(rewardConfig.Name)
	return if itemData and type(itemData.DisplayName) == "string" and itemData.DisplayName ~= "" then itemData.DisplayName else rewardConfig.Name
end

local function getRewardObjectText(): string
	return getRewardDisplayName()
end

local function isRewardClaimed(): boolean
	return rewardClaimedOverride or localPlayer:GetAttribute("GroupRewardClaimed") == true
end

local function isRewardStateLoaded(): boolean
	return rewardClaimedOverride or localPlayer:GetAttribute("GroupRewardClaimed") ~= nil
end

local function queryGroupMembership(): boolean
	local success, isInGroup = pcall(function()
		return localPlayer:IsInGroup(GROUP_ID)
	end)

	if not success then
		warn("[JoinLikeStandController] Failed to query group membership for", GROUP_ID)
		return false
	end

	return isInGroup == true
end

local function createRecord(plot: Model?, stand: Instance?, isStandalone: boolean): PlotRecord
	return {
		Plot = plot,
		Stand = stand,
		Prompt = nil,
		PromptConnection = nil,
		TouchPart = nil,
		TouchConnection = nil,
		Connections = {},
		OriginalProperties = {},
		IdleTrack = nil,
		IsInGroup = false,
		Busy = false,
		IsHidden = false,
		ManagedPromptCreated = false,
		UseProximityPrompt = not isStandalone,
		IsStandalone = isStandalone,
		LastTouchAt = 0,
	}
end

local function getRecord(plot: Model): PlotRecord
	local existing = recordsByPlot[plot]
	if existing then
		return existing
	end

	local newRecord = createRecord(plot, nil, false)
	recordsByPlot[plot] = newRecord
	return newRecord
end

local function disconnectRecord(record: PlotRecord)
	if record.PromptConnection then
		record.PromptConnection:Disconnect()
		record.PromptConnection = nil
	end

	if record.TouchConnection then
		record.TouchConnection:Disconnect()
		record.TouchConnection = nil
	end
	record.TouchPart = nil

	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end

	table.clear(record.Connections)
end

local function stopIdleTrack(record: PlotRecord)
	local idleTrack = record.IdleTrack
	if not idleTrack then
		return
	end

	record.IdleTrack = nil

	pcall(function()
		idleTrack:Stop(0)
		idleTrack:Destroy()
	end)
end

local function cleanupPlot(plot: Model)
	local record = recordsByPlot[plot]
	if not record then
		return
	end

	stopIdleTrack(record)
	disconnectRecord(record)

	if record.ManagedPromptCreated and record.Prompt and record.Prompt.Parent then
		record.Prompt:Destroy()
	end

	recordsByPlot[plot] = nil
end

local function ensureOriginalProperty(record: PlotRecord, instance: Instance, propertyName: string): any
	local propertyBag = record.OriginalProperties[instance]
	if not propertyBag then
		propertyBag = {}
		record.OriginalProperties[instance] = propertyBag
	end

	if propertyBag[propertyName] == nil then
		local dynamicInstance = instance :: any
		propertyBag[propertyName] = dynamicInstance[propertyName]
	end

	return propertyBag[propertyName]
end

local function applyVisibilityToInstance(record: PlotRecord, instance: Instance, isVisible: boolean)
	if instance:IsA("BasePart") then
		local originalLocalTransparency = ensureOriginalProperty(record, instance, "LocalTransparencyModifier")
		local originalCanCollide = ensureOriginalProperty(record, instance, "CanCollide")
		local originalCanTouch = ensureOriginalProperty(record, instance, "CanTouch")
		local originalCanQuery = ensureOriginalProperty(record, instance, "CanQuery")
		local keepHidden = string.lower(instance.Name) == "modelroot"
		local forceTouchEnabled = record.IsStandalone and record.TouchPart == instance and isVisible and not keepHidden

		instance.LocalTransparencyModifier = if isVisible and not keepHidden then originalLocalTransparency else 1
		instance.CanCollide = if isVisible and not keepHidden then originalCanCollide else false
		instance.CanTouch = if forceTouchEnabled then true else (if isVisible and not keepHidden then originalCanTouch else false)
		instance.CanQuery = if isVisible and not keepHidden then originalCanQuery else false
		return
	end

	if instance:IsA("Decal") or instance:IsA("Texture") then
		local originalTransparency = ensureOriginalProperty(record, instance, "Transparency")
		local dynamicInstance = instance :: any
		dynamicInstance.Transparency = if isVisible then originalTransparency else 1
		return
	end

	if instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") then
		local originalEnabled = ensureOriginalProperty(record, instance, "Enabled")
		local instanceToken = string.lower(string.gsub(instance.Name, "[%W_]+", ""))
		local shouldForceInfoVisible = instanceToken == "infounit"
			or string.find(instanceToken, "infounit", 1, true) ~= nil
			or instanceToken == "info"
		instance.Enabled = if isVisible then (if shouldForceInfoVisible then true else originalEnabled) else false
		return
	end

	if instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam") or instance:IsA("Fire")
		or instance:IsA("Smoke") or instance:IsA("Sparkles") or instance:IsA("Highlight") or instance:IsA("ProximityPrompt") then
		local originalEnabled = ensureOriginalProperty(record, instance, "Enabled")
		local dynamicInstance = instance :: any
		dynamicInstance.Enabled = if isVisible then originalEnabled else false
	end
end

local function setStandVisibility(record: PlotRecord, isVisible: boolean)
	local stand = record.Stand
	if not stand then
		return
	end

	record.IsHidden = not isVisible

	applyVisibilityToInstance(record, stand, isVisible)
	for _, descendant in ipairs(stand:GetDescendants()) do
		applyVisibilityToInstance(record, descendant, isVisible)
	end

	if not isVisible then
		stopIdleTrack(record)
	end
end

local function instancePathContainsIdle(instance: Instance, root: Instance): boolean
	local current: Instance? = instance
	while current and current ~= root do
		if string.find(string.lower(current.Name), "idle", 1, true) then
			return true
		end

		current = current.Parent
	end

	return false
end

local function normalizeSearchToken(value: string?): string
	if type(value) ~= "string" then
		return ""
	end

	return string.lower(string.gsub(value, "[%W_]+", ""))
end

local function shouldIgnoreAnimationCandidate(instance: Instance): boolean
	return normalizeSearchToken(instance.Name) == "modelroot"
end

local function isHiddenSupportPart(instance: Instance): boolean
	return instance:IsA("BasePart") and normalizeSearchToken(instance.Name) == "modelroot"
end

local function instanceMatchesRewardModel(instance: Instance): boolean
	local rewardConfig = ProductConfigurations.Group.Reward
	local instanceToken = normalizeSearchToken(instance.Name)
	if instanceToken == "" then
		return false
	end

	local rawRewardToken = normalizeSearchToken(rewardConfig.Name)
	if rawRewardToken ~= "" and (instanceToken == rawRewardToken or string.find(instanceToken, rawRewardToken, 1, true)) then
		return true
	end

	local displayRewardToken = normalizeSearchToken(getRewardDisplayName())
	if displayRewardToken ~= "" and (instanceToken == displayRewardToken or string.find(instanceToken, displayRewardToken, 1, true)) then
		return true
	end

	return false
end

local function isValidAnimation(animation: Animation): boolean
	local animationId = animation.AnimationId
	return type(animationId) == "string" and animationId ~= "" and animationId ~= "rbxassetid://"
end

local function findIdleAnimation(root: Instance): Animation?
	local fallbackAnimation: Animation? = nil

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Animation") and isValidAnimation(descendant) then
			fallbackAnimation = fallbackAnimation or descendant

			if instancePathContainsIdle(descendant, root) then
				return descendant
			end
		end
	end

	return fallbackAnimation
end

local function createFallbackIdleAnimation(): Animation
	local animation = Instance.new("Animation")
	animation.Name = "JoinLikeStandFallbackIdle"
	animation.AnimationId = DEFAULT_IDLE_ANIMATION_ID
	return animation
end

local function findAnimationController(root: Instance): AnimationPlaybackController?
	local humanoid = root:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid and humanoid:IsA("Humanoid") then
		return humanoid
	end

	local animationController = root:FindFirstChildWhichIsA("AnimationController", true)
	if animationController and animationController:IsA("AnimationController") then
		return animationController
	end

	return nil
end

local function getAnimationRootScore(candidate: Instance, root: Instance): number
	if shouldIgnoreAnimationCandidate(candidate) then
		return -1000
	end

	local hasAnimationController = findAnimationController(candidate) ~= nil
	local hasIdleAnimation = findIdleAnimation(candidate) ~= nil
	local score = 0

	if candidate == root then
		score += 1
	end

	if candidate:IsA("Model") and candidate.PrimaryPart then
		score += 2
	end

	if candidate.Parent == root then
		score += 3
	end

	if instanceMatchesRewardModel(candidate) then
		score += 1
	end

	if hasAnimationController then
		score += 20
	end

	if hasIdleAnimation then
		score += 12
	end

	if hasAnimationController and hasIdleAnimation then
		score += 20
	end

	return score
end

local function resolveAnimationRoot(root: Instance): Instance
	local bestCandidate = root
	local bestScore = getAnimationRootScore(root, root)

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Model") then
			local score = getAnimationRootScore(descendant, root)
			if score > bestScore then
				bestCandidate = descendant
				bestScore = score
			end
		end
	end

	return bestCandidate
end

local function getOrCreateAnimator(animationController: AnimationPlaybackController): Animator
	local existingAnimator = animationController:FindFirstChildOfClass("Animator")
	if existingAnimator then
		return existingAnimator
	end

	local createdAnimator = Instance.new("Animator")
	createdAnimator.Parent = animationController
	return createdAnimator
end

local function findPlayingTrackByAnimationId(animator: Animator, animationId: string): AnimationTrack?
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local trackAnimation = track.Animation
		if trackAnimation and trackAnimation.AnimationId == animationId then
			return track
		end
	end

	return nil
end

local function hasAnyPlayingTrack(animator: Animator): boolean
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track.IsPlaying then
			return true
		end
	end

	return false
end

local function ensureIdleAnimationPlaying(record: PlotRecord)
	local stand = record.Stand
	if not stand or record.IsHidden then
		return
	end

	if record.IdleTrack and record.IdleTrack.IsPlaying then
		return
	end

	local animationRoot = resolveAnimationRoot(stand)
	local animationController = findAnimationController(animationRoot)
	if not animationController then
		warn("[JoinLikeStandController] No animation controller found for", animationRoot:GetFullName())
		return
	end

	local animator = getOrCreateAnimator(animationController)
	local idleAnimation = findIdleAnimation(animationRoot)
	if not idleAnimation then
		if hasAnyPlayingTrack(animator) then
			return
		end

		idleAnimation = createFallbackIdleAnimation()
	end

	local animationId = idleAnimation.AnimationId
	local existingTrack = findPlayingTrackByAnimationId(animator, animationId)
	if existingTrack then
		record.IdleTrack = existingTrack
		return
	end

	stopIdleTrack(record)

	local success, trackOrError = pcall(function()
		local track = animator:LoadAnimation(idleAnimation)
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play(0.1)
		return track
	end)

	if not success then
		warn("[JoinLikeStandController] Failed to play idle animation for", animationRoot:GetFullName(), trackOrError)
		return
	end

	record.IdleTrack = trackOrError
end

local function resolveStand(plot: Model): Instance?
	local stand = plot:FindFirstChild(STAND_NAME, true)
	if stand then
		return stand
	end

	return nil
end

local function resolveAnchorPart(root: Instance): BasePart?
	if root:IsA("BasePart") and not isHiddenSupportPart(root) then
		return root
	end

	if root:IsA("Model") and root.PrimaryPart and not isHiddenSupportPart(root.PrimaryPart) then
		return root.PrimaryPart
	end

	local fallbackPart: BasePart? = nil
	local basePart = root:FindFirstChildWhichIsA("BasePart", true)
	if basePart and basePart:IsA("BasePart") then
		fallbackPart = basePart
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and not isHiddenSupportPart(descendant) then
			return descendant
		end
	end

	return fallbackPart
end

local function disableForeignPrompts(record: PlotRecord)
	local stand = record.Stand
	if not stand then
		return
	end

	for _, descendant in ipairs(stand:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant ~= record.Prompt then
			descendant.Enabled = false
		end
	end
end

local function getManagedPrompt(record: PlotRecord): ProximityPrompt?
	if record.Prompt and record.Prompt.Parent then
		return record.Prompt
	end

	local stand = record.Stand
	if not stand then
		return nil
	end

	local existingPrompt = stand:FindFirstChild(MANAGED_PROMPT_NAME, true)
	if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
		record.Prompt = existingPrompt
		record.ManagedPromptCreated = existingPrompt:GetAttribute("ManagedByJoinLikeStand") == true
		return existingPrompt
	end

	local anchorPart = resolveAnchorPart(stand)
	if not anchorPart then
		return nil
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = MANAGED_PROMPT_NAME
	prompt.Parent = anchorPart
	prompt:SetAttribute("ManagedByJoinLikeStand", true)

	record.Prompt = prompt
	record.ManagedPromptCreated = true
	return prompt
end

local function configurePrompt(record: PlotRecord, actionText: string, enabled: boolean)
	if not record.UseProximityPrompt then
		return
	end

	local prompt = getManagedPrompt(record)
	if not prompt then
		return
	end

	prompt.ActionText = actionText
	prompt.ObjectText = getRewardObjectText()
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Enabled = enabled
end

local function refreshStandState(record: PlotRecord)
	local stand = record.Stand
	if not stand or not stand:IsDescendantOf(Workspace) then
		return
	end

	local plot = record.Plot
	if plot and not isOwnPlot(plot) then
		setStandVisibility(record, false)
		configurePrompt(record, JOIN_ACTION_TEXT, false)
		return
	end

	if not isRewardStateLoaded() then
		setStandVisibility(record, false)
		configurePrompt(record, LOADING_ACTION_TEXT, false)
		return
	end

	if isRewardClaimed() then
		setStandVisibility(record, false)
		configurePrompt(record, CLAIM_ACTION_TEXT, false)
		return
	end

	setStandVisibility(record, true)
	disableForeignPrompts(record)
	configurePrompt(record, if record.IsInGroup then CLAIM_ACTION_TEXT else JOIN_ACTION_TEXT, true)
	ensureIdleAnimationPlaying(record)
end

local function resolveGroupRewardOutcome(result): (string, string?, string?)
	if type(result) ~= "table" then
		return "Error", "Reward is unavailable right now.", "Error"
	end

	if result.Success == true then
		rewardClaimedOverride = true
		return "Claimed", "Reward Claimed Successfully!", "Success"
	end

	local errorCode = if type(result.Error) == "string" then result.Error else nil
	local message = if type(result.Msg) == "string" then result.Msg else nil

	if errorCode == "AlreadyClaimed" or message == "Already claimed!" then
		rewardClaimedOverride = true
		return "AlreadyClaimed", message or "Already claimed!", "Success"
	end

	if errorCode == "NotInGroup" then
		return "NotInGroup", nil, nil
	end

	return "Error", message or "Reward is unavailable right now.", "Error"
end

local function tryClaimReward(): string
	local success, resultOrError = pcall(function()
		return requestGroupReward:InvokeServer()
	end)

	if not success then
		warn("[JoinLikeStandController] Reward request failed:", resultOrError)
		NotificationManager.show("Reward is unavailable right now.", "Error")
		return "Error"
	end

	local outcome, message, messageType = resolveGroupRewardOutcome(resultOrError)
	if message and messageType then
		NotificationManager.show(message, messageType)
	end

	return outcome
end

local function handlePromptTriggered(record: PlotRecord, triggeringPlayer: Player?)
	if triggeringPlayer and triggeringPlayer ~= localPlayer then
		return
	end

	if record.Busy then
		return
	end

	record.Busy = true

	if isRewardClaimed() then
		refreshStandState(record)
		record.Busy = false
		return
	end

	record.IsInGroup = queryGroupMembership()
	local claimOutcome = tryClaimReward()
	if claimOutcome == "Claimed" or claimOutcome == "AlreadyClaimed" then
		refreshStandState(record)
		record.Busy = false
		return
	end

	if claimOutcome ~= "NotInGroup" then
		refreshStandState(record)
		record.Busy = false
		return
	end

	local promptSuccess, promptError = pcall(function()
		GroupService:PromptJoinAsync(GROUP_ID)
	end)

	if not promptSuccess then
		warn("[JoinLikeStandController] Group prompt failed:", promptError)
		NotificationManager.show("Group prompt is unavailable right now.", "Error")
	end

	record.IsInGroup = queryGroupMembership()
	if record.IsInGroup then
		local postJoinClaimOutcome = tryClaimReward()
		if postJoinClaimOutcome == "NotInGroup" then
			NotificationManager.show("Group membership is still syncing. Try again in a moment.", "Error")
		end
	end

	refreshStandState(record)
	record.Busy = false
end

local function connectPrompt(record: PlotRecord)
	if not record.UseProximityPrompt then
		return
	end

	local prompt = getManagedPrompt(record)
	if not prompt then
		return
	end

	if record.PromptConnection and record.Prompt == prompt then
		return
	end

	if record.PromptConnection then
		record.PromptConnection:Disconnect()
	end

	record.Prompt = prompt
	record.PromptConnection = prompt.Triggered:Connect(function(triggeringPlayer)
		handlePromptTriggered(record, triggeringPlayer)
	end)
end

local function resolveStandaloneTouchPart(stand: Instance): BasePart?
	if stand:IsA("Model") then
		local primaryPart = stand.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") then
			return primaryPart
		end

		return nil
	end

	if stand:IsA("BasePart") then
		return stand
	end

	return nil
end

local function isLocalCharacterTouch(hit: BasePart): boolean
	local character = localPlayer.Character
	return character ~= nil and hit:IsDescendantOf(character)
end

local function connectStandaloneTouch(record: PlotRecord)
	if not record.IsStandalone then
		return
	end

	local stand = record.Stand
	if not stand then
		return
	end

	local touchPart = resolveStandaloneTouchPart(stand)
	if record.TouchConnection and record.TouchPart == touchPart then
		if touchPart and not record.IsHidden then
			touchPart.CanTouch = true
		end
		return
	end

	if record.TouchConnection then
		record.TouchConnection:Disconnect()
		record.TouchConnection = nil
	end

	record.TouchPart = touchPart
	if not touchPart then
		return
	end

	if not record.IsHidden then
		touchPart.CanTouch = true
	end

	record.TouchConnection = touchPart.Touched:Connect(function(hit)
		if not hit:IsA("BasePart") or not isLocalCharacterTouch(hit) then
			return
		end

		local now = os.clock()
		if now - record.LastTouchAt < STAND_TOUCH_COOLDOWN then
			return
		end

		record.LastTouchAt = now
		handlePromptTriggered(record, localPlayer)
	end)
end

local function cleanupStandaloneStand()
	local record = standaloneRecord
	if not record then
		return
	end

	stopIdleTrack(record)
	disconnectRecord(record)
	standaloneRecord = nil
end

local function bindStandaloneStand(stand: Instance)
	if findAncestorPlot(stand) then
		return
	end

	if standaloneRecord and standaloneRecord.Stand == stand then
		connectStandaloneTouch(standaloneRecord)
		refreshStandState(standaloneRecord)
		return
	end

	cleanupStandaloneStand()

	local record = createRecord(nil, stand, true)
	record.IsInGroup = queryGroupMembership()
	standaloneRecord = record

	connectStandaloneTouch(record)
	refreshStandState(record)
	ensureIdleAnimationPlaying(record)

	table.insert(record.Connections, stand.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupStandaloneStand()
		end
	end))

	if stand:IsA("Model") then
		table.insert(record.Connections, stand:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			connectStandaloneTouch(record)
			refreshStandState(record)
		end))
	end

	table.insert(record.Connections, stand.DescendantAdded:Connect(function(descendant)
		if record.IsHidden then
			applyVisibilityToInstance(record, descendant, false)
		else
			applyVisibilityToInstance(record, descendant, true)
			disableForeignPrompts(record)
		end

		if descendant:IsA("BasePart") then
			task.defer(function()
				connectStandaloneTouch(record)
				refreshStandState(record)
			end)
		end

		if descendant:IsA("Animation") or descendant:IsA("Humanoid") or descendant:IsA("AnimationController") or descendant:IsA("Animator") then
			task.defer(function()
				ensureIdleAnimationPlaying(record)
			end)
		end
	end))
end

local function bindPlot(plot: Model)
	if recordsByPlot[plot] then
		return
	end

	local stand = resolveStand(plot)
	if not stand then
		return
	end

	local record = getRecord(plot)
	record.Stand = stand
	record.IsInGroup = queryGroupMembership()

	connectPrompt(record)
	refreshStandState(record)

	table.insert(record.Connections, plot.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupPlot(plot)
		end
	end))

	table.insert(record.Connections, stand.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupPlot(plot)
		end
	end))

	table.insert(record.Connections, stand.DescendantAdded:Connect(function(descendant)
		if record.IsHidden then
			applyVisibilityToInstance(record, descendant, false)
		else
			applyVisibilityToInstance(record, descendant, true)
			disableForeignPrompts(record)
		end

		if descendant:IsA("BasePart") or descendant:IsA("ProximityPrompt") then
			task.defer(function()
				connectPrompt(record)
				refreshStandState(record)
			end)
		end

		if descendant:IsA("Animation") or descendant:IsA("Humanoid") or descendant:IsA("AnimationController") or descendant:IsA("Animator") then
			task.defer(function()
				ensureIdleAnimationPlaying(record)
			end)
		end
	end))
end

for _, child in ipairs(Workspace:GetChildren()) do
	if isPlotModel(child) then
		bindPlot(child)
	elseif child.Name == STAND_NAME then
		bindStandaloneStand(child)
	end
end

Workspace.ChildAdded:Connect(function(child)
	if isPlotModel(child) then
		bindPlot(child)
	elseif child.Name == STAND_NAME then
		bindStandaloneStand(child)
	end
end)

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name ~= STAND_NAME then
		return
	end

	local plot = findAncestorPlot(descendant)
	if plot then
		bindPlot(plot)
	elseif descendant.Parent == Workspace then
		bindStandaloneStand(descendant)
	end
end)

Workspace.ChildRemoved:Connect(function(child)
	local record = standaloneRecord
	if record and record.Stand == child then
		cleanupStandaloneStand()
	end

	if child:IsA("Model") then
		cleanupPlot(child)
	end
end)

localPlayer:GetAttributeChangedSignal("GroupRewardClaimed"):Connect(function()
	if localPlayer:GetAttribute("GroupRewardClaimed") == true then
		rewardClaimedOverride = true
	end

	for _, record in pairs(recordsByPlot) do
		refreshStandState(record)
	end

	if standaloneRecord then
		connectStandaloneTouch(standaloneRecord)
		refreshStandState(standaloneRecord)
	end
end)
