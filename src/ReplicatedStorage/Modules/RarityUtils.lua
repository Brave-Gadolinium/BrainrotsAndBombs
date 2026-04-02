--!strict

local RarityUtils = {}

local ALIASES = {
	Mythical = "Mythic",
	["Brainrot God"] = "Brainrotgod",
} :: {[string]: string}

local DISPLAY_NAMES = {
	Brainrotgod = "Brainrot God",
} :: {[string]: string}

function RarityUtils.Normalize(rarity: string?): string?
	if type(rarity) ~= "string" or rarity == "" then
		return nil
	end

	return ALIASES[rarity] or rarity
end

function RarityUtils.GetDisplayName(rarity: string?): string?
	local normalized = RarityUtils.Normalize(rarity)
	if not normalized then
		return nil
	end

	return DISPLAY_NAMES[normalized] or normalized
end

return RarityUtils
