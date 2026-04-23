--!strict
-- LOCATION: ServerScriptService/Controllers/PickaxeController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PickaxeController = {}

-- [ MODULES ]
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local BadgeManager = require(ServerScriptService.Modules.BadgeManager)
local TutorialService = require(ServerScriptService.Modules.TutorialService)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local PlayerController -- Lazy Load
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

-- [ ASSETS ]
local PickaxesFolder = ReplicatedStorage:WaitForChild("Pickaxes")
local Events = ReplicatedStorage:WaitForChild("Events")
local ActionEvent: RemoteEvent
local NotificationEvent: RemoteEvent
local GetDataFunction: RemoteFunction
local equipStates: {[Player]: {InProgress: boolean, PendingPickaxe: string?}} = {}

local function getSortedPickaxes()
	local sortedPickaxes = {}
	for id, data in pairs(BombsConfigurations.Bombs) do
		table.insert(sortedPickaxes, {Id = id, Price = data.Price or 0})
	end
	table.sort(sortedPickaxes, function(a, b)
		if a.Price == b.Price then
			return a.Id < b.Id
		end
		return a.Price < b.Price
	end)
	return sortedPickaxes
end

local function getBombTier(pickaxeName: string): number
	return tonumber(pickaxeName:match("(%d+)")) or 0
end

local function ensureOwnedPickaxes(profile)
	if type(profile.Data.OwnedPickaxes) ~= "table" then
		profile.Data.OwnedPickaxes = { ["Bomb 1"] = true }
	end
end

local function getNextPickaxeToBuy(profile): string?
	ensureOwnedPickaxes(profile)

	for _, pickaxe in ipairs(getSortedPickaxes()) do
		if not profile.Data.OwnedPickaxes[pickaxe.Id] then
			return pickaxe.Id
		end
	end

	return nil
end

local function unlockPickaxeThroughTier(profile, targetPickaxeName: string)
	local targetTier = getBombTier(targetPickaxeName)
	if targetTier <= 0 then
		return
	end

	ensureOwnedPickaxes(profile)
	for pickaxeName in pairs(BombsConfigurations.Bombs) do
		if getBombTier(pickaxeName) <= targetTier then
			profile.Data.OwnedPickaxes[pickaxeName] = true
		end
	end
end

local function refreshPickaxeUi(player: Player)
	local updateUIEvent = Events:FindFirstChild("UpdatePickaxeUI")
	if updateUIEvent and updateUIEvent:IsA("RemoteEvent") then
		updateUIEvent:FireClient(player)
	end
end

local function finalizeBombOwnership(player: Player, profile, pickaxeName: string, unlockThroughTierPurchase: boolean?): boolean
	local config = BombsConfigurations.Bombs[pickaxeName]
	if not config then
		return false
	end

	ensureOwnedPickaxes(profile)
	if unlockThroughTierPurchase == true then
		unlockPickaxeThroughTier(profile, pickaxeName)
	else
		profile.Data.OwnedPickaxes[pickaxeName] = true
	end
	profile.Data.EquippedPickaxe = pickaxeName

	PickaxeController.EquipPickaxe(player, pickaxeName)
	BadgeManager:EvaluatePickaxeMilestones(player, pickaxeName)
	refreshPickaxeUi(player)
	return true
end

-- [ CORE LOGIC ]
local function clearExistingPickaxes(player: Player)
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")

	local function removeIfPickaxe(container: Instance?)
		if not container then return end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and BombsConfigurations.Bombs[child.Name] then
				child:Destroy()
			end
		end
	end

	removeIfPickaxe(character)
	removeIfPickaxe(backpack)
	removeIfPickaxe(starterGear)
end

local function getEquipState(player: Player): {InProgress: boolean, PendingPickaxe: string?}
	local state = equipStates[player]
	if state then
		return state
	end

	state = {
		InProgress = false,
		PendingPickaxe = nil,
	}
	equipStates[player] = state
	return state
end

local function getPreferredPickaxeName(player: Player): string
	local profile = PlayerController and PlayerController:GetProfile(player)
	local equippedPickaxe = profile and profile.Data and profile.Data.EquippedPickaxe
	if type(equippedPickaxe) == "string" and BombsConfigurations.Bombs[equippedPickaxe] then
		return equippedPickaxe
	end

	return "Bomb 1"
end

local function collectBombTools(container: Instance?): {Tool}
	local tools = {}
	if not container then
		return tools
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and BombsConfigurations.Bombs[child.Name] then
			table.insert(tools, child)
		end
	end

	return tools
end

local function findNamedBombTool(tools: {Tool}, preferredPickaxeName: string?): Tool?
	if preferredPickaxeName == nil then
		return nil
	end

	for _, tool in ipairs(tools) do
		if tool.Name == preferredPickaxeName then
			return tool
		end
	end

	return nil
end

local function deduplicatePickaxes(player: Player, preferredPickaxeName: string?): Tool?
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")
	local characterTools = collectBombTools(character)
	local backpackTools = collectBombTools(backpack)
	local keptActiveTool = findNamedBombTool(characterTools, preferredPickaxeName)
		or findNamedBombTool(backpackTools, preferredPickaxeName)
		or characterTools[1]
		or backpackTools[1]

	for _, tool in ipairs(characterTools) do
		if tool ~= keptActiveTool then
			tool:Destroy()
		end
	end

	for _, tool in ipairs(backpackTools) do
		if tool ~= keptActiveTool then
			tool:Destroy()
		end
	end

	if starterGear then
		local keptStarterGear = false
		for _, child in ipairs(starterGear:GetChildren()) do
			if child:IsA("Tool") and BombsConfigurations.Bombs[child.Name] then
				local matchesPreferred = preferredPickaxeName == nil or child.Name == preferredPickaxeName
				if not keptStarterGear and matchesPreferred then
					keptStarterGear = true
				else
					child:Destroy()
				end
			end
		end

		if not keptStarterGear and preferredPickaxeName and BombsConfigurations.Bombs[preferredPickaxeName] and keptActiveTool then
			local pickaxeTemplate = PickaxesFolder:FindFirstChild(preferredPickaxeName)
			if pickaxeTemplate and pickaxeTemplate:IsA("Tool") then
				local starterClone = pickaxeTemplate:Clone()
				starterClone.CanBeDropped = false
				local config = BombsConfigurations.Bombs[preferredPickaxeName]
				if config and config.ImageId then
					starterClone.TextureId = config.ImageId
				end
				starterClone.Parent = starterGear
			end
		end
	end

	return keptActiveTool
end

local function getCurrentBombTool(player: Player): Tool?
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and BombsConfigurations.Bombs[child.Name] then
				return child
			end
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and BombsConfigurations.Bombs[child.Name] then
				return child
			end
		end
	end

	return nil
end

local function resolvePreferredBombTool(player: Player, preferredPickaxeName: string?): Tool?
	local resolvedPreferred = preferredPickaxeName
	if type(resolvedPreferred) ~= "string" or not BombsConfigurations.Bombs[resolvedPreferred] then
		resolvedPreferred = getPreferredPickaxeName(player)
	end

	return deduplicatePickaxes(player, resolvedPreferred) or getCurrentBombTool(player)
end

local function moveBombToFirstSlot(player: Player, bombTool: Tool, shouldEquipAfter: boolean): Tool?
	local backpack = player:FindFirstChild("Backpack")
	if not backpack or not bombTool.Parent then
		return nil
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if bombTool.Parent == character then
		return bombTool
	end

	if bombTool.Parent ~= backpack then
		return nil
	end

	local otherTools = {}
	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") and child ~= bombTool then
			table.insert(otherTools, child)
		end
	end

	local tempFolder = Instance.new("Folder")
	bombTool.Parent = tempFolder
	for _, otherTool in ipairs(otherTools) do
		otherTool.Parent = tempFolder
	end

	bombTool.Parent = backpack
	for _, otherTool in ipairs(otherTools) do
		otherTool.Parent = backpack
	end
	tempFolder:Destroy()

	if shouldEquipAfter and humanoid and humanoid.Parent and bombTool.Parent == backpack then
		humanoid:EquipTool(bombTool)
	end

	return bombTool
end

local function performEquipPickaxe(player: Player, pickaxeName: string)
	local pickaxeTemplate = PickaxesFolder:FindFirstChild(pickaxeName)
	if not pickaxeTemplate or not pickaxeTemplate:IsA("Tool") then
		warn("[PickaxeController] Pickaxe tool not found in ReplicatedStorage: " .. tostring(pickaxeName))
		return
	end

	clearExistingPickaxes(player)
	task.wait()

	local newPickaxe = pickaxeTemplate:Clone() :: Tool
	newPickaxe.CanBeDropped = false

	local config = BombsConfigurations.Bombs[pickaxeName]
	if config and config.ImageId then
		newPickaxe.TextureId = config.ImageId
	end

	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear then
		local gearPickaxe = newPickaxe:Clone()
		gearPickaxe.Parent = starterGear
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return
	end

	newPickaxe.Parent = backpack
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	moveBombToFirstSlot(player, newPickaxe, humanoid ~= nil)
	deduplicatePickaxes(player, pickaxeName)
end

function PickaxeController.EnsureBombFirstSlot(player: Player)
	local equippedPickaxe = getPreferredPickaxeName(player)
	local bombTool = resolvePreferredBombTool(player, equippedPickaxe)

	if not bombTool and type(equippedPickaxe) == "string" and BombsConfigurations.Bombs[equippedPickaxe] then
		PickaxeController.EquipPickaxe(player, equippedPickaxe)
		return
	end

	if not bombTool then
		return
	end

	if bombTool.Parent ~= player.Character then
		moveBombToFirstSlot(player, bombTool, false)
	end
end

function PickaxeController.EnsureBombEquipped(player: Player)
	local equippedPickaxe = getPreferredPickaxeName(player)
	local bombTool = resolvePreferredBombTool(player, equippedPickaxe)

	if not bombTool and type(equippedPickaxe) == "string" and BombsConfigurations.Bombs[equippedPickaxe] then
		PickaxeController.EquipPickaxe(player, equippedPickaxe)
		return
	end

	if not bombTool then
		return
	end

	if bombTool.Parent == player.Character then
		return
	end

	moveBombToFirstSlot(player, bombTool, true)
end

function PickaxeController.GetPreferredPickaxeName(player: Player): string
	return getPreferredPickaxeName(player)
end

function PickaxeController.ResolvePreferredBombTool(player: Player): Tool?
	return resolvePreferredBombTool(player, getPreferredPickaxeName(player))
end

function PickaxeController.EquipPickaxe(player: Player, pickaxeName: string)
	if type(pickaxeName) ~= "string" or not BombsConfigurations.Bombs[pickaxeName] then
		return
	end

	local state = getEquipState(player)
	state.PendingPickaxe = pickaxeName

	if state.InProgress then
		return
	end

	state.InProgress = true

	while player.Parent do
		local pendingPickaxe = state.PendingPickaxe
		if not pendingPickaxe then
			break
		end

		state.PendingPickaxe = nil
		performEquipPickaxe(player, pendingPickaxe)
	end

	state.InProgress = false
	if not player.Parent then
		equipStates[player] = nil
	end
end

function PickaxeController.HandlePickaxeAction(player: Player, pickaxeName: string)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	ensureOwnedPickaxes(profile)
	if not profile.Data.EquippedPickaxe then
		profile.Data.EquippedPickaxe = "Bomb 1"
	end

	local config = BombsConfigurations.Bombs[pickaxeName]
	if not config then return end

	local nextToBuy = getNextPickaxeToBuy(profile)

	local isOwned = profile.Data.OwnedPickaxes[pickaxeName]

	if isOwned then
		if profile.Data.EquippedPickaxe ~= pickaxeName then
			profile.Data.EquippedPickaxe = pickaxeName
			PickaxeController.EquipPickaxe(player, pickaxeName)
			if NotificationEvent then
				NotificationEvent:FireClient(player, "Equipped " .. config.DisplayName .. "!", "Success")
			end
			PickaxeController.RefreshUI(player)
		end
		return
	end

	AnalyticsFunnelsService:HandleBombPurchaseRequested(player, pickaxeName)

	if pickaxeName ~= nextToBuy then
		if NotificationEvent then 
			NotificationEvent:FireClient(player, "You must unlock the previous pickaxes first!", "Error") 
		end
		AnalyticsFunnelsService:LogFailure(player, "locked_by_previous_bomb", {
			zone = "base",
			target_bomb_tier = getBombTier(pickaxeName),
		})
		return
	end

	-- BUY LOGIC
	local price = config.Price
	AnalyticsEconomyService:FlushBombIncome(player)
	if PlayerController:DeductMoney(player, price) then
		AnalyticsEconomyService:LogCashSink(player, price, TRANSACTION_TYPES.Shop, `Bomb:{pickaxeName}`, {
			feature = "bomb_shop",
			content_id = pickaxeName,
			context = "shop",
			bomb_tier = getBombTier(pickaxeName),
		})

		finalizeBombOwnership(player, profile, pickaxeName, false)

		if NotificationEvent then 
			NotificationEvent:FireClient(player, "Purchased " .. config.DisplayName .. "!", "Success") 
		end
		AnalyticsFunnelsService:HandleBombPurchased(player, pickaxeName)
		TutorialService:HandleBombPurchased(player)
	else
		if NotificationEvent then 
			NotificationEvent:FireClient(player, "Not enough money!", "Error") 
		end
		AnalyticsFunnelsService:LogFailure(player, "not_enough_money", {
			zone = "base",
			funnel = "BombShopConversion",
			target_bomb_tier = getBombTier(pickaxeName),
		})
	end
end

function PickaxeController.GrantPickaxeByRobux(player: Player, pickaxeName: string): boolean
	local profile = PlayerController:GetProfile(player)
	local config = BombsConfigurations.Bombs[pickaxeName]
	if not profile or not config then
		return false
	end

	finalizeBombOwnership(player, profile, pickaxeName, true)
	TutorialService:HandleBombPurchased(player)

	if NotificationEvent then
		NotificationEvent:FireClient(player, "Purchased " .. config.DisplayName .. "!", "Success")
	end

	return true
end

function PickaxeController:PurchaseBombForTutorial(player: Player, pickaxeName: string): boolean
	local profile = PlayerController:GetProfile(player)
	local config = BombsConfigurations.Bombs[pickaxeName]
	if not profile or not config then
		return false
	end

	ensureOwnedPickaxes(profile)
	if profile.Data.OwnedPickaxes[pickaxeName] == true then
		TutorialService:HandleBombPurchased(player)
		refreshPickaxeUi(player)
		return true
	end

	local nextToBuy = getNextPickaxeToBuy(profile)
	if nextToBuy ~= pickaxeName then
		return false
	end

	local price = tonumber(config.Price) or 0
	if price > 0 then
		AnalyticsEconomyService:FlushBombIncome(player)
		if PlayerController:DeductMoney(player, price) then
			AnalyticsEconomyService:LogCashSink(player, price, TRANSACTION_TYPES.Shop, `Bomb:{pickaxeName}`, {
				feature = "bomb_shop",
				content_id = pickaxeName,
				context = "tutorial_auto_buy",
				bomb_tier = getBombTier(pickaxeName),
			})
		end
	end

	if not finalizeBombOwnership(player, profile, pickaxeName, false) then
		return false
	end

	if NotificationEvent then
		NotificationEvent:FireClient(player, "Purchased " .. config.DisplayName .. "!", "Success")
	end

	AnalyticsFunnelsService:HandleBombTutorialAutoPurchased(player)
	TutorialService:HandleBombPurchased(player)
	return true
end

function PickaxeController.RefreshUI(player: Player)
	refreshPickaxeUi(player)
end

function PickaxeController.UnlockPickaxeForTesting(player: Player, pickaxeName: string, equipAfter: boolean?): boolean
	local profile = PlayerController:GetProfile(player)
	if not profile or not BombsConfigurations.Bombs[pickaxeName] then
		return false
	end

	if type(profile.Data.OwnedPickaxes) ~= "table" then
		profile.Data.OwnedPickaxes = { ["Bomb 1"] = true }
	end

	profile.Data.OwnedPickaxes[pickaxeName] = true
	if equipAfter == true then
		profile.Data.EquippedPickaxe = pickaxeName
		PickaxeController.EquipPickaxe(player, pickaxeName)
	else
		PickaxeController.EnsureBombFirstSlot(player)
	end

	PickaxeController.RefreshUI(player)
	return true
end

function PickaxeController.UnlockAllPickaxesForTesting(player: Player, equipHighest: boolean?): boolean
	local profile = PlayerController:GetProfile(player)
	if not profile then
		return false
	end

	if type(profile.Data.OwnedPickaxes) ~= "table" then
		profile.Data.OwnedPickaxes = { ["Bomb 1"] = true }
	end

	local highestPickaxe = "Bomb 1"
	local highestPrice = -1

	for pickaxeName, config in pairs(BombsConfigurations.Bombs) do
		profile.Data.OwnedPickaxes[pickaxeName] = true
		if (config.Price or 0) > highestPrice then
			highestPrice = config.Price or 0
			highestPickaxe = pickaxeName
		end
	end

	if equipHighest == true then
		profile.Data.EquippedPickaxe = highestPickaxe
		PickaxeController.EquipPickaxe(player, highestPickaxe)
	else
		PickaxeController.EnsureBombFirstSlot(player)
	end

	PickaxeController.RefreshUI(player)
	return true
end

function PickaxeController.ResetPickaxesForTesting(player: Player): boolean
	local profile = PlayerController:GetProfile(player)
	if not profile then
		return false
	end

	profile.Data.OwnedPickaxes = { ["Bomb 1"] = true }
	profile.Data.EquippedPickaxe = "Bomb 1"
	PickaxeController.EquipPickaxe(player, "Bomb 1")
	PickaxeController.RefreshUI(player)
	return true
end

-- [ INITIALIZATION ]
function PickaxeController:Init(controllers)
	PlayerController = controllers.PlayerController

	if not Events:FindFirstChild("RequestPickaxeAction") then
		local re = Instance.new("RemoteEvent")
		re.Name = "RequestPickaxeAction"
		re.Parent = Events
	end

	if not Events:FindFirstChild("UpdatePickaxeUI") then
		local re = Instance.new("RemoteEvent")
		re.Name = "UpdatePickaxeUI"
		re.Parent = Events
	end

	if not Events:FindFirstChild("GetPickaxeData") then
		local rf = Instance.new("RemoteFunction")
		rf.Name = "GetPickaxeData"
		rf.Parent = Events
	end

	ActionEvent = Events:FindFirstChild("RequestPickaxeAction") :: RemoteEvent
	NotificationEvent = Events:FindFirstChild("ShowNotification") :: RemoteEvent
	GetDataFunction = Events:FindFirstChild("GetPickaxeData") :: RemoteFunction

	ActionEvent.OnServerEvent:Connect(function(player, pickaxeName)
		if type(pickaxeName) == "string" then
			PickaxeController.HandlePickaxeAction(player, pickaxeName)
		end
	end)

	-- ## FIXED: Wait for data to load before sending to client UI ##
	GetDataFunction.OnServerInvoke = function(player)
		local profile = PlayerController:GetProfile(player)
		local retries = 0

		-- Wait up to 5 seconds for the profile to exist
		while not profile and retries < 50 do
			task.wait(0.1)
			profile = PlayerController:GetProfile(player)
			retries += 1
		end

		if profile then
			ensureOwnedPickaxes(profile)
			return {
				OwnedPickaxes = profile.Data.OwnedPickaxes,
				EquippedPickaxe = profile.Data.EquippedPickaxe or "Bomb 1",
				NextPickaxeToBuy = getNextPickaxeToBuy(profile),
			}
		end

		-- Ultimate fallback if data utterly fails to load
		return {
			OwnedPickaxes = { ["Bomb 1"] = true },
			EquippedPickaxe = "Bomb 1",
			NextPickaxeToBuy = "Bomb 2",
		}
	end

	print("[PickaxeController] Initialized")
end

function PickaxeController:Start()
	local function grantPickaxe(player: Player)
		local function tryEquip()
			local profile = PlayerController:GetProfile(player)
			local retries = 0

			while not profile and retries < 20 do
				task.wait(0.5)
				profile = PlayerController:GetProfile(player)
				retries += 1
			end

			if profile then
				local equipped = profile.Data.EquippedPickaxe or "Bomb 1"
				PickaxeController.EquipPickaxe(player, equipped)
			end
		end

		player.CharacterAdded:Connect(function(char)
			task.wait(0.2) 
			tryEquip()
		end)

		if player.Character then
			task.wait(0.2)
			tryEquip()
		end
	end

	Players.PlayerAdded:Connect(grantPickaxe)
	for _, p in ipairs(Players:GetPlayers()) do grantPickaxe(p) end

	Players.PlayerRemoving:Connect(function(player)
		equipStates[player] = nil
	end)
end

return PickaxeController
