--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
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
local reportActionEvent: RemoteEvent? = nil
local postTutorialCompletionEvent: RemoteEvent? = nil
local CURRENT_TUTORIAL_VERSION = 2

local function getUpgradeConfig(upgradeId: string)
	for _, config in ipairs(UpgradesConfigurations.Upgrades) do
		if config.Id == upgradeId then
			return config
		end
	end

	return nil
end

local function getCurrentMoney(player: Player, profile: any): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
	if moneyValue and moneyValue:IsA("NumberValue") then
		return moneyValue.Value
	end

	return tonumber(profile.Data.Money) or 0
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
end

local function getCurrentPostTutorialStage(player: Player): number
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return PostTutorialConfiguration.Stages.Completed
	end

	return PostTutorialConfiguration.ClampStage(
		tonumber(profile.Data.PostTutorialStage) or PostTutorialConfiguration.Stages.Completed
	)
end

local function syncPostTutorialStageAttribute(player: Player, stage: number)
	player:SetAttribute("PostTutorialStage", PostTutorialConfiguration.ClampStage(stage))
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

local function firePostTutorialCompletion(player: Player, message: string)
	if postTutorialCompletionEvent then
		postTutorialCompletionEvent:FireClient(player, message, PostTutorialConfiguration.CompletionMessageDuration)
	end
end

local function setCurrentStep(player: Player, profile: any, step: number)
	local clampedStep = math.clamp(step, 1, TutorialConfiguration.FinalStep)
	profile.Data.OnboardingStep = clampedStep
	syncStepAttribute(player, clampedStep)
	AnalyticsFunnelsService:SyncTutorial(player, clampedStep)

	if PlayerController and PlayerController.OnTutorialStepChanged then
		PlayerController:OnTutorialStepChanged(player, clampedStep)
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
end

local function consumeTutorialCharacterUpgrade(profile: any)
	profile.Data.TutorialFreeCharacterUpgradeConsumed = true
end

local function consumeTutorialBaseUpgrade(profile: any)
	profile.Data.TutorialFreeBaseUpgradeConsumed = true
end

local function migrateTutorialProgress(profile: any)
	ensureTutorialFlags(profile)

	if profile.Data.TutorialVersion >= CURRENT_TUTORIAL_VERSION then
		if hasSpecificCharacterUpgrade(profile, TutorialConfiguration.TutorialCharacterUpgradeId) then
			consumeTutorialCharacterUpgrade(profile)
		end
		if hasBaseSlotUpgrade(profile) then
			consumeTutorialBaseUpgrade(profile)
		end
		profile.Data.PostTutorialStage = PostTutorialConfiguration.Stages.Completed
		return
	end

	local currentStep = math.max(1, tonumber(profile.Data.OnboardingStep) or 1)
	if currentStep >= TutorialConfiguration.LegacyCompletedFinalStep then
		profile.Data.OnboardingStep = TutorialConfiguration.FinalStep
		profile.Data.OnboardingFunnelStep = 14

		if type(profile.Data.AnalyticsFunnels) == "table" and type(profile.Data.AnalyticsFunnels.OneTime) == "table" then
			profile.Data.AnalyticsFunnels.OneTime.TutorialFTUE = 14
		end
	end

	if hasSpecificCharacterUpgrade(profile, TutorialConfiguration.TutorialCharacterUpgradeId) then
		consumeTutorialCharacterUpgrade(profile)
	end
	if hasBaseSlotUpgrade(profile) then
		consumeTutorialBaseUpgrade(profile)
	end

	profile.Data.PostTutorialStage = PostTutorialConfiguration.Stages.Completed
	profile.Data.TutorialVersion = CURRENT_TUTORIAL_VERSION
end

local function reconcileStepWithCurrentState(player: Player, profile: any): number
	local currentStep = getCurrentStep(player)

	-- If the player left during step 4, the carried brainrot is gone on next join,
	-- so we must return them to step 3 to pick one up again.
	if currentStep == 4 and not hasBrainrotInHandOrInventory(player) then
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
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return false
	end

	ensureTutorialFlags(profile)

	return getCurrentStep(player) == 10
		and upgradeId == TutorialConfiguration.TutorialCharacterUpgradeId
		and profile.Data.TutorialFreeCharacterUpgradeConsumed ~= true
		and not hasSpecificCharacterUpgrade(profile, upgradeId)
end

function TutorialService:IsTutorialBaseUpgradeFreeAvailable(player: Player): boolean
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return false
	end

	ensureTutorialFlags(profile)

	return profile.Data.TutorialFreeBaseUpgradeConsumed ~= true
		and not hasBaseSlotUpgrade(profile)
end

function TutorialService:SyncPlayer(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		local step = getCurrentStep(player)
		syncStepAttribute(player, step)
		syncPostTutorialStageAttribute(player, PostTutorialConfiguration.Stages.Completed)
		AnalyticsFunnelsService:SyncTutorial(player, step)
		return step
	end

	migrateTutorialProgress(profile)

	local step = reconcileStepWithCurrentState(player, profile)
	syncStepAttribute(player, step)
	syncPostTutorialStageAttribute(player, PostTutorialConfiguration.Stages.Completed)
	AnalyticsFunnelsService:SyncTutorial(player, step)

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

	setCurrentStep(player, profile, targetStep)
	self:EvaluateCurrentStep(player)
	return true
end

function TutorialService:EvaluatePostTutorial(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return
	end

	setCurrentPostTutorialStage(player, profile, PostTutorialConfiguration.Stages.Completed)
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
		if currentStep >= TutorialConfiguration.FinalStep then
			self:EvaluatePostTutorial(player)
			return
		end

		local rootPart = getRootPart(player)
		local nextStep: number? = nil

		if currentStep == 1 then
			if rootPart and isInsideAnyMineZone(rootPart.Position) then
				nextStep = 2
			end
		elseif currentStep == 3 then
			if hasBrainrotInHandOrInventory(player) then
				nextStep = 4
			end
		elseif currentStep == 5 then
			if hasPlacedBrainrot(player) then
				nextStep = 6
			end
		elseif currentStep == 6 then
			if getCurrentMoney(player, profile) >= TutorialConfiguration.CashGoal then
				nextStep = 7
			end
		elseif currentStep == 8 then
			if hasPurchasedAdditionalBomb(player, profile) then
				nextStep = 9
			end
		elseif currentStep == 10 then
			if hasSpecificCharacterUpgrade(profile, TutorialConfiguration.TutorialCharacterUpgradeId) then
				consumeTutorialCharacterUpgrade(profile)
				nextStep = 11
			end
		elseif currentStep == 11 then
			if isNearBaseUpgradeButton(player) then
				if hasBaseSlotUpgrade(profile) then
					consumeTutorialBaseUpgrade(profile)
					nextStep = 13
				else
					nextStep = 12
				end
			end
		elseif currentStep == 12 then
			if hasBaseSlotUpgrade(profile) then
				consumeTutorialBaseUpgrade(profile)
				nextStep = 13
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
	if getCurrentStep(player) == 1 then
		self:AdvanceToStep(player, 2)
	end
end

function TutorialService:HandleBombThrown(player: Player)
	if getCurrentStep(player) == 2 then
		self:AdvanceToStep(player, 3)
	end
end

function TutorialService:HandleBrainrotPickedUp(player: Player)
	if getCurrentStep(player) == 3 then
		self:AdvanceToStep(player, 4)
	else
		self:EvaluateCurrentStep(player)
	end
end

function TutorialService:HandleMineZoneExited(player: Player)
	if getCurrentStep(player) == 4 then
		self:AdvanceToStep(player, 5)
	end
end

function TutorialService:HandleBrainrotPlaced(player: Player)
	if getCurrentStep(player) == 5 then
		self:AdvanceToStep(player, 6)
	else
		self:EvaluateCurrentStep(player)
	end
end

function TutorialService:HandleMoneyChanged(player: Player)
	self:EvaluateCurrentStep(player)
end

function TutorialService:HandleBombPurchased(player: Player)
	if getCurrentStep(player) == 8 then
		self:AdvanceToStep(player, 9)
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

	if type(_upgradeId) == "string" and _upgradeId == TutorialConfiguration.TutorialCharacterUpgradeId then
		consumeTutorialCharacterUpgrade(profile)
	end

	if getCurrentStep(player) == 10 and type(_upgradeId) == "string" and _upgradeId == TutorialConfiguration.TutorialCharacterUpgradeId then
		self:AdvanceToStep(player, 11)
		return
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

	if getCurrentStep(player) == 12 then
		self:AdvanceToStep(player, 13)
		return
	end

	self:EvaluatePostTutorial(player)
	self:EvaluateCurrentStep(player)
end

function TutorialService:ReportAction(player: Player, actionId: string)
	local currentStep = getCurrentStep(player)

	if actionId == "BackPressed" then
		if currentStep == 4 then
			self:AdvanceToStep(player, 5)
		end
	elseif actionId == "ShopOpened" then
		if currentStep == 7 then
			self:AdvanceToStep(player, 8)
		end
	elseif actionId == "UpgradesOpened" then
		if currentStep == 9 then
			self:AdvanceToStep(player, 10)
		end
	end
end

function TutorialService:Init(controllers)
	PlayerController = controllers.PlayerController

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
end

return TutorialService
