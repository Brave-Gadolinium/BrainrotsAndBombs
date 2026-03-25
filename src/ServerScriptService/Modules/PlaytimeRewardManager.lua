--!strict
-- LOCATION: ServerScriptService/Modules/PlaytimeRewardManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.PlaytimeRewardConfiguration)

local PlaytimeRewardManager = {}

export type PlaytimeRewardData = {
	DayKey: number,
	PlaytimeSeconds: number,
	ClaimedRewards: { [number]: boolean },
	HasSpeedX2: boolean,
	HasSpeedX5: boolean,
}

export type PlaytimeRewardStatus = {
	DayKey: number,
	PlaytimeSeconds: number,
	ClaimedRewards: { [number]: boolean },
	ClaimableRewardIds: { number },
	NextRewardId: number?,
	SecondsUntilNextReward: number,
	Rewards: { [number]: any },
	HasSpeedX2: boolean,
	HasSpeedX5: boolean,
	SpeedMultiplier: number,
}

local function getCurrentDayKey(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

local function cloneClaimedRewards(source)
	local result = {}
	for rewardId, isClaimed in pairs(source or {}) do
		if isClaimed then
			result[rewardId] = true
		end
	end
	return result
end

local function getMaxRequiredSeconds(): number
	local maxRequiredSeconds = 0
	for _, reward in ipairs(Config.Rewards) do
		if reward.RequiredSeconds > maxRequiredSeconds then
			maxRequiredSeconds = reward.RequiredSeconds
		end
	end
	return maxRequiredSeconds
end

function PlaytimeRewardManager.GetSpeedMultiplier(profileData): number
	local data = PlaytimeRewardManager.EnsureData(profileData)
	if data.HasSpeedX5 then
		return 5
	end
	if data.HasSpeedX2 then
		return 2
	end
	return 1
end

function PlaytimeRewardManager.EnsureData(profileData, now: number?): PlaytimeRewardData
	local currentDayKey = getCurrentDayKey(now)
	profileData.PlaytimeRewards = profileData.PlaytimeRewards or {
		DayKey = currentDayKey,
		PlaytimeSeconds = 0,
		ClaimedRewards = {},
		HasSpeedX2 = false,
		HasSpeedX5 = false,
	}

	local data = profileData.PlaytimeRewards

	if type(data.DayKey) ~= "number" then
		data.DayKey = currentDayKey
	end

	if type(data.PlaytimeSeconds) ~= "number" then
		data.PlaytimeSeconds = 0
	end

	if type(data.ClaimedRewards) ~= "table" then
		data.ClaimedRewards = {}
	end

	if type(data.HasSpeedX2) ~= "boolean" then
		data.HasSpeedX2 = false
	end

	if type(data.HasSpeedX5) ~= "boolean" then
		data.HasSpeedX5 = false
	end

	if data.DayKey ~= currentDayKey then
		data.DayKey = currentDayKey
		data.PlaytimeSeconds = 0
		data.ClaimedRewards = {}
	end

	return data
end

function PlaytimeRewardManager.GetStatus(profileData, now: number?): PlaytimeRewardStatus
	local data = PlaytimeRewardManager.EnsureData(profileData, now)
	local speedMultiplier = PlaytimeRewardManager.GetSpeedMultiplier(profileData)
	local claimableRewardIds = {}
	local nextRewardId = nil
	local secondsUntilNextReward = 0

	for _, reward in ipairs(Config.Rewards) do
		if data.PlaytimeSeconds >= reward.RequiredSeconds then
			if not data.ClaimedRewards[reward.Id] then
				table.insert(claimableRewardIds, reward.Id)
			end
		elseif nextRewardId == nil then
			nextRewardId = reward.Id
			secondsUntilNextReward = reward.RequiredSeconds - data.PlaytimeSeconds
		end
	end

	return {
		DayKey = data.DayKey,
		PlaytimeSeconds = data.PlaytimeSeconds,
		ClaimedRewards = cloneClaimedRewards(data.ClaimedRewards),
		ClaimableRewardIds = claimableRewardIds,
		NextRewardId = nextRewardId,
		SecondsUntilNextReward = math.max(0, secondsUntilNextReward),
		Rewards = Config.Rewards,
		HasSpeedX2 = data.HasSpeedX2,
		HasSpeedX5 = data.HasSpeedX5,
		SpeedMultiplier = speedMultiplier,
	}
end

function PlaytimeRewardManager.Tick(profileData, deltaSeconds: number?, now: number?)
	local data = PlaytimeRewardManager.EnsureData(profileData, now)
	local speedMultiplier = PlaytimeRewardManager.GetSpeedMultiplier(profileData)
	data.PlaytimeSeconds += math.max(1, deltaSeconds or 1) * speedMultiplier
	return PlaytimeRewardManager.GetStatus(profileData, now)
end

function PlaytimeRewardManager.SkipAll(profileData, now: number?)
	local data = PlaytimeRewardManager.EnsureData(profileData, now)
	data.PlaytimeSeconds = math.max(data.PlaytimeSeconds, getMaxRequiredSeconds())
	return PlaytimeRewardManager.GetStatus(profileData, now)
end

function PlaytimeRewardManager.Claim(profileData, rewardId: number, now: number?)
	local data = PlaytimeRewardManager.EnsureData(profileData, now)
	local reward = Config.GetRewardById(rewardId)
	if not reward then
		return false, "RewardNotFound", PlaytimeRewardManager.GetStatus(profileData, now), nil
	end

	if data.ClaimedRewards[rewardId] then
		return false, "AlreadyClaimed", PlaytimeRewardManager.GetStatus(profileData, now), nil
	end

	if data.PlaytimeSeconds < reward.RequiredSeconds then
		return false, "RewardLocked", PlaytimeRewardManager.GetStatus(profileData, now), nil
	end

	data.ClaimedRewards[rewardId] = true
	return true, nil, PlaytimeRewardManager.GetStatus(profileData, now), reward
end

function PlaytimeRewardManager.GrantSpeedProduct(profileData, productName: string, now: number?)
	local data = PlaytimeRewardManager.EnsureData(profileData, now)

	if productName == "PlaytimeRewardsSpeedX2" then
		data.HasSpeedX2 = true
		return true, nil, PlaytimeRewardManager.GetStatus(profileData, now)
	end

	if productName == "PlaytimeRewardsSpeedX5" then
		data.HasSpeedX5 = true
		return true, nil, PlaytimeRewardManager.GetStatus(profileData, now)
	end

	return false, "UnsupportedSpeedProduct", PlaytimeRewardManager.GetStatus(profileData, now)
end

return PlaytimeRewardManager
