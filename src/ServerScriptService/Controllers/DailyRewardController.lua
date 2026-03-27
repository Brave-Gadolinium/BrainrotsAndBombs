--!strict
-- LOCATION: ServerScriptService/Controllers/DailyRewardController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyRewardManager = require(ServerScriptService.Modules.DailyRewardManager)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local DailyRewardConfiguration = require(ReplicatedStorage.Modules.DailyRewardConfiguration)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local DailyRewardController = {}
local randomObject = Random.new()

local PlayerController
local PickaxeController
local ItemManager
local remotesFolder
local getStatusRemote
local claimRewardRemote
local statusUpdatedRemote
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

local function setPlayerAttributes(player: Player, status)
	player:SetAttribute("DailyRewardStreak", status.CurrentStreak)
	player:SetAttribute("DailyRewardClaimDay", status.ClaimDay)
	player:SetAttribute("DailyRewardClaimedToday", status.ClaimedToday)
	player:SetAttribute("DailyRewardLastClaimDay", status.LastClaimDay)
end

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

local function pushStatus(player: Player, status)
	setPlayerAttributes(player, status)
	AnalyticsFunnelsService:HandleDailyRewardStatus(player, status)
	if statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end
end

local function applyCompensation(player: Player, day: number, reward)
	if reward.CompensationType == "Money" and type(reward.CompensationAmount) == "number" then
		AnalyticsEconomyService:FlushBombIncome(player)
		PlayerController:AddMoney(player, reward.CompensationAmount)
		AnalyticsEconomyService:LogCashSource(player, reward.CompensationAmount, TRANSACTION_TYPES.TimedReward, `DailyReward:{day}`, {
			feature = "daily_reward",
			content_id = tostring(day),
			context = "reward_compensation",
			reward_day = day,
		})
		showNotification(player, "You already own this reward. Compensation: $" .. NumberFormatter.Format(reward.CompensationAmount), "Success")
		return true, nil
	end

	return false, "UnsupportedCompensationType"
end

function DailyRewardController:GetStatusForPlayer(player: Player)
	local profile = getProfile(player)
	if not profile then
		return nil
	end

	local status = DailyRewardManager.GetStatus(profile.Data)
	setPlayerAttributes(player, status)
	return status
end

function DailyRewardController:PushStatus(player: Player)
	local status = self:GetStatusForPlayer(player)
	if status then
		pushStatus(player, status)
	end
	return status
end

function DailyRewardController:ApplyReward(player: Player, day: number, reward)
	if not reward then
		return false, "MissingReward"
	end

	if reward.Type == "Money" then
		AnalyticsEconomyService:FlushBombIncome(player)
		PlayerController:AddMoney(player, reward.Amount)
		AnalyticsEconomyService:LogCashSource(player, reward.Amount, TRANSACTION_TYPES.TimedReward, `DailyReward:{day}`, {
			feature = "daily_reward",
			content_id = tostring(day),
			context = "reward_claim",
			reward_day = day,
		})
		showNotification(player, "You got $" .. NumberFormatter.Format(reward.Amount) .. "!", "Success")
		return true, nil
	end

	if reward.Type == "RandomItemByRarity" then
		local rarity = reward.Rarity
		if not rarity then
			return false, "MissingRarity"
		end

		local items = ItemConfigurations.GetItemsByRarity(rarity)
		if not items or #items == 0 then
			warn("[DailyRewardController] No items found for rarity:", rarity)
			return false, "NoItemsForRarity"
		end

		local itemName = items[randomObject:NextInteger(1, #items)]
		local itemData = ItemConfigurations.GetItemData(itemName)
		if not itemData then
			return false, "ItemConfigMissing"
		end

		local tool = ItemManager.GiveItemToPlayer(player, itemName, "Normal", itemData.Rarity, 1)
		if not tool then
			return false, "ItemGrantFailed"
		end
		AnalyticsEconomyService:LogItemValueSourceForItem(
			player,
			itemName,
			"Normal",
			1,
			TRANSACTION_TYPES.TimedReward,
			`DailyRewardItem:{day}`,
			{
				feature = "daily_reward",
				content_id = itemName,
				context = "reward_claim",
				reward_day = day,
				rarity = itemData.Rarity,
				mutation = "Normal",
			}
		)
		showNotification(player, "You got a " .. itemData.Rarity .. " " .. itemName .. "!", "Success")
		return true, nil
	end

	if reward.Type == "Pickaxe" then
		local pickaxeName = reward.PickaxeName
		if not pickaxeName then
			return false, "MissingPickaxeName"
		end

		local profile = getProfile(player)
		if not profile then
			return false, "ProfileNotLoaded"
		end

		if type(profile.Data.OwnedPickaxes) ~= "table" then
			profile.Data.OwnedPickaxes = { ["Bomb 1"] = true }
		end

		if profile.Data.OwnedPickaxes[pickaxeName] then
			return applyCompensation(player, day, reward)
		end

		profile.Data.OwnedPickaxes[pickaxeName] = true
		profile.Data.EquippedPickaxe = pickaxeName
		PickaxeController.EquipPickaxe(player, pickaxeName)
		AnalyticsEconomyService:LogEntitlementGranted(player, "PickaxeReward", pickaxeName, reward.CompensationAmount, {
			feature = "daily_reward",
			content_id = pickaxeName,
			context = "reward_claim",
			reward_day = day,
		})

		local updateUIEvent = getEventsFolder() and getEventsFolder():FindFirstChild("UpdatePickaxeUI")
		if updateUIEvent and updateUIEvent:IsA("RemoteEvent") then
			updateUIEvent:FireClient(player)
		end

		showNotification(player, "You got " .. pickaxeName .. "!", "Success")
		return true, nil
	end

	return false, "UnsupportedRewardType"
end

function DailyRewardController:HandleSkip1(player: Player)
	local profile = getProfile(player)
	if not profile then
		return false, "ProfileNotLoaded", nil
	end

	local unopenedDays = DailyRewardManager.GetUnopenedRewardDays(profile.Data)
	local day = unopenedDays[1]
	if not day then
		local status = DailyRewardManager.GetStatus(profile.Data)
		pushStatus(player, status)
		return false, "NoRewardsToSkip", status
	end

	local success, err, status = DailyRewardManager.UnlockDay(profile.Data, day)
	pushStatus(player, status)

	if not success then
		return false, err, status
	end

	showNotification(player, "Day " .. tostring(day) .. " daily reward unlocked!", "Success")
	return true, nil, status
end

function DailyRewardController:HandleSkipAll(player: Player)
	local profile = getProfile(player)
	if not profile then
		return false, "ProfileNotLoaded", nil
	end

	local unopenedDays = DailyRewardManager.GetUnopenedRewardDays(profile.Data)
	if #unopenedDays == 0 then
		local status = DailyRewardManager.GetStatus(profile.Data)
		pushStatus(player, status)
		return false, "NoRewardsToSkip", status
	end

	local latestStatus = DailyRewardManager.GetStatus(profile.Data)
	for _, day in ipairs(unopenedDays) do
		local success, err, status = DailyRewardManager.UnlockDay(profile.Data, day)
		latestStatus = status
		if not success then
			pushStatus(player, latestStatus)
			return false, err, latestStatus
		end
	end

	pushStatus(player, latestStatus)
	showNotification(player, "All remaining daily rewards for this cycle are now unlocked!", "Success")
	return true, nil, latestStatus
end

function DailyRewardController:HandleClaim(player: Player, day: number)
	local profile = getProfile(player)
	if not profile then
		return {
			Success = false,
			Error = "ProfileNotLoaded",
		}
	end

	if type(day) ~= "number" then
		local status = DailyRewardManager.GetStatus(profile.Data)
		setPlayerAttributes(player, status)
		return {
			Success = false,
			Error = "InvalidDay",
			Status = status,
		}
	end

	local success, err, status, reward = DailyRewardManager.GetClaimableReward(profile.Data, day)
	AnalyticsFunnelsService:HandleDailyRewardClaimAttempt(player, day)
	if not success then
		AnalyticsFunnelsService:HandleDailyRewardClaimFailure(player, day, err or "Unknown")
		setPlayerAttributes(player, status)
		return {
			Success = false,
			Error = err,
			Status = status,
		}
	end

	local applied, applyError = self:ApplyReward(player, day, reward)
	if not applied then
		return {
			Success = false,
			Error = applyError,
			Status = status,
		}
	end

	local marked, markError, updatedStatus = DailyRewardManager.MarkRewardClaimed(profile.Data, day)
	if not marked then
		AnalyticsFunnelsService:HandleDailyRewardClaimFailure(player, day, markError or "Unknown")
		return {
			Success = false,
			Error = markError,
			Status = updatedStatus,
		}
	end

	pushStatus(player, updatedStatus)
	AnalyticsFunnelsService:HandleDailyRewardClaimSuccess(player, day)

	return {
		Success = true,
		Status = updatedStatus,
		Reward = reward,
	}
end

function DailyRewardController:Init(controllers)
	PlayerController = controllers.PlayerController
	PickaxeController = controllers.PickaxeController
	ItemManager = require(ServerScriptService.Modules.ItemManager)

	remotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DailyRewards")
	getStatusRemote = remotesFolder:WaitForChild("GetStatus")
	claimRewardRemote = remotesFolder:WaitForChild("ClaimReward")
	statusUpdatedRemote = remotesFolder:WaitForChild("StatusUpdated")

	getStatusRemote.OnServerInvoke = function(player)
		local status = self:GetStatusForPlayer(player)
		return {
			Success = status ~= nil,
			Status = status,
			Rewards = DailyRewardConfiguration.Rewards,
		}
	end

	claimRewardRemote.OnServerInvoke = function(player, day)
		return self:HandleClaim(player, day)
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
		player:SetAttribute("DailyRewardStreak", nil)
		player:SetAttribute("DailyRewardClaimDay", nil)
		player:SetAttribute("DailyRewardClaimedToday", nil)
		player:SetAttribute("DailyRewardLastClaimDay", nil)
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

return DailyRewardController
