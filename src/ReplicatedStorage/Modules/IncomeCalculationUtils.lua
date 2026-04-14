--!strict
-- LOCATION: ReplicatedStorage/Modules/IncomeCalculationUtils

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Modules.Constants)
local MultiplierUtils = require(ReplicatedStorage.Modules.MultiplierUtils)

local IncomeCalculationUtils = {}

local LEGACY_MUTATION_MULTIPLIERS = {
	["Normal"] = 1,
	["Golden"] = 2,
	["Diamond"] = 3,
	["Ruby"] = 4,
	["Neon"] = 5,
}

local VIP_MULTIPLIER = 1.5

function IncomeCalculationUtils.GetMutationMultiplier(mutation: string?): number
	if type(mutation) ~= "string" then
		return 1
	end

	return LEGACY_MUTATION_MULTIPLIERS[mutation] or 1
end

function IncomeCalculationUtils.GetLevelMultiplier(level: number?): number
	local resolvedLevel = math.max(1, math.floor(tonumber(level) or 1))
	return Constants.INCOME_SCALING ^ (resolvedLevel - 1)
end

function IncomeCalculationUtils.GetVipMultiplier(isVip: boolean?): number
	return isVip == true and VIP_MULTIPLIER or 1
end

function IncomeCalculationUtils.ComputeBaseIncomePerSecond(baseIncome: number, mutation: string?, level: number?): number
	local resolvedBaseIncome = math.max(0, tonumber(baseIncome) or 0)
	return resolvedBaseIncome
		* IncomeCalculationUtils.GetMutationMultiplier(mutation)
		* IncomeCalculationUtils.GetLevelMultiplier(level)
end

function IncomeCalculationUtils.ComputeOnlineIncomePerSecond(
	baseIncome: number,
	mutation: string?,
	level: number?,
	rebirths: number?,
	isVip: boolean?,
	friendBoostMultiplier: number?
): number
	local resolvedFriendBoost = math.max(1, tonumber(friendBoostMultiplier) or 1)
	return IncomeCalculationUtils.ComputeBaseIncomePerSecond(baseIncome, mutation, level)
		* MultiplierUtils.GetRebirthMultiplier(rebirths)
		* IncomeCalculationUtils.GetVipMultiplier(isVip)
		* resolvedFriendBoost
end

function IncomeCalculationUtils.ComputeOfflineIncomePerSecond(
	baseIncome: number,
	mutation: string?,
	level: number?,
	rebirths: number?,
	isVip: boolean?
): number
	return IncomeCalculationUtils.ComputeBaseIncomePerSecond(baseIncome, mutation, level)
		* MultiplierUtils.GetRebirthMultiplier(rebirths)
		* IncomeCalculationUtils.GetVipMultiplier(isVip)
end

return IncomeCalculationUtils
