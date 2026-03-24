--!strict
-- LOCATION: ServerScriptService/Modules/PlaytimeRewardManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.PlaytimeRewardConfiguration)

local PlaytimeRewardManager = {}

export type PlaytimeRewardData = {
	DayKey: number,
	PlaytimeSeconds: number,
	ClaimedRewards: { [number]: boolean },
}

export type PlaytimeRewardStatus = {
	DayKey: number,
	PlaytimeSeconds: number,
	ClaimedRewards: { [number]: boolean },
	ClaimableRewardIds: { number },
	NextRewardId: number?,
	SecondsUntilNextReward: number,
	Rewards: { [number]: any },
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

function PlaytimeRewardManager.EnsureData(profileData, now: number?): PlaytimeRewardData
	local currentDayKey = getCurrentDayKey(now)
	profileData.PlaytimeRewards = profileData.PlaytimeRewards or {
		DayKey = currentDayKey,
		PlaytimeSeconds = 0,
		ClaimedRewards = {},
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

	if data.DayKey ~= currentDayKey then
		data.DayKey = currentDayKey
		data.PlaytimeSeconds = 0
		data.ClaimedRewards = {}
	end

	return data
end

function PlaytimeRewardManager.GetStatus(profileData, now: number?): PlaytimeRewardStatus
	local data = PlaytimeRewardManager.EnsureData(profileData, now)
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
	}
end

function PlaytimeRewardManager.Tick(profileData, deltaSeconds: number?, now: number?)
	local data = PlaytimeRewardManager.EnsureData(profileData, now)
	data.PlaytimeSeconds += math.max(1, deltaSeconds or 1)
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

return PlaytimeRewardManager