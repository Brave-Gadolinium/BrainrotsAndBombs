--!strict
-- LOCATION: ServerScriptService/Modules/RebirthSystem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RebirthSystem = {}

-- [ MODULES ]
local PlayerController 
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfigurations)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local SlotManager 
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

-- [ CONFIG ]
local BASE_REBIRTH_COST = 1000000 -- Cost for the first Rebirth in Cash
local REBIRTH_COST_STEP = 500000  -- How much the price increases per Rebirth

-- [ HELPERS ]
function RebirthSystem.GetInfo(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return 0, 0, 0 end

	local reb = profile.Data.Rebirths or 0
	local cost = BASE_REBIRTH_COST + (reb * REBIRTH_COST_STEP)

	local currentMult = 1 + (reb * 0.5)
	local nextMult = 1 + ((reb + 1) * 0.5)

	return cost, currentMult, nextMult
end

-- [ INTERNAL: DO REBIRTH ]
local function executeRebirth(player: Player, profile: any)
	profile.Data.Rebirths += 1
	player:SetAttribute("Rebirths", profile.Data.Rebirths)

	-- Reset Upgrades to 0 using the new Array format and StatId
	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		local statId = config.StatId
		profile.Data[statId] = nil -- Set to nil so it falls back to defaults
		player:SetAttribute(statId, nil)
	end

	-- ## FIXED: Apply physical reset to a base WalkSpeed of 20 ##
	local char = player.Character
	local hum = char and char:FindFirstChild("Humanoid") :: Humanoid
	if hum then hum.WalkSpeed = 20 end

	-- NOTIFICATION
	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")
	if notif then 
		notif:FireClient(player, "Rebirth Successful!", "Success") 
	end

	local updateEvent = Events:FindFirstChild("UpdateRebirthUI")
	if updateEvent then updateEvent:FireClient(player) end

	local UpgradesSystem = require(ServerScriptService.Modules.UpgradesSystem)
	if UpgradesSystem and UpgradesSystem.UpdateClientUI then
		UpgradesSystem.UpdateClientUI(player)
	end

	if SlotManager then
		SlotManager.RefreshAllSlots(player)
	end

	AnalyticsFunnelsService:HandleRebirthSuccess(player, profile.Data.Rebirths)
end

-- [ PUBLIC API ]
function RebirthSystem.ForceRebirth(player: Player)
	local profile = PlayerController:GetProfile(player)
	if profile then
		executeRebirth(player, profile)
	end
end

function RebirthSystem.AttemptRebirth(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	local cost, _, _ = RebirthSystem.GetInfo(player)
	local targetRebirth = (profile.Data.Rebirths or 0) + 1
	AnalyticsFunnelsService:HandleRebirthRequested(player)

	-- Check and deduct money
	AnalyticsEconomyService:FlushBombIncome(player)
	if PlayerController:DeductMoney(player, cost) then
		AnalyticsEconomyService:LogCashSink(player, cost, TRANSACTION_TYPES.Gameplay, `Rebirth:{targetRebirth}`, {
			feature = "rebirth",
			content_id = tostring(targetRebirth),
			context = "base",
		})
		executeRebirth(player, profile)
	else
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local notif = Events and Events:FindFirstChild("ShowNotification")
		if notif then 
			notif:FireClient(player, "Not enough money!", "Error") 
		end
		AnalyticsFunnelsService:LogFailure(player, "not_enough_money", {
			zone = "base",
			funnel = "RebirthConversion",
		})
	end
end

-- [ INIT ]
function RebirthSystem:Init(controllers)
	print("[RebirthSystem] Initialized")
	PlayerController = controllers.PlayerController

	local Modules = ServerScriptService:WaitForChild("Modules")
	SlotManager = require(Modules:WaitForChild("SlotManager"))

	local Events = ReplicatedStorage:WaitForChild("Events")
	if not Events:FindFirstChild("RequestRebirth") then
		local re = Instance.new("RemoteEvent")
		re.Name = "RequestRebirth"
		re.Parent = Events
	end

	if not Events:FindFirstChild("UpdateRebirthUI") then
		local re = Instance.new("RemoteEvent")
		re.Name = "UpdateRebirthUI"
		re.Parent = Events
	end

	Events.RequestRebirth.OnServerEvent:Connect(function(player)
		RebirthSystem.AttemptRebirth(player)
	end)
end

function RebirthSystem:Start() end

return RebirthSystem
