--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PostTutorialConfiguration = require(ReplicatedStorage.Modules.PostTutorialConfiguration)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)
local SlotUnlockConfigurations = require(ReplicatedStorage.Modules.SlotUnlockConfigurations)
local UpgradesConfigurations = require(ReplicatedStorage.Modules.UpgradesConfigurations)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)

type PlayerControllerType = {
	GetProfile: (self: any, player: Player) -> any,
	OnTutorialStepChanged: ((self: any, player: Player, step: number) -> ())?,
}

local TutorialService = {}

local PlayerController: PlayerControllerType? = nil
local PickaxeController: any = nil
local reportActionEvent: RemoteEvent? = nil
local postTutorialCompletionEvent: RemoteEvent? = nil
local CURRENT_TUTORIAL_VERSION = 4
local PREVIOUS_TUTORIAL_ANALYTICS_KEY = "Tutor_22_04"
local LEGACY_TUTORIAL_ANALYTICS_KEY = "TutorialFTUE"
local PRE_FINAL_AUTO_ADVANCE_STEP = TutorialConfiguration.FinalStep - 1
local STEP_ONE_MIN_DISPLAY_TIME = 1.5
local PRE_FINAL_AUTO_ADVANCE_DELAY = 0
local COLLECT_CASH_STEP = 6
local OPEN_BOMB_SHOP_STEP = 7
local BUY_BOMB_TWO_STEP = 8
local BUY_BOMB_TWO_ID = "Bomb 2"
local BUY_BOMB_TWO_AUTO_PURCHASE_DELAY = 10
local stepActivatedAt: {[Player]: number} = {}
local stepOneEvaluationTokens: {[Player]: number} = {}
local preFinalAutoAdvanceTokens: {[Player]: number} = {}
local buyBombTwoAutoPurchaseStates: {[Player]: {StartedAt: number}} = {}
local DEBUG_TUTORIAL = false
local DEBUG_BRAINROT_TRACE = false

local function debugTutorialLog(player: Player, message: string)
	if DEBUG_TUTORIAL then
		print(("[Tutorial][Server][%s] %s"):format(player.Name, message))
	end
end

local function summarizeToolContainer(container: Instance?): string
	if not container then
		return "[]"
	end

	local entries = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and (child:GetAttribute("Mutation") ~= nil or child:GetAttribute("IsLuckyBlock") == true) then
			table.insert(entries, ("Tool{name=%s,orig=%s,mut=%s,rar=%s,lvl=%s,parent=%s}"):format(
				tostring(child.Name),
				tostring(child:GetAttribute("OriginalName")),
				tostring(child:GetAttribute("Mutation")),
				tostring(child:GetAttribute("Rarity")),
				tostring(child:GetAttribute("Level")),
				tostring(child.Parent and child.Parent.Name or "nil")
			))
		end
	end

	table.sort(entries)
	return "[" .. table.concat(entries, ", ") .. "]"
end

local function logBrainrotTrace(player: Player, message: string)
	if not DEBUG_BRAINROT_TRACE then
		return
	end

	local backpack = player:FindFirstChild("Backpack")
	print(("[BrainrotTrace][TutorialService][%s][step=%s][server=%.3f] %s | char=%s | backpack=%s"):format(
		player.Name,
		tostring(player:GetAttribute("OnboardingStep")),
		Workspace:GetServerTimeNow(),
		message,
		summarizeToolContainer(player.Character),
		summarizeToolContainer(backpack)
	))
end

local function getUpgradeConfig(upgradeId: string)
	for _, config in ipairs(UpgradesConfigurations.Upgrades) do
		if config.Id == upgradeId then
			return config
		end
	end

	return nil
end

local function getCurrentMoney(player: Player?, profile: any): number
	local leaderstats = if player then player:FindFirstChild("leaderstats") else nil
	local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
	if moneyValue and moneyValue:IsA("NumberValue") then
		return moneyValue.Value
	end

	return tonumber(profile.Data.Money) or 0
end

local function getStoredPostTutorialStage(profile: any): number
	return PostTutorialConfiguration.ClampStage(
		tonumber(profile.Data.PostTutorialStage) or PostTutorialConfiguration.Stages.WaitingForCharacterMoney
	)
end

local function isTutorialSkipped(profile: any): boolean
	return profile ~= nil and profile.Data ~= nil and profile.Data.TutorialSkipped == true
end

local function getProfile(player: Player)
	if not PlayerController then
		return nil
	end

	return PlayerController:GetProfile(player)
end

local function getCurrentStep(player: Player): number
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return 1
	end

	local step = tonumber(profile.Data.OnboardingStep) or 1
	return math.clamp(step, 1, TutorialConfiguration.FinalStep)
end

local function syncStepAttribute(player: Player, step: number)
	player:SetAttribute("OnboardingStep", step)
	debugTutorialLog(player, ("OnboardingStep=%d"):format(step))
end

local function markStepActivated(player: Player)
	stepActivatedAt[player] = tick()
end

local function invalidateScheduledStepOneEvaluation(player: Player)
	stepOneEvaluationTokens[player] = (stepOneEvaluationTokens[player] or 0) + 1
end

local function invalidateScheduledPreFinalAutoAdvance(player: Player)
	preFinalAutoAdvanceTokens[player] = (preFinalAutoAdvanceTokens[player] or 0) + 1
end

local function cancelBuyBombTwoAutoPurchase(player: Player)
	buyBombTwoAutoPurchaseStates[player] = nil
end

local function ensureBuyBombTwoAutoPurchase(player: Player)
	if buyBombTwoAutoPurchaseStates[player] or getCurrentStep(player) ~= BUY_BOMB_TWO_STEP then
		return
	end

	local state = {
		StartedAt = os.clock(),
	}
	buyBombTwoAutoPurchaseStates[player] = state

	task.delay(BUY_BOMB_TWO_AUTO_PURCHASE_DELAY, function()
		if buyBombTwoAutoPurchaseStates[player] ~= state then
			return
		end

		buyBombTwoAutoPurchaseStates[player] = nil
		if not player.Parent or getCurrentStep(player) ~= BUY_BOMB_TWO_STEP then
			return
		end

		if PickaxeController and PickaxeController.PurchaseBombForTutorial then
			PickaxeController:PurchaseBombForTutorial(player, BUY_BOMB_TWO_ID)
		end
	end)
end

local function schedulePreFinalAutoAdvance(player: Player)
	local token = (preFinalAutoAdvanceTokens[player] or 0) + 1
	preFinalAutoAdvanceTokens[player] = token

	task.delay(PRE_FINAL_AUTO_ADVANCE_DELAY, function()
		if preFinalAutoAdvanceTokens[player] ~= token then
			return
		end

		if not player.Parent then
			return
		end

		if getCurrentStep(player) ~= PRE_FINAL_AUTO_ADVANCE_STEP then
			return
		end

		TutorialService:AdvanceToStep(player, TutorialConfiguration.FinalStep)
	end)
end

local function getRemainingInitialStepOneDisplayTime(player: Player, step: number): number
	if step ~= 1 then
		return 0
	end

	local activatedAt = stepActivatedAt[player]
	if type(activatedAt) ~= "number" then
		return 0
	end

	return math.max(0, STEP_ONE_MIN_DISPLAY_TIME - (tick() - activatedAt))
end

local function getCurrentPostTutorialStage(player: Player): number
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return PostTutorialConfiguration.Stages.WaitingForCharacterMoney
	end

	return getStoredPostTutorialStage(profile)
end

local function syncPostTutorialStageAttribute(player: Player, stage: number)
	player:SetAttribute("PostTutorialStage", PostTutorialConfiguration.ClampStage(stage))
end

local function syncTutorialSkippedAttribute(player: Player, skipped: boolean)
	player:SetAttribute("TutorialSkipped", skipped == true)
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function isInsideAnyMineZone(position: Vector3): boolean
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then
		return false
	end

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

local function hasBrainrotInHandOrInventory(player: Player): boolean
	local character = player.Character
	if character then
		if character:FindFirstChild("HeadStackItem") or character:FindFirstChild("StackItem") then
			return true
		end

		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("Mutation") ~= nil then
				return true
			end
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("Mutation") ~= nil then
				return true
			end
		end
	end

	return false
end

local function hasPlacedBrainrot(player: Player): boolean
	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then
		return false
	end

	for _, floor in ipairs(plot:GetChildren()) do
		if floor:IsA("Model") and floor.Name:match("^Floor%d+$") then
			local slots = floor:FindFirstChild("Slots")
			if slots then
				for _, slot in ipairs(slots:GetChildren()) do
					local spawnPart = slot:FindFirstChild("Spawn")
					if spawnPart then
						local visualItem = spawnPart:FindFirstChild("VisualItem")
						if visualItem and visualItem:GetAttribute("IsLuckyBlock") ~= true then
							return true
						end
					end
				end
			end
		end
	end

	return false
end

local function hasPurchasedAdditionalBomb(player: Player, profile: any): boolean
	local ownedPickaxes = profile.Data.OwnedPickaxes
	if type(ownedPickaxes) ~= "table" then
		return false
	end

	for pickaxeName, isOwned in pairs(ownedPickaxes) do
		if pickaxeName ~= "Bomb 1" and isOwned == true then
			return true
		end
	end

	return false
end

local function hasSpecificCharacterUpgrade(profile: any, upgradeId: string): boolean
	local config = getUpgradeConfig(upgradeId)
	if not config then
		return false
	end

	local currentValue = tonumber(profile.Data[config.StatId]) or 0
	local defaultValue = tonumber(config.DefaultValue) or 0
	return currentValue >= (defaultValue + (tonumber(config.Amount) or 1))
end

local function getPlayerPlot(player: Player): Model?
	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if plot and plot:IsA("Model") then
		return plot
	end

	return nil
end

local function hasBaseSlotUpgrade(profile: any): boolean
	local unlockedSlots = SlotUnlockConfigurations.ClampSlots(
		tonumber(profile.Data.unlocked_slots) or SlotUnlockConfigurations.StartSlots
	)

	return unlockedSlots > SlotUnlockConfigurations.StartSlots
end

local function getBaseUpgradeTargetPart(player: Player): BasePart?
	local plot = getPlayerPlot(player)
	if not plot then
		return nil
	end

	local upgradeButton = plot:FindFirstChild("UpgradeSlotsButton", true)
	if not upgradeButton then
		return nil
	end

	if upgradeButton:IsA("BasePart") then
		return upgradeButton
	end

	if upgradeButton:IsA("Model") then
		return upgradeButton.PrimaryPart or upgradeButton:FindFirstChildWhichIsA("BasePart", true)
	end

	return upgradeButton:FindFirstChildWhichIsA("BasePart", true)
end

local function isNearBaseUpgradeButton(player: Player): boolean
	local rootPart = getRootPart(player)
	local targetPart = getBaseUpgradeTargetPart(player)
	if not rootPart or not targetPart then
		return false
	end

	return (rootPart.Position - targetPart.Position).Magnitude <= TutorialConfiguration.BaseUpgradeApproachDistance
end

local function isMainTutorialCompleted(profile: any): boolean
	return (tonumber(profile.Data.OnboardingStep) or 1) >= TutorialConfiguration.FinalStep
end

local function resolvePostTutorialStage(player: Player?, profile: any): number
	if not profile or not profile.Data then
		return PostTutorialConfiguration.Stages.WaitingForCharacterMoney
	end

	if isTutorialSkipped(profile) then
		return PostTutorialConfiguration.Stages.Completed
	end

	if not isMainTutorialCompleted(profile) then
		return getStoredPostTutorialStage(profile)
	end

	-- Upgrade prompts are no longer part of the onboarding/post-tutorial guidance flow.
	return PostTutorialConfiguration.Stages.Completed
end

local function getStepAfterBrainrotPickup(pickedUpInMine: boolean): number
	if pickedUpInMine then
		return 4
	end

	return 5
end

local function firePostTutorialCompletion(player: Player, message: string)
	if postTutorialCompletionEvent then
		postTutorialCompletionEvent:FireClient(player, message, PostTutorialConfiguration.CompletionMessageDuration)
	end
end

local function setCurrentStep(player: Player, profile: any, step: number)
	local clampedStep = math.clamp(step, 1, TutorialConfiguration.FinalStep)
	local previousStep = tonumber(profile.Data.OnboardingStep) or 1
	profile.Data.OnboardingStep = clampedStep
	syncStepAttribute(player, clampedStep)
	logBrainrotTrace(player, ("setCurrentStep %s -> %s"):format(
		tostring(previousStep),
		tostring(clampedStep)
	))
	markStepActivated(player)
	invalidateScheduledStepOneEvaluation(player)
	invalidateScheduledPreFinalAutoAdvance(player)
	if clampedStep ~= BUY_BOMB_TWO_STEP then
		cancelBuyBombTwoAutoPurchase(player)
	end
	AnalyticsFunnelsService:SyncTutorial(player, clampedStep)
	if previousStep < TutorialConfiguration.FinalStep and clampedStep >= TutorialConfiguration.FinalStep then
		AnalyticsFunnelsService:HandleTutorialCompleted(player)
	end

	if PlayerController and PlayerController.OnTutorialStepChanged then
		PlayerController:OnTutorialStepChanged(player, clampedStep)
	end

	if clampedStep == PRE_FINAL_AUTO_ADVANCE_STEP then
		schedulePreFinalAutoAdvance(player)
	end
end

local function setCurrentPostTutorialStage(player: Player, profile: any, stage: number)
	local clampedStage = PostTutorialConfiguration.ClampStage(stage)
	profile.Data.PostTutorialStage = clampedStage
	syncPostTutorialStageAttribute(player, clampedStage)
end

local function ensureTutorialFlags(profile: any)
	if type(profile.Data.TutorialVersion) ~= "number" then
		profile.Data.TutorialVersion = 1
	end

	if type(profile.Data.TutorialFreeCharacterUpgradeConsumed) ~= "boolean" then
		profile.Data.TutorialFreeCharacterUpgradeConsumed = false
	end

	if type(profile.Data.TutorialFreeBaseUpgradeConsumed) ~= "boolean" then
		profile.Data.TutorialFreeBaseUpgradeConsumed = false
	end

	if type(profile.Data.TutorialSkipped) ~= "boolean" then
		profile.Data.TutorialSkipped = false
	end
end

local function consumeTutorialCharacterUpgrade(profile: any)
	profile.Data.TutorialFreeCharacterUpgradeConsumed = true
end

local function consumeTutorialBaseUpgrade(profile: any)
	profile.Data.TutorialFreeBaseUpgradeConsumed = true
end

local function remapLegacyTutorialStepForVersionThree(step: number): number
	local remappedStep = math.max(1, math.floor(tonumber(step) or 1))
	if remappedStep >= 7 then
		remappedStep -= 1
	end

	return math.clamp(remappedStep, 1, TutorialConfiguration.FinalStep)
end

local function remapVersionThreeStepForVersionFour(step: number): number
	local remappedStep = math.max(1, math.floor(tonumber(step) or 1))
	if remappedStep <= COLLECT_CASH_STEP then
		return math.clamp(remappedStep, 1, TutorialConfiguration.FinalStep)
	end
	if remappedStep == OPEN_BOMB_SHOP_STEP then
		return BUY_BOMB_TWO_STEP
	end

	return TutorialConfiguration.FinalStep
end

local function migrateTutorialProgress(profile: any)
	ensureTutorialFlags(profile)

	local previousTutorialVersion = math.floor(tonumber(profile.Data.TutorialVersion) or 1)
	if previousTutorialVersion >= CURRENT_TUTORIAL_VERSION then
		if hasSpecificCharacterUpgrade(profile, TutorialConfiguration.TutorialCharacterUpgradeId) then
			consumeTutorialCharacterUpgrade(profile)
		end
		if hasBaseSlotUpgrade(profile) then
			consumeTutorialBaseUpgrade(profile)
		end
		profile.Data.PostTutorialStage = getStoredPostTutorialStage(profile)
		return
	end

	local currentStep = math.max(1, tonumber(profile.Data.OnboardingStep) or 1)
	if previousTutorialVersion < 2 then
		if currentStep >= TutorialConfiguration.LegacyCompletedFinalStep then
			currentStep = TutorialConfiguration.FinalStep
		end
	elseif previousTutorialVersion < 3 then
		if currentStep >= 13 then
			currentStep = 12
		else
			currentStep = remapLegacyTutorialStepForVersionThree(currentStep)
		end
	end

	if previousTutorialVersion < CURRENT_TUTORIAL_VERSION then
		currentStep = remapVersionThreeStepForVersionFour(currentStep)
	end

	profile.Data.OnboardingStep = math.clamp(currentStep, 1, TutorialConfiguration.FinalStep)
	if type(profile.Data.AnalyticsFunnels) == "table" and type(profile.Data.AnalyticsFunnels.OneTime) == "table" then
		profile.Data.AnalyticsFunnels.OneTime[PREVIOUS_TUTORIAL_ANALYTICS_KEY] = nil
		profile.Data.AnalyticsFunnels.OneTime[LEGACY_TUTORIAL_ANALYTICS_KEY] = nil
	end

	if hasSpecificCharacterUpgrade(profile, TutorialConfiguration.TutorialCharacterUpgradeId) then
		consumeTutorialCharacterUpgrade(profile)
	end
	if hasBaseSlotUpgrade(profile) then
		consumeTutorialBaseUpgrade(profile)
	end

	profile.Data.PostTutorialStage = getStoredPostTutorialStage(profile)
	profile.Data.TutorialVersion = CURRENT_TUTORIAL_VERSION
end

local function reconcileStepWithCurrentState(player: Player, profile: any): number
	local currentStep = getCurrentStep(player)
	logBrainrotTrace(player, ("reconcileStepWithCurrentState currentStep=%s hasBrainrot=%s hasPlaced=%s"):format(
		tostring(currentStep),
		tostring(hasBrainrotInHandOrInventory(player)),
		tostring(hasPlacedBrainrot(player))
	))

	-- If the player left during step 4, the carried brainrot is gone on next join,
	-- so we must return them to step 3 to pick one up again.
	if currentStep == 4 and not hasBrainrotInHandOrInventory(player) then
		logBrainrotTrace(player, "reconcileStepWithCurrentState rewinding step 4 -> 3 because no brainrot remains")
		setCurrentStep(player, profile, 3)
		return 3
	end

	if currentStep == 5 and not hasPlacedBrainrot(player) and not hasBrainrotInHandOrInventory(player) then
		logBrainrotTrace(player, "reconcileStepWithCurrentState rewinding step 5 -> 3 because no brainrot is in hand/inventory")
		setCurrentStep(player, profile, 3)
		return 3
	end

	return currentStep
end

function TutorialService:GetCurrentStep(player: Player): number
	return getCurrentStep(player)
end

function TutorialService:GetCurrentPostTutorialStage(player: Player): number
	return getCurrentPostTutorialStage(player)
end

function TutorialService:GetStepDefinition(step: number)
	return TutorialConfiguration.Steps[step]
end

function TutorialService:IsTutorialCharacterUpgradeFreeAvailable(player: Player, upgradeId: string): boolean
	return false
end

function TutorialService:IsTutorialBaseUpgradeFreeAvailable(player: Player): boolean
	return false
end

function TutorialService:SyncPlayer(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		local step = getCurrentStep(player)
		local storedStage = tonumber(player:GetAttribute("PostTutorialStage"))
		local tutorialSkipped = player:GetAttribute("TutorialSkipped") == true
		syncStepAttribute(player, step)
		markStepActivated(player)
		invalidateScheduledStepOneEvaluation(player)
		invalidateScheduledPreFinalAutoAdvance(player)
		syncTutorialSkippedAttribute(player, tutorialSkipped)
		syncPostTutorialStageAttribute(
			player,
			PostTutorialConfiguration.ClampStage(
				storedStage or PostTutorialConfiguration.Stages.WaitingForCharacterMoney
			)
		)
		AnalyticsFunnelsService:SyncTutorial(player, step)
		return step
	end

	migrateTutorialProgress(profile)

	local step = reconcileStepWithCurrentState(player, profile)
	syncStepAttribute(player, step)
	markStepActivated(player)
	invalidateScheduledStepOneEvaluation(player)
	invalidateScheduledPreFinalAutoAdvance(player)
	if step ~= BUY_BOMB_TWO_STEP then
		cancelBuyBombTwoAutoPurchase(player)
	end
	syncTutorialSkippedAttribute(player, isTutorialSkipped(profile))
	setCurrentPostTutorialStage(player, profile, resolvePostTutorialStage(player, profile))
	AnalyticsFunnelsService:SyncTutorial(player, step)
	if step >= TutorialConfiguration.FinalStep then
		AnalyticsFunnelsService:HandleTutorialCompleted(player)
	end

	if step == PRE_FINAL_AUTO_ADVANCE_STEP then
		schedulePreFinalAutoAdvance(player)
	end

	return step
end

function TutorialService:AdvanceToStep(player: Player, step: number): boolean
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return false
	end

	local currentStep = getCurrentStep(player)
	local targetStep = math.clamp(step, 1, TutorialConfiguration.FinalStep)
	if targetStep <= currentStep then
		return false
	end

	debugTutorialLog(player, ("AdvanceToStep %d -> %d"):format(currentStep, targetStep))
	setCurrentStep(player, profile, targetStep)
	self:EvaluateCurrentStep(player)
	return true
end

function TutorialService:SkipTutorial(player: Player): boolean
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return false
	end

	ensureTutorialFlags(profile)

	local currentStep = getCurrentStep(player)
	if currentStep >= TutorialConfiguration.FinalStep or isTutorialSkipped(profile) then
		return false
	end

	debugTutorialLog(player, ("SkipTutorial step=%d"):format(currentStep))
	profile.Data.TutorialSkipped = true
	syncTutorialSkippedAttribute(player, true)
	consumeTutorialCharacterUpgrade(profile)
	consumeTutorialBaseUpgrade(profile)
	setCurrentPostTutorialStage(player, profile, PostTutorialConfiguration.Stages.Completed)
	AnalyticsFunnelsService:HandleTutorialSkipped(player, currentStep)
	self:AdvanceToStep(player, TutorialConfiguration.FinalStep)
	return true
end

function TutorialService:EvaluatePostTutorial(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return
	end

	setCurrentPostTutorialStage(player, profile, resolvePostTutorialStage(player, profile))
end

function TutorialService:EvaluateCurrentStep(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return
	end

	ensureTutorialFlags(profile)
	reconcileStepWithCurrentState(player, profile)

	local advanced = true
	while advanced do
		advanced = false

		local currentStep = getCurrentStep(player)
		if currentStep >= 3 and currentStep <= 5 then
			logBrainrotTrace(player, ("EvaluateCurrentStep currentStep=%s hasBrainrot=%s hasPlaced=%s"):format(
				tostring(currentStep),
				tostring(hasBrainrotInHandOrInventory(player)),
				tostring(hasPlacedBrainrot(player))
			))
		end
		debugTutorialLog(player, ("EvaluateStep %d"):format(currentStep))
		if currentStep >= TutorialConfiguration.FinalStep then
			self:EvaluatePostTutorial(player)
			return
		end

		local rootPart = getRootPart(player)
		local nextStep: number? = nil

		if currentStep == 1 then
			if rootPart
				and isInsideAnyMineZone(rootPart.Position)
				and getRemainingInitialStepOneDisplayTime(player, currentStep) <= 0
			then
				nextStep = 2
			end
		elseif currentStep == 5 then
			if hasPlacedBrainrot(player) then
				nextStep = COLLECT_CASH_STEP
			end
		elseif currentStep == BUY_BOMB_TWO_STEP then
			if hasPurchasedAdditionalBomb(player, profile) then
				nextStep = PRE_FINAL_AUTO_ADVANCE_STEP
			end
		end

		if nextStep then
			setCurrentStep(player, profile, nextStep)
			advanced = true
		end
	end

	self:EvaluatePostTutorial(player)
end

function TutorialService:HandleMineZoneEntered(player: Player)
	logBrainrotTrace(player, ("HandleMineZoneEntered currentStep=%s"):format(tostring(getCurrentStep(player))))
	if getCurrentStep(player) == 1 then
		local remainingDisplayTime = getRemainingInitialStepOneDisplayTime(player, 1)
		if remainingDisplayTime > 0 then
			local token = (stepOneEvaluationTokens[player] or 0) + 1
			stepOneEvaluationTokens[player] = token
			task.delay(remainingDisplayTime, function()
				if stepOneEvaluationTokens[player] ~= token then
					return
				end

				stepOneEvaluationTokens[player] = nil
				if player.Parent and getCurrentStep(player) == 1 then
					self:EvaluateCurrentStep(player)
				end
			end)
			return
		end

		self:AdvanceToStep(player, 2)
	end
end

function TutorialService:HandleBombThrown(player: Player)
	if getCurrentStep(player) == 2 then
		self:AdvanceToStep(player, 3)
	end
end

function TutorialService:HandleBrainrotPickedUp(player: Player, pickedUpInMine: boolean?)
	local isPickupInMine = pickedUpInMine ~= false
	local currentStep = getCurrentStep(player)
	logBrainrotTrace(player, ("HandleBrainrotPickedUp inMine=%s currentStep=%s"):format(
		tostring(isPickupInMine),
		tostring(currentStep)
	))
	debugTutorialLog(player, ("HandleBrainrotPickedUp inMine=%s step=%d"):format(tostring(isPickupInMine), currentStep))
	if currentStep == 2 or currentStep == 3 then
		self:AdvanceToStep(player, getStepAfterBrainrotPickup(isPickupInMine))
	else
		self:EvaluateCurrentStep(player)
	end
end

function TutorialService:HandleMineZoneExited(player: Player)
	local currentStep = getCurrentStep(player)
	local hasBrainrot = hasBrainrotInHandOrInventory(player)
	logBrainrotTrace(player, ("HandleMineZoneExited currentStep=%s hasBrainrot=%s"):format(
		tostring(currentStep),
		tostring(hasBrainrot)
	))
	debugTutorialLog(player, ("HandleMineZoneExited step=%d hasBrainrot=%s"):format(currentStep, tostring(hasBrainrot)))

	if currentStep == 4 then
		if hasBrainrot then
			self:AdvanceToStep(player, 5)
		else
			-- If the carry-to-tool conversion failed or the item vanished, immediately
			-- reconcile the FTUE back to pickup instead of leaving the player on step 5.
			self:EvaluateCurrentStep(player)
		end
	end
end

function TutorialService:HandleBrainrotPlaced(player: Player)
	logBrainrotTrace(player, ("HandleBrainrotPlaced currentStep=%s"):format(tostring(getCurrentStep(player))))
	debugTutorialLog(player, "HandleBrainrotPlaced")
	if getCurrentStep(player) == 5 then
		self:AdvanceToStep(player, COLLECT_CASH_STEP)
	else
		self:EvaluateCurrentStep(player)
	end
end

function TutorialService:HandleManualCollect(player: Player, amount: number)
	debugTutorialLog(player, ("HandleManualCollect amount=%d"):format(math.floor(tonumber(amount) or 0)))
	if math.floor(tonumber(amount) or 0) <= 0 then
		return
	end

	if getCurrentStep(player) == COLLECT_CASH_STEP then
		self:AdvanceToStep(player, OPEN_BOMB_SHOP_STEP)
	end
end

function TutorialService:HandleMoneyChanged(player: Player)
	debugTutorialLog(player, "HandleMoneyChanged")
	self:EvaluateCurrentStep(player)
end

function TutorialService:HandleBombPurchased(player: Player)
	debugTutorialLog(player, "HandleBombPurchased")
	if getCurrentStep(player) == BUY_BOMB_TWO_STEP then
		self:AdvanceToStep(player, PRE_FINAL_AUTO_ADVANCE_STEP)
	else
		self:EvaluateCurrentStep(player)
	end
end

function TutorialService:HandlePostTutorialCharacterUpgradePurchased(player: Player, _upgradeId: string?)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return
	end

	ensureTutorialFlags(profile)
	local isTutorialCharacterUpgrade = type(_upgradeId) == "string"
		and _upgradeId == TutorialConfiguration.TutorialCharacterUpgradeId

	if isTutorialCharacterUpgrade then
		consumeTutorialCharacterUpgrade(profile)
	end

	self:EvaluatePostTutorial(player)
	self:EvaluateCurrentStep(player)
end

function TutorialService:HandlePostTutorialBaseUpgradePurchased(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return
	end

	ensureTutorialFlags(profile)
	consumeTutorialBaseUpgrade(profile)

	self:EvaluatePostTutorial(player)
	self:EvaluateCurrentStep(player)
end

function TutorialService:ReportAction(player: Player, actionId: string)
	local currentStep = getCurrentStep(player)
	debugTutorialLog(player, ("ReportAction %s (step=%d)"):format(actionId, currentStep))

	if actionId == "BackPressed" then
		if currentStep == 4 then
			self:AdvanceToStep(player, 5)
		end
	elseif actionId == "SkipTutorialPressed" then
		self:SkipTutorial(player)
	elseif actionId == "ShopOpened" then
		if currentStep == OPEN_BOMB_SHOP_STEP then
			self:AdvanceToStep(player, BUY_BOMB_TWO_STEP)
			ensureBuyBombTwoAutoPurchase(player)
		elseif currentStep == BUY_BOMB_TWO_STEP then
			ensureBuyBombTwoAutoPurchase(player)
		end
	end
end

function TutorialService:Init(controllers)
	PlayerController = controllers.PlayerController
	PickaxeController = controllers.PickaxeController

	local events = ReplicatedStorage:WaitForChild("Events")
	reportActionEvent = events:FindFirstChild("ReportTutorialAction") :: RemoteEvent
	if not reportActionEvent then
		reportActionEvent = Instance.new("RemoteEvent")
		reportActionEvent.Name = "ReportTutorialAction"
		reportActionEvent.Parent = events
	end

	postTutorialCompletionEvent = events:FindFirstChild("ShowPostTutorialCompletion") :: RemoteEvent
	if not postTutorialCompletionEvent then
		postTutorialCompletionEvent = Instance.new("RemoteEvent")
		postTutorialCompletionEvent.Name = "ShowPostTutorialCompletion"
		postTutorialCompletionEvent.Parent = events
	end

	reportActionEvent.OnServerEvent:Connect(function(player, actionId)
		if type(actionId) == "string" then
			self:ReportAction(player, actionId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		stepActivatedAt[player] = nil
		stepOneEvaluationTokens[player] = nil
		preFinalAutoAdvanceTokens[player] = nil
		buyBombTwoAutoPurchaseStates[player] = nil
	end)
end

return TutorialService
