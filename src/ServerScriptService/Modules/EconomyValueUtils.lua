--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Modules.Constants)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local LuckyBlockConfiguration = require(ReplicatedStorage.Modules.LuckyBlockConfiguration)

local EconomyValueUtils = {}

local INCOME_SCALING = Constants.INCOME_SCALING
local MUTATION_MULTIPLIERS = Constants.MUTATION_MULTIPLIERS
local SELL_SECONDS_MULTIPLIER = 300

local function getMutationMultiplier(mutation: string?): number
	if type(mutation) ~= "string" then
		return 1
	end

	return MUTATION_MULTIPLIERS[mutation] or 1
end

function EconomyValueUtils.GetItemReferencePrice(itemName: string, mutation: string?, level: number?): number
	local itemData = ItemConfigurations.GetItemData(itemName)
	if not itemData then
		return 0
	end

	local itemLevel = math.max(1, tonumber(level) or 1)
	local mutationMultiplier = getMutationMultiplier(mutation)
	local incomePerSecond = itemData.Income * mutationMultiplier * (INCOME_SCALING ^ (itemLevel - 1))
	return math.floor(incomePerSecond * SELL_SECONDS_MULTIPLIER)
end

function EconomyValueUtils.GetToolReferencePrice(tool: Tool): number
	local luckyBlockId = tool:GetAttribute("LuckyBlockId")
	if type(luckyBlockId) == "string" then
		return EconomyValueUtils.GetLuckyBlockReferencePrice(luckyBlockId)
	end

	local itemName = tool:GetAttribute("OriginalName")
	if type(itemName) ~= "string" then
		return 0
	end

	local mutation = tool:GetAttribute("Mutation")
	local level = tool:GetAttribute("Level")
	return EconomyValueUtils.GetItemReferencePrice(itemName, if type(mutation) == "string" then mutation else "Normal", tonumber(level) or 1)
end

function EconomyValueUtils.GetLuckyBlockReferencePrice(blockId: string): number
	local blockConfig = LuckyBlockConfiguration.GetBlockConfig(blockId)
	if not blockConfig or not blockConfig.Rewards or #blockConfig.Rewards == 0 then
		return 0
	end

	local totalWeight = 0
	for _, reward in ipairs(blockConfig.Rewards) do
		totalWeight += reward.Weight
	end

	if totalWeight <= 0 then
		return 0
	end

	local expectedValue = 0
	for _, reward in ipairs(blockConfig.Rewards) do
		expectedValue += (reward.Weight / totalWeight) * EconomyValueUtils.GetItemReferencePrice(reward.ItemName, "Normal", 1)
	end

	return math.floor(expectedValue)
end

return EconomyValueUtils
