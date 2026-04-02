local Constants = {
	INCOME_SCALING = 1.125,
	RECYCLE_MIN_TIME = 30,
	RECYCLE_MAX_TIME = 90,
	RESPAWN_TIME = 300,
	DROPPED_LIFETIME = 30,
	SESSION_DURATION = 5 * 60,
	SESSION_END_MESSAGE_DURATION = 2,
	SESSION_WARNING_THRESHOLD = 10,
	MAX_ITEMS_PER_MINE = 45,
	MIN_ITEM_SPACING = 4.5,
	ZONE_ITEM_CAP_MULTIPLIERS = {
		["Zone1"] = 4,
		["Zone2"] = 3,
		["Zone3"] = 3,
		["Zone4"] = 2,
		["Zone5"] = 2,
	},
	
	SPAWNER_TIERS = {
		["Zone1"] = { Common = 75, Uncommon = 25 },
		["Zone2"] = { Uncommon = 60, Rare = 30, Epic = 10 },
		["Zone3"] = { Rare = 40, Epic = 40, Legendary = 20 },
		["Zone4"] = { Epic = 30, Legendary = 50, Mythic = 20 },
		["Zone5"] = { Epic = 10, Legendary = 40, Mythic = 50 },
	},
	
	DEFAULT_CHANCE = { Common = 100 },

	MUTATIONS = {
		{Name = "Neon", Chance = 100},
		{Name = "Ruby", Chance = 50},
		{Name = "Diamond", Chance = 25},
		{Name = "Golden", Chance = 10},
	},

	MUTATION_MULTIPLIERS = {
		["Normal"] = 1,
		["Golden"] = 2,
		["Diamond"] = 3,
		["Ruby"] = 4,
		["Neon"] = 5,
	},

}

return Constants
