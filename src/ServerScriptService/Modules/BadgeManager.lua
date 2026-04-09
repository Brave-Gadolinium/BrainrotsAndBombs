--!strict
-- LOCATION: ServerScriptService/Modules/BadgeManager

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BadgeConfigurations = require(ServerScriptService.Modules.BadgeConfigurations)
local TutorialConfiguration = require(game:GetService("ReplicatedStorage").Modules.TutorialConfiguration)

local BadgeManager = {}
local bottomTouchConnections: {[BasePart]: RBXScriptConnection} = {}
local deepExplorerDescendantConnection: RBXScriptConnection? = nil
local deepExplorerAwardTimestamps: {[Player]: number} = {}
local DEEP_EXPLORER_TOUCH_DEBOUNCE = 1

local function getBadgeDefinition(badgeKey: string)
	return BadgeConfigurations.Badges[badgeKey]
end

local function getPlayerFromTouchedPart(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function connectBottomTouch(self, bottomPart: BasePart)
	if bottomTouchConnections[bottomPart] then
		return
	end

	bottomTouchConnections[bottomPart] = bottomPart.Touched:Connect(function(hit)
		local player = getPlayerFromTouchedPart(hit)
		if not player then
			return
		end

		local now = os.clock()
		local lastAwardAt = deepExplorerAwardTimestamps[player]
		if lastAwardAt and (now - lastAwardAt) < DEEP_EXPLORER_TOUCH_DEBOUNCE then
			return
		end

		deepExplorerAwardTimestamps[player] = now
		self:AwardBadge(player, "DeepExplorer")
	end)
end

local function connectDeepExplorerTouch(self)
	local foundBottomPart = false

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "Bottom" then
			foundBottomPart = true
			connectBottomTouch(self, descendant)
		end
	end

	if not foundBottomPart then
		warn("[BadgeManager] No Bottom BasePart found in Workspace, waiting for it to appear.")
	end

	if deepExplorerDescendantConnection then
		deepExplorerDescendantConnection:Disconnect()
	end

	deepExplorerDescendantConnection = Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant.Name == "Bottom" then
			connectBottomTouch(self, descendant)
		end
	end)
end

local function canAwardBadge(player: Player, badgeKey: string): (boolean, string?)
	local badgeDefinition = getBadgeDefinition(badgeKey)
	if not badgeDefinition then
		return false, "UnknownBadge"
	end

	if type(badgeDefinition.Id) ~= "number" or badgeDefinition.Id <= 0 then
		return false, "BadgeIdNotConfigured"
	end

	local success, hasBadge = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, badgeDefinition.Id)
	end)

	if not success then
		return false, "BadgeCheckFailed"
	end

	if hasBadge then
		return false, "AlreadyOwned"
	end

	return true, nil
end

function BadgeManager:AwardBadge(player: Player, badgeKey: string): (boolean, string?)
	local badgeDefinition = getBadgeDefinition(badgeKey)
	if not badgeDefinition then
		return false, "UnknownBadge"
	end

	local canAward, reason = canAwardBadge(player, badgeKey)
	if not canAward then
		return false, reason
	end

	local success, result = pcall(function()
		BadgeService:AwardBadge(player.UserId, badgeDefinition.Id)
		return true
	end)

	if not success then
		warn("[BadgeManager] Failed to award badge:", badgeKey, result)
		return false, "AwardFailed"
	end

	return true, nil
end

function BadgeManager:AwardWelcome(player: Player)
	return self:AwardBadge(player, "WelcomeToTheMines")
end

function BadgeManager:EvaluateMoneyMilestones(player: Player, totalMoney: number)
	if totalMoney >= 1 then
		self:AwardBadge(player, "FirstProfit")
	end

	if totalMoney >= 1_000_000 then
		self:AwardBadge(player, "Millionaire")
	end
end

function BadgeManager:EvaluatePickaxeMilestones(player: Player, pickaxeName: string)
	self:AwardBadge(player, "BombOwner")
	local pickaxeLevel = tonumber(string.match(pickaxeName, "%d+"))
	if not pickaxeLevel then
		return
	end

	if pickaxeLevel >= 5 then
		self:AwardBadge(player, "BombMedium")
	end

	if pickaxeLevel >= 10 then
		self:AwardBadge(player, "BombPro")
	end

	if pickaxeLevel >= 15 then
		self:AwardBadge(player, "BombMaster")
	end
end

function BadgeManager:EvaluateOnboardingStep(player: Player, onboardingStep: number)
	local finalStep = TutorialConfiguration.FinalStep
	if onboardingStep >= finalStep then
		self:AwardBadge(player, "TutorialMaster")
	end
end

function BadgeManager:EvaluateBrainrotMilestones(player: Player, rarity: string?, totalCollected: number?)
	self:AwardBadge(player, "FirstBrainrot")

	if type(totalCollected) == "number" then
		if totalCollected >= 10 then
			self:AwardBadge(player, "BrainrotCollector")
		end

		if totalCollected >= 100 then
			self:AwardBadge(player, "BrainrotEmpire")
		end
	end

	if rarity == "Legendary" then
		self:AwardBadge(player, "FirstLegendary")
	elseif rarity == "Mythic" then
		self:AwardBadge(player, "FirstMythic")
	end
end

function BadgeManager:Start()
	connectDeepExplorerTouch(self)
end

function BadgeManager:GetBadgeDefinition(badgeKey: string)
	return getBadgeDefinition(badgeKey)
end

function BadgeManager:GetAllBadgeDefinitions()
	return BadgeConfigurations.Badges
end

return BadgeManager
