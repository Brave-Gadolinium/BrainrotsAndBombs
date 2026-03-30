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
	{
		lvl = 3,
		soft_required = 450000,
		item_required = {"bobrito_bandito"},
	},
	{
		lvl = 4,
		soft_required = 1200000,
		item_required = {"fluri_flura"},
	},
	{
		lvl = 5,
		soft_required = 3000000,
		item_required = {"banana_dancana"},
	},
	{
		lvl = 6,
		soft_required = 8000000,
		item_required = {"cacto_hipopotamo"},
	},
	{
		lvl = 7,
		soft_required = 20000000,
		item_required = {"ballerina_cappuccina"},
	},
	{
		lvl = 8,
		soft_required = 50000000,
		item_required = {"cappuccino_assassino"},
	},
	{
		lvl = 9,
		soft_required = 120000000,
		item_required = {"bombombini_gusini"},
	},
	{
		lvl = 10,
		soft_required = 300000000,
		item_required = {"chimpanzini_bananini"},
	},
	{
		lvl = 11,
		soft_required = 750000000,
		item_required = {"bombardiro_crocodilo"},
	},
	{
		lvl = 12,
		soft_required = 1800000000,
		item_required = {"girafa_celeste"},
	},
	{
		lvl = 13,
		soft_required = 4000000000,
		item_required = {"illuminato_triangolo"},
	},
	{
		lvl = 14,
		soft_required = 9000000000,
		item_required = {"chillin_chili"},
	},
	{
		lvl = 15,
		soft_required = 20000000000,
		item_required = {"la_grande_combinasion"},
	},
	{
		lvl = 16,
		soft_required = 45000000000,
		item_required = {"ballerino_lololo"},
	},
	{
		lvl = 17,
		soft_required = 100000000000,
		item_required = {"dragon_cannelloni"},
	},
	{
		lvl = 18,
		soft_required = 220000000000,
		item_required = {"esok_sekolah"},
	},
	{
		lvl = 19,
		soft_required = 500000000000,
		item_required = {"espresso_signora"},
	},
	{
		lvl = 20,
		soft_required = 1000000000000,
		item_required = {"matteo"},
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
