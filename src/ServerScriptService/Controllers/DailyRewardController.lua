--!strict
-- LOCATION: ServerScriptService/Controllers/DailyRewardController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyRewardManager = require(ServerScriptService.Modules.DailyRewardManager)
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
	if statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end
end

local function applyCompensation(player: Player, reward)
	if reward.CompensationType == "Money" and type(reward.CompensationAmount) == "number" then
		PlayerController:AddMoney(player, reward.CompensationAmount)
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
	if status and statusUpdatedRemote then
		statusUpdatedRemote:FireClient(player, status)
	end
	return status
end

function DailyRewardController:ApplyReward(player: Player, reward)
	if not reward then
		return false, "MissingReward"
	end

	if reward.Type == "Money" then
		PlayerController:AddMoney(player, reward.Amount)
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

		ItemManager.GiveItemToPlayer(player, itemName, "Normal", itemData.Rarity, 1)
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
			return applyCompensation(player, reward)
		end

		profile.Data.OwnedPickaxes[pickaxeName] = true
		profile.Data.EquippedPickaxe = pickaxeName
		PickaxeController.EquipPickaxe(player, pickaxeName)

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

	local reward = DailyRewardConfiguration.GetRewardForDay(day)
	local applied, applyError = self:ApplyReward(player, reward)
	if not applied then
		local status = DailyRewardManager.GetStatus(profile.Data)
		pushStatus(player, status)
		return false, applyError, status
	end

	local status = DailyRewardManager.MarkClaimedThroughDay(profile.Data, day)
	pushStatus(player, status)
	showNotification(player, "Day " .. tostring(day) .. " daily reward opened!", "Success")
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
		local reward = DailyRewardConfiguration.GetRewardForDay(day)
		local applied, applyError = self:ApplyReward(player, reward)
		if not applied then
			pushStatus(player, latestStatus)
			return false, applyError, latestStatus
		end

		latestStatus = DailyRewardManager.MarkClaimedThroughDay(profile.Data, day)
	end

	pushStatus(player, latestStatus)
	showNotification(player, "All remaining daily rewards for this cycle are now opened!", "Success")
	return true, nil, latestStatus
end

function DailyRewardController:HandleClaim(player: Player)
	local profile = getProfile(player)
	if not profile then
		return {
			Success = false,
			Error = "ProfileNotLoaded",
		}
	end

	local success, err, status, reward = DailyRewardManager.Claim(profile.Data)
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

	pushStatus(player, status)

	return {
		Success = true,
		Status = status,
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

	claimRewardRemote.OnServerInvoke = function(player)
		return self:HandleClaim(player)
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