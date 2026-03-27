--!strict
-- LOCATION: ServerScriptService/Controllers/GroupRewardController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GroupRewardController = {}

-- Modules
local PlayerController 
local ItemManager 
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

function GroupRewardController:ProcessRewardRequest(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return {Success = false, Msg = "Data not loaded yet!"} end

	-- Check if they already claimed it
	if profile.Data.ClaimedPacks["GroupItemReward"] then
		return {Success = false, Msg = "Already claimed!"}
	end

	-- Verify Group Membership via Roblox API
	local groupId = ProductConfigurations.Group.Id
	local success, isInGroup = pcall(function()
		return player:IsInGroup(groupId)
	end)

	if not success then
		return {Success = false, Msg = "Roblox API Error. Try again!"}
	end

	if isInGroup then
		-- 1. Mark as Claimed
		profile.Data.ClaimedPacks["GroupItemReward"] = true
		player:SetAttribute("GroupRewardClaimed", true)

		-- 2. Give the Item
		local rewardConfig = ProductConfigurations.Group.Reward
		local itemData = ItemConfigurations.GetItemData(rewardConfig.Name)
		local rarity = itemData and itemData.Rarity or "Common"

		local tool = ItemManager.GiveItemToPlayer(
			player, 
			rewardConfig.Name, 
			rewardConfig.Mutation, 
			rarity, 
			rewardConfig.Level or 1
		)
		if tool then
			AnalyticsEconomyService:LogItemValueSourceForItem(
				player,
				rewardConfig.Name,
				rewardConfig.Mutation,
				rewardConfig.Level or 1,
				TRANSACTION_TYPES.Onboarding,
				`GroupRewardItem:{rewardConfig.Name}`,
				{
					feature = "group_reward",
					content_id = rewardConfig.Name,
					context = "onboarding",
					rarity = rarity,
					mutation = rewardConfig.Mutation,
				}
			)
		end

		-- 3. Play Visual Effects
		local Events = ReplicatedStorage:FindFirstChild("Events")
		if Events and Events:FindFirstChild("TriggerUIEffect") then
			Events.TriggerUIEffect:FireClient(player, "HighlightLight")
		end

		return {Success = true}
	else
		AnalyticsFunnelsService:HandleGroupRewardRejected(player)
		return {Success = false, Msg = "You must join the group first!"}
	end
end

function GroupRewardController:Init(controllers)
	print("[GroupRewardController] Initialized")
	PlayerController = controllers.PlayerController
	ItemManager = require(ServerScriptService.Modules.ItemManager)

	-- Create RemoteFunction
	local Events = ReplicatedStorage:WaitForChild("Events")
	local reqEvent = Events:FindFirstChild("RequestGroupReward") or Instance.new("RemoteFunction")
	reqEvent.Name = "RequestGroupReward"
	reqEvent.Parent = Events

	reqEvent.OnServerInvoke = function(player)
		return self:ProcessRewardRequest(player)
	end
end

function GroupRewardController:Start()
	-- Synchronize the player's attribute when their character loads
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			local profile = PlayerController:GetProfile(player)
			if profile then
				local isClaimed = profile.Data.ClaimedPacks["GroupItemReward"] == true
				player:SetAttribute("GroupRewardClaimed", isClaimed)
			end
		end)
	end)
end

return GroupRewardController
