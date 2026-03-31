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
		item_required = {"noobini_pizzanini"},
	},
	{
		lvl = 2,
		soft_required = 100000,
		item_required = {"bananini_kittini"},
	},
	{
		lvl = 3,
		soft_required = 500000,
		item_required = {"brr_brr_patapim"},
	},
	{
		lvl = 4,
		soft_required = 1000000,
		item_required = {"ballerina_cappuccina"},
	},
	{
		lvl = 5,
		soft_required = 5000000,
		item_required = {"chimpanzini_bananini"},
	},
	{
		lvl = 6,
		soft_required = 10000000,
		item_required = {"bombardiro_crocodilo"},
	},
	{
		lvl = 7,
		soft_required = 25000000,
		item_required = {"cocofanto_elefanto"},
	},
	{
		lvl = 8,
		soft_required = 50000000,
		item_required = {"girafa_celeste"},
	},
	{
		lvl = 9,
		soft_required = 100000000,
		item_required = {"gorillo_watermelondrillo"},
	},
	{
		lvl = 10,
		soft_required = 250000000,
		item_required = {"illuminato_triangolo"},
	},
	{
		lvl = 11,
		soft_required = 500000000,
		item_required = {"chicleteira_bicicleteira"},
	},
	{
		lvl = 12,
		soft_required = 1000000000,
		item_required = {"chicleteirina_bicicleteirina"},
	},
	{
		lvl = 13,
		soft_required = 2500000000,
		item_required = {"chillin_chili"},
	},
	{
		lvl = 14,
		soft_required = 5000000000,
		item_required = {"karkerkar_kurkur"},
	},
	{
		lvl = 15,
		soft_required = 10000000000,
		item_required = {"la_grande_combinasion"},
	},
	{
		lvl = 16,
		soft_required = 100000000000,
		item_required = {"ballerino_lololo"},
	},
	{
		lvl = 17,
		soft_required = 250000000000,
		item_required = {"dragon_cannelloni"},
	},
	{
		lvl = 18,
		soft_required = 500000000000,
		item_required = {"esok_sekolah"},
	},
	{
		lvl = 19,
		soft_required = 750000000000,
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
		item_required = {"noobini_pizzanini"},
	},
	{
		lvl = 2,
		soft_required = 100000,
		item_required = {"bananini_kittini"},
	},
	{
		lvl = 3,
		soft_required = 500000,
		item_required = {"brr_brr_patapim"},
	},
	{
		lvl = 4,
		soft_required = 1000000,
		item_required = {"ballerina_cappuccina"},
	},
	{
		lvl = 5,
		soft_required = 5000000,
		item_required = {"chimpanzini_bananini"},
	},
	{
		lvl = 6,
		soft_required = 10000000,
		item_required = {"bombardiro_crocodilo"},
	},
	{
		lvl = 7,
		soft_required = 25000000,
		item_required = {"cocofanto_elefanto"},
	},
	{
		lvl = 8,
		soft_required = 50000000,
		item_required = {"girafa_celeste"},
	},
	{
		lvl = 9,
		soft_required = 100000000,
		item_required = {"gorillo_watermelondrillo"},
	},
	{
		lvl = 10,
		soft_required = 250000000,
		item_required = {"illuminato_triangolo"},
	},
	{
		lvl = 11,
		soft_required = 500000000,
		item_required = {"chicleteira_bicicleteira"},
	},
	{
		lvl = 12,
		soft_required = 1000000000,
		item_required = {"chicleteirina_bicicleteirina"},
	},
	{
		lvl = 13,
		soft_required = 2500000000,
		item_required = {"chillin_chili"},
	},
	{
		lvl = 14,
		soft_required = 5000000000,
		item_required = {"karkerkar_kurkur"},
	},
	{
		lvl = 15,
		soft_required = 10000000000,
		item_required = {"la_grande_combinasion"},
	},
	{
		lvl = 16,
		soft_required = 100000000000,
		item_required = {"ballerino_lololo"},
	},
	{
		lvl = 17,
		soft_required = 250000000000,
		item_required = {"dragon_cannelloni"},
	},
	{
		lvl = 18,
		soft_required = 500000000000,
		item_required = {"esok_sekolah"},
	},
	{
		lvl = 19,
		soft_required = 750000000000,
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