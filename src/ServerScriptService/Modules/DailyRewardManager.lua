--!strict
-- LOCATION: ServerScriptService/Modules/DailyRewardManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.DailyRewardConfiguration)

local DailyRewardManager = {}

export type DailyRewardData = {
	CurrentStreak: number,
	LastClaimDay: number,
}

export type DailyRewardStatus = {
	CurrentStreak: number,
	ClaimDay: number,
	ClaimedToday: boolean,
	CanClaim: boolean,
	LastClaimDay: number,
	Rewards: { [number]: any },
}

local function getCurrentDayNumber(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

function DailyRewardManager.EnsureData(profileData): DailyRewardData
	profileData.DailyRewards = profileData.DailyRewards or {
		CurrentStreak = 0,
		LastClaimDay = 0,
	}

	local data = profileData.DailyRewards

	if type(data.CurrentStreak) ~= "number" then
		data.CurrentStreak = 0
	end

	if type(data.LastClaimDay) ~= "number" then
		data.LastClaimDay = 0
	end

	return data
end

function DailyRewardManager.GetStatus(profileData, now: number?): DailyRewardStatus
	local data = DailyRewardManager.EnsureData(profileData)
	local currentDay = getCurrentDayNumber(now)
	local maxDay = Config.GetMaxDay()
	local claimedToday = data.LastClaimDay == currentDay

	local claimDay: number
	if claimedToday then
		claimDay = math.clamp(data.CurrentStreak, 1, maxDay)
	elseif data.LastClaimDay == currentDay - 1 then
		claimDay = math.clamp(data.CurrentStreak + 1, 1, maxDay)
	else
		claimDay = 1
	end

	return {
		CurrentStreak = data.CurrentStreak,
		ClaimDay = claimDay,
		ClaimedToday = claimedToday,
		CanClaim = not claimedToday,
		LastClaimDay = data.LastClaimDay,
		Rewards = Config.Rewards,
	}
end

function DailyRewardManager.Claim(profileData, now: number?)
	local data = DailyRewardManager.EnsureData(profileData)
	local currentDay = getCurrentDayNumber(now)
	local status = DailyRewardManager.GetStatus(profileData, now)

	if not status.CanClaim then
		return false, "AlreadyClaimed", status, nil
	end

	data.CurrentStreak = status.ClaimDay
	data.LastClaimDay = currentDay

	local reward = Config.GetRewardForDay(status.ClaimDay)
	local updatedStatus = DailyRewardManager.GetStatus(profileData, now)

	return true, nil, updatedStatus, reward
end

return DailyRewardManager