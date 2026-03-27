--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)

type PlayerControllerType = {
	GetProfile: (self: any, player: Player) -> any,
	OnTutorialStepChanged: ((self: any, player: Player, step: number) -> ())?,
}

local TutorialService = {}

local PlayerController: PlayerControllerType? = nil
local reportActionEvent: RemoteEvent? = nil

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

local function setCurrentStep(player: Player, profile: any, step: number)
	local clampedStep = math.clamp(step, 1, TutorialConfiguration.FinalStep)
	profile.Data.OnboardingStep = clampedStep
	syncStepAttribute(player, clampedStep)

	if PlayerController and PlayerController.OnTutorialStepChanged then
		PlayerController:OnTutorialStepChanged(player, clampedStep)
	end
end

function TutorialService:GetCurrentStep(player: Player): number
	return getCurrentStep(player)
end

function TutorialService:GetStepDefinition(step: number)
	return TutorialConfiguration.Steps[step]
end

function TutorialService:SyncPlayer(player: Player)
	local step = getCurrentStep(player)
	syncStepAttribute(player, step)
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

function TutorialService:EvaluateCurrentStep(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return
	end

	local advanced = true
	while advanced do
		advanced = false

		local currentStep = getCurrentStep(player)
		if currentStep >= TutorialConfiguration.FinalStep then
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
		end

		if nextStep then
			setCurrentStep(player, profile, nextStep)
			advanced = true
		end
	end
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

	reportActionEvent.OnServerEvent:Connect(function(player, actionId)
		if type(actionId) == "string" then
			self:ReportAction(player, actionId)
		end
	end)
end

return TutorialService
