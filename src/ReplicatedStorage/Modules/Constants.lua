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
	MINE_STARTUP_ZONE_ORDER = {
		"Zone0",
		"Zone1",
		"Zone2",
		"Zone3",
		"Zone4",
		"Zone5",
	},
	MINE_STARTUP_ZONE_DELAY_SECONDS = 0,
	TERRAIN_STARTUP_SLICE_HEIGHT = 100,
	MINE_STARTUP_INITIAL_SEED_RATIO = 0.15,
	MINE_STARTUP_INITIAL_SEED_MINIMUM = 12,
	MINE_STARTUP_BACKFILL_CHUNK_RATIO = 0.05,
	MINE_STARTUP_DEPTH_BANDS = {
		{ MinDepthRatio = 0.00, MaxDepthRatio = 0.35 },
		{ MinDepthRatio = 0.35, MaxDepthRatio = 0.65 },
		{ MinDepthRatio = 0.65, MaxDepthRatio = 1.00 },
	},
	ZONE_ITEM_CAPS = {
		["Zone0"] = 5,
		["Zone1"] = 30,
		["Zone2"] = 30,
		["Zone3"] = 30,
		["Zone4"] = 30,
		["Zone5"] = 25,
	},

	ITEM_SPAWN_BATCH_SIZE = 300,
	ITEM_SPAWN_BATCH_YIELD = 0.01,
	
	SPAWNER_TIERS = {
		["Zone0"] = { Common = 70, Uncommon = 30 },
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
