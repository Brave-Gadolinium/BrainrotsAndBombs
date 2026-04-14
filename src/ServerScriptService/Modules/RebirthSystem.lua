--!strict
-- LOCATION: ServerScriptService/Modules/RebirthSystem

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RebirthSystem = {}

local PlayerController
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local MultiplierUtils = require(ReplicatedStorage.Modules.MultiplierUtils)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local RebirthRequirements = require(ReplicatedStorage.Modules.RebirthRequirements)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local SlotManager
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()
local connected = false
local PROTECTED_REBIRTH_RARITIES = {
	Legendary = true,
	Mythic = true,
	Mythical = true,
	Secret = true,
	Brainrotgod = true,
}

export type RebirthEvaluation = {
	targetLevel: number,
	requirement: any?,
	canRebirth: boolean,
	missingMoney: number,
	missingItems: {string},
}

local function getEventsFolder(): Folder
	return ReplicatedStorage:WaitForChild("Events")
end

local function fireNotification(player: Player, message: string, messageType: string)
	local notif = getEventsFolder():FindFirstChild("ShowNotification")
	if notif and notif:IsA("RemoteEvent") then
		notif:FireClient(player, message, messageType)
	end
end

local function getItemDisplayName(itemId: string): string
	local itemData = ItemConfigurations.GetItemData(itemId) :: any
	if itemData and type(itemData.DisplayName) == "string" and itemData.DisplayName ~= "" then
		return itemData.DisplayName
	end

	return itemId
end

local function buildOwnedBrainrotSet(player: Player, profile: any): {[string]: boolean}
	local owned: {[string]: boolean} = {}

	local function mark(itemName: any)
		if type(itemName) == "string" and itemName ~= "" then
			owned[itemName] = true
		end
	end

	local function scanContainer(container: Instance?)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsTemporary") ~= true then
				mark(child:GetAttribute("OriginalName"))
			end
		end
	end

	scanContainer(player:FindFirstChild("Backpack"))
	scanContainer(player.Character)

	local plots = profile and profile.Data and profile.Data.Plots
	if type(plots) == "table" then
		for _, floorData in pairs(plots) do
			if type(floorData) == "table" then
				for _, slotData in pairs(floorData) do
					if type(slotData) == "table" and type(slotData.Item) == "table" then
						mark(slotData.Item.Name)
					end
				end
			end
		end
	end

	return owned
end

local function isProtectedRebirthRarity(rarity: any): boolean
	return type(rarity) == "string" and PROTECTED_REBIRTH_RARITIES[rarity] == true
end

local function filterSavedInventory(profile: any)
	local inventory = profile.Data.Inventory
	if type(inventory) ~= "table" then
		profile.Data.Inventory = {}
		return
	end

	local keptInventory = {}
	for _, itemData in ipairs(inventory) do
		if type(itemData) == "table" and isProtectedRebirthRarity(itemData.Rarity) then
			table.insert(keptInventory, itemData)
		end
	end

	profile.Data.Inventory = keptInventory
end

local function filterSavedPlots(profile: any)
	local plots = profile.Data.Plots
	if type(plots) ~= "table" then
		return
	end

	for _, floorData in pairs(plots) do
		if type(floorData) == "table" then
			for slotName, slotData in pairs(floorData) do
				local isLuckyBlockSlot = type(slotData) == "table"
					and (slotData.ContentType == "LuckyBlock" or slotData.LuckyBlock ~= nil)

				if type(slotData) == "table"
					and not isLuckyBlockSlot
					and type(slotData.Item) == "table"
					and not isProtectedRebirthRarity(slotData.Item.Rarity) then
					floorData[slotName] = {
						Item = nil,
						Level = 1,
						Stored = 0,
					}
				end
			end
		end
	end
end

local function shouldKeepLiveTool(tool: Tool): boolean
	if tool:GetAttribute("IsLuckyBlock") == true then
		return true
	end

	local originalName = tool:GetAttribute("OriginalName")
	if type(originalName) ~= "string" or originalName == "" then
		return true
	end

	return isProtectedRebirthRarity(tool:GetAttribute("Rarity"))
end

local function filterLiveInventoryContainer(container: Instance?)
	if not container then
		return
	end

	local toolsToDestroy = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and not shouldKeepLiveTool(child) then
			table.insert(toolsToDestroy, child)
		end
	end

	for _, tool in ipairs(toolsToDestroy) do
		if tool.Parent then
			tool:Destroy()
		end
	end
end

local function filterLiveInventory(player: Player)
	filterLiveInventoryContainer(player:FindFirstChild("Backpack"))
	filterLiveInventoryContainer(player.Character)
	filterLiveInventoryContainer(player:FindFirstChild("StarterGear"))
end

function RebirthSystem.EvaluateRequirements(player: Player, targetLevel: number?): RebirthEvaluation
	local profile = PlayerController:GetProfile(player)
	local currentRebirths = profile and profile.Data and tonumber(profile.Data.Rebirths) or 0
	local resolvedTargetLevel = tonumber(targetLevel) or (currentRebirths + 1)
	local requirement = RebirthRequirements.Get(resolvedTargetLevel)

	if not profile or not requirement then
		return {
			targetLevel = resolvedTargetLevel,
			requirement = requirement,
			canRebirth = false,
			missingMoney = 0,
			missingItems = {},
		}
	end

	local money = tonumber(profile.Data.Money) or 0
	local requiredMoney = tonumber(requirement.soft_required) or 0
	local missingMoney = math.max(requiredMoney - money, 0)
	local ownedBrainrots = buildOwnedBrainrotSet(player, profile)
	local missingItems = {}

	for _, itemId in ipairs(requirement.item_required or {}) do
		if type(itemId) == "string" and itemId ~= "" and not ownedBrainrots[itemId] then
			table.insert(missingItems, itemId)
		end
	end

	return {
		targetLevel = resolvedTargetLevel,
		requirement = requirement,
		canRebirth = missingMoney <= 0 and #missingItems == 0,
		missingMoney = missingMoney,
		missingItems = missingItems,
	}
end

function RebirthSystem.GetInfo(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then
		return 0, 0, 0
	end

	local rebirths = tonumber(profile.Data.Rebirths) or 0
	local currentMult = MultiplierUtils.GetRebirthMultiplier(rebirths)
	local nextMult = MultiplierUtils.GetRebirthMultiplier(rebirths + 1)
	local requirement = RebirthRequirements.Get(rebirths + 1)
	local cost = requirement and (tonumber(requirement.soft_required) or 0) or 0

	if not requirement then
		nextMult = currentMult
	end

	return cost, currentMult, nextMult
end

local function executeRebirth(player: Player, profile: any, suppressAnalytics: boolean?)
	profile.Data.Rebirths += 1
	player:SetAttribute("Rebirths", profile.Data.Rebirths)

	local char = player.Character
	local hum = char and char:FindFirstChild("Humanoid") :: Humanoid?
	if hum then
		hum.WalkSpeed = 20 + math.max(0, tonumber(profile.Data.BonusSpeed) or 0)
	end

	filterSavedInventory(profile)
	filterSavedPlots(profile)
	filterLiveInventory(player)

	fireNotification(player, "Rebirth Successful!", "Success")

	local updateEvent = getEventsFolder():FindFirstChild("UpdateRebirthUI")
	if updateEvent and updateEvent:IsA("RemoteEvent") then
		updateEvent:FireClient(player)
	end

	local UpgradesSystem = require(ServerScriptService.Modules.UpgradesSystem)
	if UpgradesSystem and UpgradesSystem.UpdateClientUI then
		UpgradesSystem.UpdateClientUI(player)
	end

	if SlotManager then
		SlotManager.RefreshAllSlots(player)
	end

	if suppressAnalytics ~= true then
		AnalyticsFunnelsService:HandleRebirthSuccess(player, profile.Data.Rebirths)
	end
end

function RebirthSystem.ForceRebirth(player: Player)
	local profile = PlayerController:GetProfile(player)
	if profile then
		executeRebirth(player, profile)
	end
end

function RebirthSystem.ForceRebirthForTesting(player: Player): boolean
	local profile = PlayerController:GetProfile(player)
	if not profile then
		return false
	end

	executeRebirth(player, profile, true)
	return true
end

function RebirthSystem.SetRebirthsForTesting(player: Player, amount: number): boolean
	local profile = PlayerController:GetProfile(player)
	if not profile then
		return false
	end

	profile.Data.Rebirths = math.max(0, math.floor(tonumber(amount) or 0))
	player:SetAttribute("Rebirths", profile.Data.Rebirths)
	RebirthSystem.RefreshUIForTesting(player)
	return true
end

function RebirthSystem.RefreshUIForTesting(player: Player)
	local updateEvent = getEventsFolder():FindFirstChild("UpdateRebirthUI")
	if updateEvent and updateEvent:IsA("RemoteEvent") then
		updateEvent:FireClient(player)
	end
end

function RebirthSystem.AttemptRebirth(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then
		return
	end

	local evaluation = RebirthSystem.EvaluateRequirements(player)
	if not evaluation.requirement then
		fireNotification(player, "Max rebirth reached!", "Error")
		AnalyticsFunnelsService:LogFailure(player, "max_rebirth", {
			zone = "base",
			funnel = "RebirthConversion",
		})
		return
	end

	AnalyticsFunnelsService:HandleRebirthRequested(player)

	if not evaluation.canRebirth then
		if evaluation.missingMoney > 0 and #evaluation.missingItems > 0 then
			local missingNames = {}
			for _, itemId in ipairs(evaluation.missingItems) do
				table.insert(missingNames, getItemDisplayName(itemId))
			end

			fireNotification(
				player,
				`Need ${NumberFormatter.Format(evaluation.missingMoney)} more cash and: {table.concat(missingNames, ", ")}`,
				"Error"
			)
			AnalyticsFunnelsService:LogFailure(player, "rebirth_requirements_missing", {
				zone = "base",
				funnel = "RebirthConversion",
				target_rebirth = evaluation.targetLevel,
			})
			return
		end

		if evaluation.missingMoney > 0 then
			fireNotification(player, `Need ${NumberFormatter.Format(evaluation.missingMoney)} more cash!`, "Error")
			AnalyticsFunnelsService:LogFailure(player, "not_enough_money", {
				zone = "base",
				funnel = "RebirthConversion",
				target_rebirth = evaluation.targetLevel,
			})
			return
		end

		local missingNames = {}
		for _, itemId in ipairs(evaluation.missingItems) do
			table.insert(missingNames, getItemDisplayName(itemId))
		end

		fireNotification(player, table.concat(missingNames, ", "), "Error")
		AnalyticsFunnelsService:LogFailure(player, "missing_brainrots", {
			zone = "base",
			funnel = "RebirthConversion",
			target_rebirth = evaluation.targetLevel,
		})
		return
	end

	local cost = tonumber(evaluation.requirement.soft_required) or 0
	local targetRebirth = evaluation.targetLevel

	AnalyticsEconomyService:FlushBombIncome(player)
	if PlayerController:DeductMoney(player, cost) then
		AnalyticsEconomyService:LogCashSink(player, cost, TRANSACTION_TYPES.Gameplay, `Rebirth:{targetRebirth}`, {
			feature = "rebirth",
			content_id = tostring(targetRebirth),
			context = "base",
		})
		executeRebirth(player, profile)
	else
		fireNotification(player, "Not enough money!", "Error")
		AnalyticsFunnelsService:LogFailure(player, "not_enough_money", {
			zone = "base",
			funnel = "RebirthConversion",
			target_rebirth = targetRebirth,
		})
	end
end

function RebirthSystem:Init(controllers)
	print("[RebirthSystem] Initialized")
	PlayerController = controllers.PlayerController

	local modules = ServerScriptService:WaitForChild("Modules")
	SlotManager = require(modules:WaitForChild("SlotManager"))

	local events = getEventsFolder()
	if not events:FindFirstChild("RequestRebirth") then
		local re = Instance.new("RemoteEvent")
		re.Name = "RequestRebirth"
		re.Parent = events
	end

	if not events:FindFirstChild("UpdateRebirthUI") then
		local re = Instance.new("RemoteEvent")
		re.Name = "UpdateRebirthUI"
		re.Parent = events
	end

	if not connected then
		connected = true
		events.RequestRebirth.OnServerEvent:Connect(function(player)
			RebirthSystem.AttemptRebirth(player)
		end)
	end
end

function RebirthSystem:Start() end

return RebirthSystem
