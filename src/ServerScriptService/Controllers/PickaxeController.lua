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

local function deduplicatePickaxes(player: Player, preferredPickaxeName: string?): Tool?
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")
	local starterGear = player:FindFirstChild("StarterGear")
	local keptActiveTool: Tool? = nil

	local function processContainer(container: Instance?, allowKeep: boolean)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and BombsConfigurations.Bombs[child.Name] then
				local shouldPrefer = preferredPickaxeName ~= nil and child.Name == preferredPickaxeName
				if allowKeep and (not keptActiveTool or shouldPrefer) then
					if keptActiveTool and keptActiveTool ~= child and keptActiveTool.Parent then
						keptActiveTool:Destroy()
					end
					keptActiveTool = child
				else
					child:Destroy()
				end
			end
		end
	end

	processContainer(character, true)
	processContainer(backpack, true)

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

local function moveBombToFirstSlot(player: Player, bombTool: Tool, shouldEquipAfter: boolean): Tool?
	local backpack = player:FindFirstChild("Backpack")
	if not backpack or not bombTool.Parent then
		return nil
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if bombTool.Parent ~= backpack then
		if humanoid and bombTool.Parent == character then
			humanoid:UnequipTools()
			task.wait()
		end

		if not bombTool.Parent then
			return nil
		end

		bombTool.Parent = backpack
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
	local profile = PlayerController and PlayerController:GetProfile(player)
	local equippedPickaxe = profile and profile.Data and profile.Data.EquippedPickaxe or "Bomb 1"
	local bombTool = deduplicatePickaxes(player, equippedPickaxe) or getCurrentBombTool(player)

	if not bombTool and type(equippedPickaxe) == "string" and BombsConfigurations.Bombs[equippedPickaxe] then
		PickaxeController.EquipPickaxe(player, equippedPickaxe)
		return
	end

	if not bombTool then
		return
	end

	moveBombToFirstSlot(player, bombTool, bombTool.Parent == player.Character)
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

	if type(profile.Data.OwnedPickaxes) ~= "table" then
		profile.Data.OwnedPickaxes = { ["Bomb 1"] = true }
	end
	if not profile.Data.EquippedPickaxe then
		profile.Data.EquippedPickaxe = "Bomb 1"
	end

	local config = BombsConfigurations.Bombs[pickaxeName]
	if not config then return end

	-- Enforce Linear Progression
	local sortedPickaxes = {}
	for id, data in pairs(BombsConfigurations.Bombs) do
		table.insert(sortedPickaxes, {Id = id, Price = data.Price})
	end
	table.sort(sortedPickaxes, function(a, b) return a.Price < b.Price end)

	local nextToBuy = nil
	for _, p in ipairs(sortedPickaxes) do
		if not profile.Data.OwnedPickaxes[p.Id] then
			nextToBuy = p.Id
			break
		end
	end

	local isOwned = profile.Data.OwnedPickaxes[pickaxeName]

	if isOwned then
		return
	end

	AnalyticsFunnelsService:HandleBombPurchaseRequested(player, pickaxeName)

	if pickaxeName ~= nextToBuy then
		if NotificationEvent then 
			NotificationEvent:FireClient(player, "You must unlock the previous pickaxes first!", "Error") 
		end
		AnalyticsFunnelsService:LogFailure(player, "locked_by_previous_bomb", {
			zone = "base",
			target_bomb_tier = tonumber(pickaxeName:match("(%d+)")) or 0,
		})
		return
	end

	-- BUY LOGIC
	local price = config.Price
	AnalyticsEconomyService:FlushBombIncome(player)
	if PlayerController:DeductMoney(player, price) then
		profile.Data.OwnedPickaxes[pickaxeName] = true
		profile.Data.EquippedPickaxe = pickaxeName -- Auto-Equip the new best pickaxe!
		AnalyticsEconomyService:LogCashSink(player, price, TRANSACTION_TYPES.Shop, `Bomb:{pickaxeName}`, {
			feature = "bomb_shop",
			content_id = pickaxeName,
			context = "shop",
			bomb_tier = tonumber(pickaxeName:match("(%d+)")) or 0,
		})

		PickaxeController.EquipPickaxe(player, pickaxeName)
		BadgeManager:EvaluatePickaxeMilestones(player, pickaxeName)

		if NotificationEvent then 
			NotificationEvent:FireClient(player, "Purchased " .. config.DisplayName .. "!", "Success") 
		end
		AnalyticsFunnelsService:HandleBombPurchased(player, pickaxeName)
		TutorialService:HandleBombPurchased(player)

		local UpdateUIEvent = Events:FindFirstChild("UpdatePickaxeUI")
		if UpdateUIEvent and UpdateUIEvent:IsA("RemoteEvent") then
			UpdateUIEvent:FireClient(player)
		end
	else
		if NotificationEvent then 
			NotificationEvent:FireClient(player, "Not enough money!", "Error") 
		end
		AnalyticsFunnelsService:LogFailure(player, "not_enough_money", {
			zone = "base",
			funnel = "BombShopConversion",
			target_bomb_tier = tonumber(pickaxeName:match("(%d+)")) or 0,
		})
	end
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
			-- Guarantee the data table exists just in case
			if type(profile.Data.OwnedPickaxes) ~= "table" then
				profile.Data.OwnedPickaxes = { ["Bomb 1"] = true }
			end
			return profile.Data.OwnedPickaxes
		end

		-- Ultimate fallback if data utterly fails to load
		return { ["Bomb 1"] = true }
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
