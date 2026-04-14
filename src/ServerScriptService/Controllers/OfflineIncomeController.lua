--!strict
-- LOCATION: ServerScriptService/Controllers/OfflineIncomeController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local OfflineIncomeConfiguration = require(ReplicatedStorage.Modules.OfflineIncomeConfiguration)
local IncomeCalculationUtils = require(ReplicatedStorage.Modules.IncomeCalculationUtils)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)

local OfflineIncomeController = {}

type OfflineIncomeData = {
	PendingBaseAmount: number,
	PendingSeconds: number,
	PendingGeneratedAt: number,
}

type Play15Session = {
	EndsAt: number,
}

type RecentClaim = {
	BaseAmount: number,
	Multiplier: number,
	ResolvedAt: number,
}

local PlayerController
local getStatusRemote: RemoteFunction? = nil
local claimRemote: RemoteFunction? = nil
local startPlay15Remote: RemoteFunction? = nil
local statusUpdatedRemote: RemoteEvent? = nil
local play15Sessions: {[Player]: Play15Session} = {}
local recentClaims: {[Player]: RecentClaim} = {}
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()
local RECENT_CLAIM_UPGRADE_WINDOW = 120

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getEventsFolder(): Folder?
	local events = ReplicatedStorage:FindFirstChild("Events")
	if events and events:IsA("Folder") then
		return events
	end

	return nil
end

local function showNotification(player: Player, message: string, messageType: string)
	local eventsFolder = getEventsFolder()
	local remote = eventsFolder and eventsFolder:FindFirstChild("ShowNotification")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, message, messageType)
	end
end

local function getProfile(player: Player)
	if not PlayerController then
		return nil
	end

	return PlayerController:GetProfile(player)
end

local function clearRecentClaim(player: Player)
	recentClaims[player] = nil
end

function OfflineIncomeController:EnsureData(profileData): OfflineIncomeData
	if type(profileData.OfflineIncome) ~= "table" then
		profileData.OfflineIncome = {
			PendingBaseAmount = 0,
			PendingSeconds = 0,
			PendingGeneratedAt = 0,
		}
	end

	local data = profileData.OfflineIncome
	if type(data.PendingBaseAmount) ~= "number" then
		data.PendingBaseAmount = 0
	end
	if type(data.PendingSeconds) ~= "number" then
		data.PendingSeconds = 0
	end
	if type(data.PendingGeneratedAt) ~= "number" then
		data.PendingGeneratedAt = 0
	end

	data.PendingBaseAmount = math.max(0, data.PendingBaseAmount)
	data.PendingSeconds = math.max(0, math.floor(data.PendingSeconds))
	data.PendingGeneratedAt = math.max(0, math.floor(data.PendingGeneratedAt))

	return data
end

function OfflineIncomeController:GetStatus(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return nil
	end

	local data = self:EnsureData(profile.Data)
	local productId = ProductConfigurations.Products[OfflineIncomeConfiguration.ProductKey]
	local play15Session = play15Sessions[player]

	return {
		PendingBaseAmount = data.PendingBaseAmount,
		PendingSeconds = data.PendingSeconds,
		HasPendingReward = data.PendingBaseAmount > 0,
		RobuxMultiplier = OfflineIncomeConfiguration.RobuxMultiplier,
		Play15Multiplier = OfflineIncomeConfiguration.Play15Multiplier,
		Play15Seconds = OfflineIncomeConfiguration.Play15Seconds,
		ProductKey = OfflineIncomeConfiguration.ProductKey,
		ProductId = type(productId) == "number" and productId or 0,
		Play15Active = play15Session ~= nil,
		Play15EndsAt = play15Session and play15Session.EndsAt or 0,
	}
end

function OfflineIncomeController:PushStatus(player: Player)
	local status = self:GetStatus(player)
	if not status then
		return nil
	end

	player:SetAttribute("OfflineIncomePendingAmount", status.PendingBaseAmount)
	player:SetAttribute("OfflineIncomePlay15Active", status.Play15Active)
	player:SetAttribute("OfflineIncomePlay15EndsAt", status.Play15EndsAt)

	if statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end

	return status
end

function OfflineIncomeController:PushStatusForTesting(player: Player)
	return self:PushStatus(player)
end

function OfflineIncomeController:CancelPlay15(player: Player)
	play15Sessions[player] = nil
	player:SetAttribute("OfflineIncomePlay15Active", false)
	player:SetAttribute("OfflineIncomePlay15EndsAt", 0)
end

function OfflineIncomeController:ClearPendingReward(profileData)
	local data = self:EnsureData(profileData)
	data.PendingBaseAmount = 0
	data.PendingSeconds = 0
	data.PendingGeneratedAt = 0
end

function OfflineIncomeController:RememberClaim(player: Player, baseAmount: number, multiplier: number)
	recentClaims[player] = {
		BaseAmount = math.max(0, baseAmount),
		Multiplier = math.max(1, multiplier),
		ResolvedAt = os.time(),
	}
end

local function buildClaimSourceFields(multiplier: number, claimType: string)
	return {
		feature = "offline_income",
		content_id = claimType,
		context = "claim",
		claim_type = claimType,
		claim_multiplier = multiplier,
	}
end

function OfflineIncomeController:GrantReward(player: Player, baseAmount: number, multiplier: number, transactionType: string, claimType: string)
	local resolvedBaseAmount = math.max(0, math.floor(baseAmount))
	local resolvedMultiplier = math.max(1, multiplier)
	local totalAmount = math.max(0, math.floor(resolvedBaseAmount * resolvedMultiplier))

	if resolvedBaseAmount <= 0 or totalAmount <= 0 then
		return false, 0
	end

	AnalyticsEconomyService:FlushBombIncome(player)
	PlayerController:AddMoney(player, totalAmount)
	AnalyticsEconomyService:LogCashSource(
		player,
		totalAmount,
		transactionType,
		`OfflineIncome:{claimType}`,
		buildClaimSourceFields(resolvedMultiplier, claimType)
	)

	self:RememberClaim(player, resolvedBaseAmount, resolvedMultiplier)
	return true, totalAmount
end

function OfflineIncomeController:QueueOfflineIncomeForJoin(player: Player, profile: any)
	if not profile or not profile.Data then
		return 0
	end

	local lastSaveTime = tonumber(profile.Data.LastSaveTime) or 0
	if lastSaveTime <= 0 then
		return 0
	end

	local elapsedSeconds = os.time() - lastSaveTime
	if elapsedSeconds < OfflineIncomeConfiguration.MinimumOfflineSeconds then
		return 0
	end

	local offlineSeconds = math.min(elapsedSeconds, OfflineIncomeConfiguration.MaxOfflineSeconds)
	local totalBaseAmount = 0
	local isVip = PlayerController:IsVIP(player)
	local rebirths = tonumber(profile.Data.Rebirths) or 0

	for _, floorData in pairs(profile.Data.Plots or {}) do
		if type(floorData) == "table" then
			for _, slotData in pairs(floorData) do
				if type(slotData) == "table" and type(slotData.Item) == "table" then
					local itemName = slotData.Item.Name
					if type(itemName) == "string" and itemName ~= "" then
						local itemConfiguration = ItemConfigurations.GetItemData(itemName)
						if itemConfiguration then
							local incomePerSecond = IncomeCalculationUtils.ComputeOfflineIncomePerSecond(
								itemConfiguration.Income,
								slotData.Item.Mutation,
								slotData.Level,
								rebirths,
								isVip
							)
							totalBaseAmount += incomePerSecond * offlineSeconds
						end
					end
				end
			end
		end
	end

	local roundedBaseAmount = math.max(0, math.floor(totalBaseAmount))
	if roundedBaseAmount <= 0 then
		return 0
	end

	local data = self:EnsureData(profile.Data)
	data.PendingBaseAmount += roundedBaseAmount
	data.PendingSeconds += offlineSeconds
	data.PendingGeneratedAt = os.time()

	return roundedBaseAmount
end

function OfflineIncomeController:HandleClaim(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return {
			Success = false,
			Error = "ProfileNotLoaded",
		}
	end

	local data = self:EnsureData(profile.Data)
	local baseAmount = math.max(0, math.floor(data.PendingBaseAmount))
	if baseAmount <= 0 then
		self:CancelPlay15(player)
		local status = self:PushStatus(player)
		return {
			Success = false,
			Error = "NoPendingReward",
			Status = status,
		}
	end

	local granted, totalAmount = self:GrantReward(player, baseAmount, 1, TRANSACTION_TYPES.Gameplay, "base")
	if not granted then
		return {
			Success = false,
			Error = "GrantFailed",
			Status = self:PushStatus(player),
		}
	end

	self:ClearPendingReward(profile.Data)
	self:CancelPlay15(player)
	local status = self:PushStatus(player)
	showNotification(player, "Offline income claimed: +" .. NumberFormatter.Format(totalAmount), "Success")

	return {
		Success = true,
		Status = status,
		GrantedAmount = totalAmount,
	}
end

function OfflineIncomeController:StartPlay15(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return {
			Success = false,
			Error = "ProfileNotLoaded",
		}
	end

	local data = self:EnsureData(profile.Data)
	if data.PendingBaseAmount <= 0 then
		self:CancelPlay15(player)
		return {
			Success = false,
			Error = "NoPendingReward",
			Status = self:PushStatus(player),
		}
	end

	if play15Sessions[player] then
		return {
			Success = false,
			Error = "AlreadyActive",
			Status = self:PushStatus(player),
		}
	end

	play15Sessions[player] = {
		EndsAt = os.time() + OfflineIncomeConfiguration.Play15Seconds,
	}

	local status = self:PushStatus(player)
	showNotification(player, "Stay in-game for 15 minutes to claim x5 offline income.", "Success")

	return {
		Success = true,
		Status = status,
	}
end

function OfflineIncomeController:HandlePlay15Completion(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		self:CancelPlay15(player)
		return false
	end

	local data = self:EnsureData(profile.Data)
	local baseAmount = math.max(0, math.floor(data.PendingBaseAmount))
	if baseAmount <= 0 then
		self:CancelPlay15(player)
		self:PushStatus(player)
		return false
	end

	local granted, totalAmount = self:GrantReward(
		player,
		baseAmount,
		OfflineIncomeConfiguration.Play15Multiplier,
		TRANSACTION_TYPES.TimedReward,
		"play15"
	)
	if not granted then
		self:CancelPlay15(player)
		return false
	end

	self:ClearPendingReward(profile.Data)
	self:CancelPlay15(player)
	self:PushStatus(player)
	showNotification(player, "Offline income x5 claimed: +" .. NumberFormatter.Format(totalAmount), "Success")
	return true
end

function OfflineIncomeController:HandleRobuxClaim(player: Player)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return false, false, nil
	end

	local data = self:EnsureData(profile.Data)
	local baseAmount = math.max(0, math.floor(data.PendingBaseAmount))
	if baseAmount > 0 then
		local granted, totalAmount = self:GrantReward(
			player,
			baseAmount,
			OfflineIncomeConfiguration.RobuxMultiplier,
			TRANSACTION_TYPES.IAP,
			"robux"
		)
		if not granted then
			return false, false, self:PushStatus(player)
		end

		self:ClearPendingReward(profile.Data)
		self:CancelPlay15(player)
		local status = self:PushStatus(player)
		showNotification(player, "Offline income x5 claimed: +" .. NumberFormatter.Format(totalAmount), "Success")
		return true, true, status
	end

	local recentClaim = recentClaims[player]
	if recentClaim then
		local claimAge = os.time() - recentClaim.ResolvedAt
		if claimAge <= RECENT_CLAIM_UPGRADE_WINDOW and recentClaim.Multiplier < OfflineIncomeConfiguration.RobuxMultiplier then
			local upgradeMultiplier = OfflineIncomeConfiguration.RobuxMultiplier - recentClaim.Multiplier
			local granted, totalAmount = self:GrantReward(
				player,
				recentClaim.BaseAmount,
				upgradeMultiplier,
				TRANSACTION_TYPES.IAP,
				"robux_upgrade"
			)
			if not granted then
				return false, false, self:PushStatus(player)
			end

			recentClaim.Multiplier = OfflineIncomeConfiguration.RobuxMultiplier
			recentClaim.ResolvedAt = os.time()
			self:CancelPlay15(player)
			local status = self:PushStatus(player)
			showNotification(player, "Offline income upgraded to x5: +" .. NumberFormatter.Format(totalAmount), "Success")
			return true, true, status
		end
	end

	showNotification(player, "No offline income is waiting to be upgraded.", "Error")
	return true, false, self:PushStatus(player)
end

function OfflineIncomeController:Init(controllers)
	PlayerController = controllers.PlayerController

	local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
	local offlineIncomeFolder = ensureFolder(remotesFolder, "OfflineIncome")

	getStatusRemote = ensureRemoteFunction(offlineIncomeFolder, "GetStatus")
	claimRemote = ensureRemoteFunction(offlineIncomeFolder, "Claim")
	startPlay15Remote = ensureRemoteFunction(offlineIncomeFolder, "StartPlay15")
	statusUpdatedRemote = ensureRemoteEvent(offlineIncomeFolder, "StatusUpdated")

	getStatusRemote.OnServerInvoke = function(player)
		local status = self:PushStatus(player) or self:GetStatus(player)
		return {
			Success = status ~= nil,
			Status = status,
		}
	end

	claimRemote.OnServerInvoke = function(player)
		return self:HandleClaim(player)
	end

	startPlay15Remote.OnServerInvoke = function(player)
		return self:StartPlay15(player)
	end
end

function OfflineIncomeController:Start()
	Players.PlayerRemoving:Connect(function(player)
		self:CancelPlay15(player)
		clearRecentClaim(player)
		player:SetAttribute("OfflineIncomePendingAmount", nil)
		player:SetAttribute("OfflineIncomePlay15Active", nil)
		player:SetAttribute("OfflineIncomePlay15EndsAt", nil)
	end)

	task.spawn(function()
		while true do
			task.wait(1)

			local now = os.time()
			for player, session in pairs(play15Sessions) do
				if not player.Parent then
					self:CancelPlay15(player)
				elseif now >= session.EndsAt then
					self:HandlePlay15Completion(player)
				end
			end
		end
	end)
end

return OfflineIncomeController
