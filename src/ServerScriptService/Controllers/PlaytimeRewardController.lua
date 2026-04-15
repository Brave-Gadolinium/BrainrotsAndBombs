--!strict
-- LOCATION: ServerScriptService/Controllers/PlaytimeRewardController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlaytimeRewardManager = require(ServerScriptService.Modules.PlaytimeRewardManager)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local PlaytimeRewardConfiguration = require(ReplicatedStorage.Modules.PlaytimeRewardConfiguration)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local PlaytimeRewardController = {}

local PlayerController
local ItemManager
local remotesFolder
local getStatusRemote
local claimRewardRemote
local statusUpdatedRemote
local claimRequestsInFlight: {[Player]: boolean} = {}
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

local function getProfile(player: Player)
	if not PlayerController then
		return nil
	end

	return PlayerController:GetProfile(player)
end

local function getEventsFolder()
	return ReplicatedStorage:FindFirstChild("Events")
end

local function showNotification(player: Player, message: string, messageType: string)
	local eventsFolder = getEventsFolder()
	local remote = eventsFolder and eventsFolder:FindFirstChild("ShowNotification")
	if remote then
		remote:FireClient(player, message, messageType)
	end
end

local function setPlayerAttributes(player: Player, status)
	player:SetAttribute("PlaytimeRewardDayKey", status.DayKey)
	player:SetAttribute("PlaytimeRewardSeconds", status.PlaytimeSeconds)
	player:SetAttribute("PlaytimeRewardNextId", status.NextRewardId or 0)
	player:SetAttribute("PlaytimeRewardSecondsUntilNext", status.SecondsUntilNextReward)
	player:SetAttribute("PlaytimeRewardClaimableCount", #status.ClaimableRewardIds)
	player:SetAttribute("PlaytimeRewardHasSpeedX2", status.HasSpeedX2)
	player:SetAttribute("PlaytimeRewardHasSpeedX5", status.HasSpeedX5)
	player:SetAttribute("PlaytimeRewardSpeedMultiplier", status.SpeedMultiplier)
end

function PlaytimeRewardController:GetStatusForPlayer(player: Player)
	local profile = getProfile(player)
	if not profile then
		return nil
	end

	local status = PlaytimeRewardManager.GetStatus(profile.Data)
	setPlayerAttributes(player, status)
	return status
end

function PlaytimeRewardController:PushStatus(player: Player)
	local status = self:GetStatusForPlayer(player)
	if status then
		AnalyticsFunnelsService:HandlePlaytimeRewardStatus(player, status)
	end
	if status and statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end
	return status
end

function PlaytimeRewardController:PushStatusForTesting(player: Player)
	local status = self:GetStatusForPlayer(player)
	if status then
		setPlayerAttributes(player, status)
	end
	if status and statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end
	return status
end

function PlaytimeRewardController:HandleSkipAll(player: Player)
	local profile = getProfile(player)
	if not profile then
		return false, "ProfileNotLoaded"
	end

	local status = PlaytimeRewardManager.SkipAll(profile.Data)
	setPlayerAttributes(player, status)
	if statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end

	showNotification(player, "All playtime rewards for today are now unlocked!", "Success")
	return true, status
end

function PlaytimeRewardController:HandleSpeedProduct(player: Player, productName: string)
	local profile = getProfile(player)
	if not profile then
		return false, "ProfileNotLoaded", nil
	end

	local success, err, status = PlaytimeRewardManager.GrantSpeedProduct(profile.Data, productName)
	if not success then
		return false, err, status
	end

	setPlayerAttributes(player, status)
	if statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end

	showNotification(player, "Playtime speed multiplier activated: x" .. tostring(status.SpeedMultiplier) .. "!", "Success")
	return true, nil, status
end

function PlaytimeRewardController:ApplyReward(player: Player, reward)
	if not reward then
		return false, "MissingReward"
	end

	if reward.Type == "Money" then
		AnalyticsEconomyService:FlushBombIncome(player)
		PlayerController:AddMoney(player, reward.Amount)
		AnalyticsEconomyService:LogCashSource(player, reward.Amount, TRANSACTION_TYPES.TimedReward, `PlaytimeReward:{reward.Id or 0}`, {
			feature = "playtime_reward",
			content_id = tostring(reward.Id or 0),
			context = "reward_claim",
			reward_id = reward.Id or 0,
		})
		showNotification(player, "You got $" .. NumberFormatter.Format(reward.Amount) .. "!", "Success")
		return true, nil
	end

	if reward.Type == "LuckyBlock" then
		if not reward.LuckyBlockId then
			return false, "MissingLuckyBlockId"
		end

		if not ItemManager then
			ItemManager = require(ServerScriptService.Modules.ItemManager)
		end

		local tool = ItemManager.GiveLuckyBlockToPlayer(player, reward.LuckyBlockId)
		if not tool then
			return false, "LuckyBlockGiveFailed"
		end
		AnalyticsEconomyService:LogItemValueSourceForLuckyBlock(
			player,
			reward.LuckyBlockId,
			TRANSACTION_TYPES.TimedReward,
			`LuckyBlock:{reward.LuckyBlockId}`,
			{
				feature = "playtime_reward",
				content_id = reward.LuckyBlockId,
				context = "reward_claim",
				reward_id = reward.Id or 0,
			}
		)

		showNotification(player, "You got " .. (reward.DisplayName or tool.Name) .. "!", "Success")
		return true, nil
	end

	if reward.Type == "Item" then
		if not reward.ItemName then
			return false, "MissingItemName"
		end

		if not ItemManager then
			ItemManager = require(ServerScriptService.Modules.ItemManager)
		end

		local rarity = reward.Rarity or "Common"
		local tool = ItemManager.GiveItemToPlayer(player, reward.ItemName, reward.Mutation or "Normal", rarity, reward.Level or 1)
		if not tool then
			return false, "ItemGiveFailed"
		end

		PlayerController:IncrementBrainrotsCollected(player, 1)
		showNotification(player, "You got " .. reward.ItemName .. "!", "Success")
		return true, nil
	end

	return false, "UnsupportedRewardType"
end

function PlaytimeRewardController:HandleClaim(player: Player, rewardId: number)
	local profile = getProfile(player)
	if not profile then
		return {
			Success = false,
			Error = "ProfileNotLoaded",
		}
	end

	if claimRequestsInFlight[player] then
		return {
			Success = false,
			Error = "ClaimInProgress",
			Status = self:GetStatusForPlayer(player),
		}
	end

	claimRequestsInFlight[player] = true

	local function finish(result)
		claimRequestsInFlight[player] = nil
		return result
	end

	local success, err, status, reward = PlaytimeRewardManager.GetClaimableReward(profile.Data, rewardId)
	if not success then
		AnalyticsFunnelsService:HandlePlaytimeRewardClaimFailure(player, rewardId, err or "Unknown")
		if status then
			setPlayerAttributes(player, status)
		end
		return finish({
			Success = false,
			Error = err,
			Status = status,
		})
	end

	local applied, applyError = self:ApplyReward(player, reward)
	if not applied then
		AnalyticsFunnelsService:HandlePlaytimeRewardClaimFailure(player, rewardId, applyError or "ApplyFailed")
		if status then
			setPlayerAttributes(player, status)
		end
		return finish({
			Success = false,
			Error = applyError,
			Status = status,
		})
	end

	local marked, markError, updatedStatus = PlaytimeRewardManager.MarkRewardClaimed(profile.Data, rewardId)
	if not marked then
		AnalyticsFunnelsService:HandlePlaytimeRewardClaimFailure(player, rewardId, markError or "MarkFailed")
		if updatedStatus then
			setPlayerAttributes(player, updatedStatus)
		end
		warn("[PlaytimeRewardController] Failed to mark reward claimed after grant:", player.Name, rewardId, markError)
		return finish({
			Success = false,
			Error = markError,
			Status = updatedStatus,
		})
	end

	setPlayerAttributes(player, updatedStatus)
	AnalyticsFunnelsService:HandlePlaytimeRewardClaimSuccess(player, rewardId, updatedStatus)
	if statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, updatedStatus)
	end

	return finish({
		Success = true,
		Status = updatedStatus,
		Reward = reward,
	})
end

function PlaytimeRewardController:Init(controllers)
	PlayerController = controllers.PlayerController
	ItemManager = require(ServerScriptService.Modules.ItemManager)

	remotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlaytimeRewards")
	getStatusRemote = remotesFolder:WaitForChild("GetStatus")
	claimRewardRemote = remotesFolder:WaitForChild("ClaimReward")
	statusUpdatedRemote = remotesFolder:WaitForChild("StatusUpdated")

	getStatusRemote.OnServerInvoke = function(player)
		local status = self:GetStatusForPlayer(player)
		return {
			Success = status ~= nil,
			Status = status,
			Rewards = PlaytimeRewardConfiguration.Rewards,
		}
	end

	claimRewardRemote.OnServerInvoke = function(player, rewardId)
		if type(rewardId) ~= "number" then
			return {
				Success = false,
				Error = "InvalidRewardId",
			}
		end
		return self:HandleClaim(player, rewardId)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			repeat task.wait() until not player.Parent or getProfile(player)
			if not player.Parent then
				return
			end
			self:PushStatus(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		claimRequestsInFlight[player] = nil
		player:SetAttribute("PlaytimeRewardDayKey", nil)
		player:SetAttribute("PlaytimeRewardSeconds", nil)
		player:SetAttribute("PlaytimeRewardNextId", nil)
		player:SetAttribute("PlaytimeRewardSecondsUntilNext", nil)
		player:SetAttribute("PlaytimeRewardClaimableCount", nil)
		player:SetAttribute("PlaytimeRewardHasSpeedX2", nil)
		player:SetAttribute("PlaytimeRewardHasSpeedX5", nil)
		player:SetAttribute("PlaytimeRewardSpeedMultiplier", nil)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			repeat task.wait() until not player.Parent or getProfile(player)
			if not player.Parent then
				return
			end
			self:PushStatus(player)
		end)
	end
end

function PlaytimeRewardController:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = getProfile(player)
				if not profile then
					continue
				end

				local previousStatus = PlaytimeRewardManager.GetStatus(profile.Data)
				local nextRewardIdBefore = previousStatus.NextRewardId
				local secondsUntilBefore = previousStatus.SecondsUntilNextReward
				local claimableCountBefore = #previousStatus.ClaimableRewardIds
				local dayKeyBefore = previousStatus.DayKey

				local status = PlaytimeRewardManager.Tick(profile.Data, 1)
				setPlayerAttributes(player, status)
				AnalyticsFunnelsService:HandlePlaytimeRewardStatus(player, status)

				local shouldPush = false
				if status.DayKey ~= dayKeyBefore then
					shouldPush = true
				elseif #status.ClaimableRewardIds > claimableCountBefore then
					shouldPush = true
				elseif status.NextRewardId ~= nextRewardIdBefore then
					shouldPush = true
				elseif status.SecondsUntilNextReward == 0 and secondsUntilBefore > 0 then
					shouldPush = true
				end

				if shouldPush and statusUpdatedRemote then
					statusUpdatedRemote:FireClient(player, status)
				end
			end
		end
	end)
end

return PlaytimeRewardController
