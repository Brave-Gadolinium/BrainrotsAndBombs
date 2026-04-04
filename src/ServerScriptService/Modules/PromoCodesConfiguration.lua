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

export type Reward = MoneyReward | ItemReward

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
		Id = "hello",
		Code = "hello",
		Reward = {
			Type = "Item",
			ItemName = "blueberrinni_octopusini",
			Mutation = "Normal",
			Level = 1,
		},
		SuccessText = "Code redeemed! You got Blueberrinni Octopusini.",
	},
	{
		Id = "digdigdig",
		Code = "digdigdig",
		Reward = {
			Type = "Money",
			Amount = 10000000,
		},
		SuccessText = "Code redeemed! You got $10,000,000.",
	},
	{
		Id = "startergift",
		Code = "startergift",
		Reward = {
			Type = "Money",
			Amount = 50000,
		},
		SuccessText = "Code redeemed! You got $50,000.",
	},
	{
		Id = "cavecash",
		Code = "cavecash",
		Reward = {
			Type = "Money",
			Amount = 250000,
		},
		SuccessText = "Code redeemed! You got $250,000.",
	},
	{
		Id = "boomday",
		Code = "boomday",
		Reward = {
			Type = "Money",
			Amount = 1000000,
		},
		SuccessText = "Code redeemed! You got $1,000,000.",
	},
	{
		Id = "legenddrop",
		Code = "legenddrop",
		Reward = {
			Type = "Item",
			ItemName = "chimpanzini_bananini",
			Mutation = "Normal",
			Level = 1,
		},
		SuccessText = "Code redeemed! You got Chimpanzini Bananini.",
	},
	{
		Id = "mythrush",
		Code = "mythrush",
		Reward = {
			Type = "Item",
			ItemName = "bombardiro_crocodilo",
			Mutation = "Normal",
			Level = 1,
		},
		SuccessText = "Code redeemed! You got Bombardiro Crocodilo.",
	},
	{
		Id = "luckybrain",
		Code = "luckybrain",
		Reward = {
			Type = "Item",
			ItemName = "cocofanto_elefanto",
			Mutation = "Normal",
			Level = 1,
		},
		SuccessText = "Code redeemed! You got Cocofanto Elefanto.",
	},
	{
		Id = "secretstash",
		Code = "secretstash",
		Reward = {
			Type = "Item",
			ItemName = "chillin_chili",
			Mutation = "Normal",
			Level = 1,
		},
		SuccessText = "Code redeemed! You got Chillin Chili.",
	},
	{
		Id = "richmine",
		Code = "richmine",
		Reward = {
			Type = "Money",
			Amount = 5000000,
		},
		SuccessText = "Code redeemed! You got $5,000,000.",
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
