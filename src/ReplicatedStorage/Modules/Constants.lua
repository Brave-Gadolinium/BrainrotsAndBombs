local Constants = {
	INCOME_SCALING = 1.125,
	RECYCLE_MIN_TIME = 30,
	RECYCLE_MAX_TIME = 90,
	RESPAWN_TIME = 300,
	DROPPED_LIFETIME = 30,
	SESSION_DURATION = 5 * 60,
	SESSION_END_MESSAGE_DURATION = 2,
	SESSION_WARNING_THRESHOLD = 10,
	MIN_ITEM_SPACING = 4.5,
	ZONE_ITEM_CAPS = {
		["Zone1"] = 300,
		["Zone2"] = 250,
		["Zone3"] = 200,
		["Zone4"] = 175,
		["Zone5"] = 150,
	},
	ITEM_SPAWN_BATCH_SIZE = 8,
	ITEM_SPAWN_BATCH_YIELD = 0.03,
	
	SPAWNER_TIERS = {
		["Zone1"] = { Common = 70, Uncommon = 30 },
		["Zone2"] = { Uncommon = 80, Rare = 20 },
		["Zone3"] = { Rare = 70, Epic = 30 },
		["Zone4"] = { Epic = 80, Legendary = 20 },
		["Zone5"] = { Epic = 10, Legendary = 90 },
	},
	
	DEFAULT_CHANCE = { Common = 100 },

	MUTATION_DEPTH_BANDS = {
		{ MaxDepthRatio = 0.20, Weights = { Normal = 100 } },
		{ MaxDepthRatio = 0.40, Weights = { Normal = 85, Golden = 15 } },
		{ MaxDepthRatio = 0.60, Weights = { Normal = 70, Golden = 20, Diamond = 10 } },
		{ MaxDepthRatio = 0.80, Weights = { Normal = 55, Golden = 20, Diamond = 15, Ruby = 10 } },
		{ MaxDepthRatio = 1.00, Weights = { Normal = 40, Golden = 18, Diamond = 18, Ruby = 14, Neon = 10 } },
	},

	MUTATION_MULTIPLIERS = {
		["Normal"] = 1,
		["Golden"] = 2.5,
		["Diamond"] = 5,
		["Ruby"] = 8,
		["Neon"] = 12,
	},

}

return Constants