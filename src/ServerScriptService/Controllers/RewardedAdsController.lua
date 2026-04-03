--!strict
-- LOCATION: ServerScriptService/Controllers/RewardedAdsController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdService = game:GetService("AdService")

local RewardedAdsController = {}

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local REQUEST_REMOTE_NAME = "RequestRewardedAd"
local RESULT_REMOTE_NAME = "RewardedAdResult"

local activeRequests: {[Player]: boolean} = {}

local function getEventsFolder(): Folder
	return ReplicatedStorage:WaitForChild("Events") :: Folder
end

local function getRemoteEvent(name: string): RemoteEvent
	local eventsFolder = getEventsFolder()
	local remote = eventsFolder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	local createdRemote = Instance.new("RemoteEvent")
	createdRemote.Name = name
	createdRemote.Parent = eventsFolder
	return createdRemote
end

local function getPrimaryRewardConfig(): (string?, {[string]: any}?, number?)
	local rewardKey = ProductConfigurations.PrimaryRewardedAdKey
	if type(rewardKey) ~= "string" or rewardKey == "" then
		return nil, nil, nil
	end

	local rewardConfig = ProductConfigurations.RewardedAdRewards[rewardKey]
	if type(rewardConfig) ~= "table" then
		return rewardKey, nil, nil
	end

	local productId = ProductConfigurations.Products[rewardKey]
	if type(productId) ~= "number" then
		productId = nil
	end

	return rewardKey, rewardConfig, productId
end

local function getPlacementId(rewardConfig: {[string]: any}?): number?
	if type(rewardConfig) ~= "table" then
		return nil
	end

	local placementId = rewardConfig.PlacementId
	if type(placementId) == "number" and placementId > 0 then
		return placementId
	end

	return nil
end

local function getResultMessage(result: EnumItem): string
	if result == Enum.ShowAdResult.ShowCompleted then
		return "completed"
	end
	if result == Enum.ShowAdResult.AdNotReady then
		return "Rewarded ad is not ready yet. Try again in a bit."
	end
	if result == Enum.ShowAdResult.AdAlreadyShowing then
		return "Another full-screen ad is already showing."
	end
	if result == Enum.ShowAdResult.ShowInterrupted then
		return "The ad was interrupted, so no reward was granted."
	end
	if result == Enum.ShowAdResult.InsufficientMemory then
		return "The ad could not start because the device is low on memory."
	end

	return "Rewarded ad is unavailable right now."
end

function RewardedAdsController:Start()
	local requestRemote = getRemoteEvent(REQUEST_REMOTE_NAME)
	local resultRemote = getRemoteEvent(RESULT_REMOTE_NAME)

	local function sendResult(player: Player, status: string, message: string?)
		resultRemote:FireClient(player, status, message)
	end

	requestRemote.OnServerEvent:Connect(function(player: Player)
		if activeRequests[player] then
			sendResult(player, "Error", "Rewarded ad is already opening.")
			return
		end

		local rewardKey, rewardConfig, productId = getPrimaryRewardConfig()
		if not rewardKey or not rewardConfig then
			sendResult(player, "Error", "Rewarded ad is not configured yet.")
			return
		end

		if type(productId) ~= "number" or productId <= 0 then
			sendResult(player, "Error", "Set the rewarded ad Developer Product ID first.")
			return
		end

		activeRequests[player] = true

		local ok, resultOrError = pcall(function()
			local reward = AdService:CreateAdRewardFromDevProductId(productId)
			local placementId = getPlacementId(rewardConfig)
			return AdService:ShowRewardedVideoAdAsync(player, reward, placementId)
		end)

		activeRequests[player] = nil

		if not ok then
			warn("[RewardedAdsController] Failed to show rewarded ad:", resultOrError)
			sendResult(player, "Error", "Rewarded ad is unavailable right now.")
			return
		end

		local result = resultOrError :: EnumItem
		if result == Enum.ShowAdResult.ShowCompleted then
			sendResult(player, "Success", nil)
			return
		end

		sendResult(player, "Error", getResultMessage(result))
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		activeRequests[player] = nil
	end)

	print("[RewardedAdsController] Started")
end

return RewardedAdsController
