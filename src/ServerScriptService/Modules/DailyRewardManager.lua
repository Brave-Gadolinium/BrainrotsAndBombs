--!strict
-- LOCATION: ServerScriptService/Modules/DailyRewardManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.DailyRewardConfiguration)

local DailyRewardManager = {}

export type DayStateMap = { [string]: boolean }

export type DailyRewardData = {
	CurrentStreak: number,
	LastClaimDay: number,
	AvailableClaimDays: DayStateMap,
	ClaimedRewardDays: DayStateMap,
}

export type DailyRewardStatus = {
	CurrentStreak: number,
	ClaimDay: number,
	ClaimedToday: boolean,
	CanClaim: boolean,
	LastClaimDay: number,
	Rewards: { [number]: any },
	AvailableClaimDays: DayStateMap,
	ClaimedRewardDays: DayStateMap,
}

local function getCurrentDayNumber(now: number?): number
	return math.floor((now or os.time()) / 86400)
end

local function getDayKey(day: number): string
	return tostring(day)
end

local function hasDay(dayMap: DayStateMap, day: number): boolean
	local key = getDayKey(day)
	local anyDayMap = dayMap :: any
	return dayMap[key] == true or anyDayMap[day] == true
end

local function setDay(dayMap: DayStateMap, day: number, value: boolean?)
	local key = getDayKey(day)
	local anyDayMap = dayMap :: any
	anyDayMap[day] = nil
	dayMap[key] = value == true or nil
end

local function normalizeDayMap(dayMap): DayStateMap
	local normalized: DayStateMap = {}

	if type(dayMap) ~= "table" then
		return normalized
	end

	for key, value in pairs(dayMap) do
		if value == true then
			if type(key) == "number" then
				normalized[tostring(key)] = true
			elseif type(key) == "string" then
				normalized[key] = true
			end
		end
	end

	return normalized
end

local function hasAnyAvailableRewards(days: DayStateMap): boolean
	return next(days) ~= nil
end

local function resetCycle(data: DailyRewardData)
	data.CurrentStreak = 0
	data.LastClaimDay = 0
	data.AvailableClaimDays = {}
	data.ClaimedRewardDays = {}
end

local function startCycleForToday(data: DailyRewardData, currentDay: number)
	resetCycle(data)
	data.CurrentStreak = 1
	data.LastClaimDay = currentDay
	setDay(data.AvailableClaimDays, 1, true)
end

local function advanceCycleForToday(data: DailyRewardData, currentDay: number, maxDay: number)
	local nextDay = data.CurrentStreak >= maxDay and 1 or math.clamp(data.CurrentStreak + 1, 1, maxDay)

	if nextDay == 1 then
		data.AvailableClaimDays = {}
		data.ClaimedRewardDays = {}
	end

	data.CurrentStreak = nextDay
	data.LastClaimDay = currentDay

	if not hasDay(data.ClaimedRewardDays, nextDay) then
		setDay(data.AvailableClaimDays, nextDay, true)
	end
end

local function normalizeForCurrentDay(profileData, now: number?): (DailyRewardData, number, number)
	local data = DailyRewardManager.EnsureData(profileData)
	local currentDay = getCurrentDayNumber(now)
	local maxDay = Config.GetMaxDay()

	if data.LastClaimDay == currentDay then
		if data.CurrentStreak <= 0 then
			data.CurrentStreak = 1
		end

		if not hasDay(data.ClaimedRewardDays, data.CurrentStreak) then
			setDay(data.AvailableClaimDays, data.CurrentStreak, true)
		end

		return data, currentDay, maxDay
	end

	if data.LastClaimDay == currentDay - 1 and data.CurrentStreak > 0 then
		advanceCycleForToday(data, currentDay, maxDay)
	else
		startCycleForToday(data, currentDay)
	end

	return data, currentDay, maxDay
end

function DailyRewardManager.EnsureData(profileData): DailyRewardData
	profileData.DailyRewards = profileData.DailyRewards or {
		CurrentStreak = 0,
		LastClaimDay = 0,
		AvailableClaimDays = {},
		ClaimedRewardDays = {},
	}

	local data = profileData.DailyRewards

	if type(data.CurrentStreak) ~= "number" then
		data.CurrentStreak = 0
	end

	if type(data.LastClaimDay) ~= "number" then
		data.LastClaimDay = 0
	end

	data.AvailableClaimDays = normalizeDayMap(data.AvailableClaimDays)
	data.ClaimedRewardDays = normalizeDayMap(data.ClaimedRewardDays)

	return data
end

function DailyRewardManager.GetStatus(profileData, now: number?): DailyRewardStatus
	local data, currentDay, maxDay = normalizeForCurrentDay(profileData, now)

	return {
		CurrentStreak = data.CurrentStreak,
		ClaimDay = math.clamp(data.CurrentStreak, 1, maxDay),
		ClaimedToday = data.LastClaimDay == currentDay,
		CanClaim = hasAnyAvailableRewards(data.AvailableClaimDays),
		LastClaimDay = data.LastClaimDay,
		Rewards = Config.Rewards,
		AvailableClaimDays = data.AvailableClaimDays,
		ClaimedRewardDays = data.ClaimedRewardDays,
	}
end

function DailyRewardManager.GetUnopenedRewardDays(profileData, now: number?): { number }
	local data, _, maxDay = normalizeForCurrentDay(profileData, now)
	local days = {}

	for day = data.CurrentStreak + 1, maxDay do
		if not hasDay(data.AvailableClaimDays, day) and not hasDay(data.ClaimedRewardDays, day) then
			table.insert(days, day)
		end
	end

	return days
end

function DailyRewardManager.UnlockDay(profileData, day: number, now: number?): (boolean, string?, DailyRewardStatus)
	local data, _, maxDay = normalizeForCurrentDay(profileData, now)

	if day < 1 or day > maxDay then
		return false, "RewardNotFound", DailyRewardManager.GetStatus(profileData, now)
	end

	if hasDay(data.ClaimedRewardDays, day) or hasDay(data.AvailableClaimDays, day) then
		return true, nil, DailyRewardManager.GetStatus(profileData, now)
	end

	setDay(data.AvailableClaimDays, day, true)
	if day > data.CurrentStreak then
		data.CurrentStreak = day
	end

	return true, nil, DailyRewardManager.GetStatus(profileData, now)
end

function DailyRewardManager.GetClaimableReward(profileData, day: number, now: number?)
	local data = DailyRewardManager.EnsureData(profileData)
	local status = DailyRewardManager.GetStatus(profileData, now)
	local maxDay = Config.GetMaxDay()

	if day < 1 or day > maxDay then
		return false, "RewardNotFound", status, nil
	end

	if hasDay(data.ClaimedRewardDays, day) then
		return false, "AlreadyClaimed", status, nil
	end

	if not hasDay(data.AvailableClaimDays, day) then
		return false, "RewardLocked", status, nil
	end

	local reward = Config.GetRewardForDay(day)
	if not reward then
		return false, "RewardNotFound", status, nil
	end

	return true, nil, status, reward
end

function DailyRewardManager.MarkRewardClaimed(profileData, day: number, now: number?): (boolean, string?, DailyRewardStatus)
	local data = DailyRewardManager.EnsureData(profileData)
	local status = DailyRewardManager.GetStatus(profileData, now)
	local maxDay = Config.GetMaxDay()

	if day < 1 or day > maxDay then
		return false, "RewardNotFound", status
	end

	if hasDay(data.ClaimedRewardDays, day) then
		return false, "AlreadyClaimed", status
	end

	if not hasDay(data.AvailableClaimDays, day) then
		return false, "RewardLocked", status
	end

	setDay(data.AvailableClaimDays, day, false)
	setDay(data.ClaimedRewardDays, day, true)

	return true, nil, DailyRewardManager.GetStatus(profileData, now)
end

return DailyRewardManager
