--!strict

local RebirthRequirements = {}

export type RebirthRequirement = {
	lvl: number,
	soft_required: number,
	item_required: {string}?,
}

local REQUIREMENTS: {RebirthRequirement} = {
	{
		lvl = 1,
		soft_required = 25000,
		item_required = {"tim_cheese"},
	},
	{
		lvl = 2,
		soft_required = 120000,
		item_required = {"talpa_di_fero"},
	},
}

local requirementsByLevel: {[number]: RebirthRequirement} = {}

for _, requirement in ipairs(REQUIREMENTS) do
	requirementsByLevel[requirement.lvl] = requirement
end

function RebirthRequirements.Get(level: number): RebirthRequirement?
	return requirementsByLevel[level]
end

function RebirthRequirements.GetAll(): {RebirthRequirement}
	return REQUIREMENTS
end

return RebirthRequirements
