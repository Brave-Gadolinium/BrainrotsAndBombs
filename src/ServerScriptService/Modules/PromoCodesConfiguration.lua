--!strict
-- LOCATION: ServerScriptService/Modules/PromoCodesConfiguration

local PromoCodesConfiguration = {}

export type MoneyReward = {
	Type: "Money",
	Amount: number,
}

export type ItemReward = {
	Type: "Item",
	ItemName: string,
	Mutation: string?,
	Level: number?,
}

export type RandomItemsReward = {
	Type: "RandomItems",
	Rarity: string,
	Count: number,
	Mutation: string?,
	Level: number?,
}

export type BundleReward = {
	Type: "Bundle",
	Rewards: {Reward},
}

export type Reward = MoneyReward | ItemReward | RandomItemsReward | BundleReward

export type PromoCodeEntry = {
	Id: string,
	Code: string,
	Reward: Reward,
	SuccessText: string,
}

local function trim(value: string): string
	return value:match("^%s*(.-)%s*$") or ""
end

local function normalizeCode(rawCode: string): string
	return string.lower(trim(rawCode))
end

local entries: {PromoCodeEntry} = {
	{
		Id = "release",
		Code = "RELEASE",
		Reward = {
			Type = "Bundle",
			Rewards = {
				{
					Type = "Money",
					Amount = 100000,
				},
				{
					Type = "RandomItems",
					Rarity = "Legendary",
					Count = 3,
					Mutation = "Normal",
					Level = 1,
				},
			},
		},
		SuccessText = "Code redeemed! You got $100,000 and 3 random Legendary Brainrots.",
	},
	{
		Id = "deepexplorer",
		Code = "DEEPEXPLORER",
		Reward = {
			Type = "Bundle",
			Rewards = {
				{
					Type = "Money",
					Amount = 100000000,
				},
				{
					Type = "RandomItems",
					Rarity = "Mythic",
					Count = 3,
					Mutation = "Normal",
					Level = 1,
				},
			},
		},
		SuccessText = "Code redeemed! You got $100,000,000 and 3 random Mythic Brainrots.",
	},
}

local lookupByNormalizedCode: {[string]: PromoCodeEntry} = {}

for _, entry in ipairs(entries) do
	local normalizedCode = normalizeCode(entry.Code)
	assert(normalizedCode ~= "", `[PromoCodesConfiguration] Code "{entry.Id}" cannot be empty.`)
	assert(lookupByNormalizedCode[normalizedCode] == nil, `[PromoCodesConfiguration] Duplicate code "{normalizedCode}".`)
	lookupByNormalizedCode[normalizedCode] = entry
end

PromoCodesConfiguration.Entries = entries

function PromoCodesConfiguration.NormalizeCode(rawCode: string?): string
	if type(rawCode) ~= "string" then
		return ""
	end

	return normalizeCode(rawCode)
end

function PromoCodesConfiguration.GetByNormalizedCode(normalizedCode: string?): PromoCodeEntry?
	if type(normalizedCode) ~= "string" or normalizedCode == "" then
		return nil
	end

	return lookupByNormalizedCode[normalizedCode]
end

function PromoCodesConfiguration.GetByCode(rawCode: string?): PromoCodeEntry?
	return PromoCodesConfiguration.GetByNormalizedCode(PromoCodesConfiguration.NormalizeCode(rawCode))
end

return table.freeze(PromoCodesConfiguration)
