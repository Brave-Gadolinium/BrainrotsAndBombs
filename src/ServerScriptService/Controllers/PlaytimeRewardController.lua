--!strict
-- LOCATION: ServerScriptService/Controllers/PlaytimeRewardController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlaytimeRewardManager = require(ServerScriptService.Modules.PlaytimeRewardManager)
local PlaytimeRewardConfiguration = require(ReplicatedStorage.Modules.PlaytimeRewardConfiguration)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local PlaytimeRewardController = {}

local PlayerController
local ItemManager
local remotesFolder
local getStatusRemote
local claimRewardRemote
local statusUpdatedRemote

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
		PlayerController:AddMoney(player, reward.Amount)
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

		showNotification(player, "You got " .. (reward.DisplayName or tool.Name) .. "!", "Success")
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

	local success, err, status, reward = PlaytimeRewardManager.Claim(profile.Data, rewardId)
	if not success then
		setPlayerAttributes(player, status)
		return {
			Success = false,
			Error = err,
			Status = status,
		}
	end

	local applied, applyError = self:ApplyReward(player, reward)
	if not applied then
		return {
			Success = false,
			Error = applyError,
			Status = status,
		}
	end

	setPlayerAttributes(player, status)
	if statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end

	return {
		Success = true,
		Status = status,
		Reward = reward,
	}
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
