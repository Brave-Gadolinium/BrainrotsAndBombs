--!strict
-- LOCATION: ServerScriptService/Controllers/PickaxeController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PickaxeController = {}

-- [ MODULES ]
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local BadgeManager = require(ServerScriptService.Modules.BadgeManager)
local PlayerController -- Lazy Load

-- [ ASSETS ]
local PickaxesFolder = ReplicatedStorage:WaitForChild("Pickaxes")
local Events = ReplicatedStorage:WaitForChild("Events")
local ActionEvent: RemoteEvent
local NotificationEvent: RemoteEvent
local GetDataFunction: RemoteFunction

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

function PickaxeController.EquipPickaxe(player: Player, pickaxeName: string)
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

	local character = player.Character
	if character then
		newPickaxe.Parent = character
	else
		local backpack = player:FindFirstChild("Backpack")
		if backpack then newPickaxe.Parent = backpack end
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

	if pickaxeName ~= nextToBuy then
		if NotificationEvent then 
			NotificationEvent:FireClient(player, "You must unlock the previous pickaxes first!", "Error") 
		end
		return
	end

	-- BUY LOGIC
	local price = config.Price
	if PlayerController:DeductMoney(player, price) then
		profile.Data.OwnedPickaxes[pickaxeName] = true
		profile.Data.EquippedPickaxe = pickaxeName -- Auto-Equip the new best pickaxe!

		PickaxeController.EquipPickaxe(player, pickaxeName)
		BadgeManager:EvaluatePickaxeMilestones(player, pickaxeName)

		if NotificationEvent then 
			NotificationEvent:FireClient(player, "Purchased " .. config.DisplayName .. "!", "Success") 
		end

		local UpdateUIEvent = Events:FindFirstChild("UpdatePickaxeUI")
		if UpdateUIEvent and UpdateUIEvent:IsA("RemoteEvent") then
			UpdateUIEvent:FireClient(player)
		end
	else
		if NotificationEvent then 
			NotificationEvent:FireClient(player, "Not enough money!", "Error") 
		end
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
end

return PickaxeController
