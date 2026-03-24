--!strict
-- LOCATION: ReplicatedStorage/Modules/LuckyBlockConfiguration

local LuckyBlockConfiguration = {}

export type RewardEntry = {
	ItemName: string,
	Weight: number,
}

export type LuckyBlockEntry = {
	Id: string,
	DisplayName: string,
	Image: string,
	Rarity: string,
	Scale: number,
	ModelName: string,
	Rewards: { RewardEntry },
}

LuckyBlockConfiguration.Blocks = {
	luckyblock_common = {
		Id = "luckyblock_common",
		DisplayName = "COMMON BLOCK",
		Image = "rbxassetid://91834580706569",
		Rarity = "Common",
		Scale = 1,
		ModelName = "luckyblock_common",
		Rewards = {
			{ ItemName = "noobini_pizzanini", Weight = 19 },
			{ ItemName = "pipi_kiwi", Weight = 19 },
			{ ItemName = "tim_cheese", Weight = 19 },
			{ ItemName = "svinina_bombardino", Weight = 19 },
			{ ItemName = "talpa_di_fero", Weight = 19 },
			{ ItemName = "bananini_kittini", Weight = 1 },
			{ ItemName = "bobrito_bandito", Weight = 1 },
			{ ItemName = "boneca_ambalabu", Weight = 1 },
			{ ItemName = "fluri_flura", Weight = 1 },
			{ ItemName = "gangster_footera", Weight = 1 },
		},
	} :: LuckyBlockEntry,
	luckyblock_rare = {
		Id = "luckyblock_rare",
		DisplayName = "RARE BLOCK",
		Image = "rbxassetid://78540026394217",
		Rarity = "Rare",
		Scale = 1.2,
		ModelName = "luckyblock_rare",
		Rewards = {
			{ ItemName = "bananini_kittini", Weight = 7.8 },
			{ ItemName = "bobrito_bandito", Weight = 7.8 },
			{ ItemName = "boneca_ambalabu", Weight = 7.8 },
			{ ItemName = "fluri_flura", Weight = 7.8 },
			{ ItemName = "gangster_footera", Weight = 7.8 },
			{ ItemName = "banana_dancana", Weight = 12 },
			{ ItemName = "bananita_dolphinita", Weight = 12 },
			{ ItemName = "brr_brr_patapim", Weight = 12 },
			{ ItemName = "cacto_hipopotamo", Weight = 12 },
			{ ItemName = "ta_ta_ta_ta_sahur", Weight = 12 },
			{ ItemName = "avocadini_guffo", Weight = 0.2 },
			{ ItemName = "ballerina_cappuccina", Weight = 0.2 },
			{ ItemName = "bambini_crostini", Weight = 0.2 },
			{ ItemName = "brri_brri_bicus_dicus", Weight = 0.2 },
			{ ItemName = "cappuccino_assassino", Weight = 0.2 },
		},
	} :: LuckyBlockEntry,
	luckyblock_epic = {
		Id = "luckyblock_epic",
		DisplayName = "EPIC BLOCK",
		Image = "rbxassetid://119662372487092",
		Rarity = "Epic",
		Scale = 1.4,
		ModelName = "luckyblock_epic",
		Rewards = {
			{ ItemName = "avocadini_guffo", Weight = 19.6 },
			{ ItemName = "ballerina_cappuccina", Weight = 19.6 },
			{ ItemName = "bambini_crostini", Weight = 19.6 },
			{ ItemName = "brri_brri_bicus_dicus", Weight = 19.6 },
			{ ItemName = "cappuccino_assassino", Weight = 19.6 },
			{ ItemName = "blueberrinni_octopusini", Weight = 0.4 },
			{ ItemName = "bombombini_gusini", Weight = 0.4 },
			{ ItemName = "burbaloni_luliloli", Weight = 0.4 },
			{ ItemName = "cavallo_virtuoso", Weight = 0.4 },
			{ ItemName = "chimpanzini_bananini", Weight = 0.4 },
		},
	} :: LuckyBlockEntry,
	luckyblock_legendary = {
		Id = "luckyblock_legendary",
		DisplayName = "LEGENDARY BLOCK",
		Image = "rbxassetid://111304202358633",
		Rarity = "Legendary",
		Scale = 1.6,
		ModelName = "luckyblock_legendary",
		Rewards = {
			{ ItemName = "blueberrinni_octopusini", Weight = 19.6 },
			{ ItemName = "bombombini_gusini", Weight = 19.6 },
			{ ItemName = "burbaloni_luliloli", Weight = 19.6 },
			{ ItemName = "cavallo_virtuoso", Weight = 19.6 },
			{ ItemName = "chimpanzini_bananini", Weight = 19.6 },
			{ ItemName = "bombardiro_crocodilo", Weight = 0.4 },
			{ ItemName = "cocofanto_elefanto", Weight = 0.4 },
			{ ItemName = "girafa_celeste", Weight = 0.4 },
			{ ItemName = "gorillo_watermelondrillo", Weight = 0.4 },
			{ ItemName = "illuminato_triangolo", Weight = 0.4 },
		},
	} :: LuckyBlockEntry,
	luckyblock_mythic = {
		Id = "luckyblock_mythic",
		DisplayName = "MYTHIC BLOCK",
		Image = "rbxassetid://72804494822487",
		Rarity = "Mythic",
		Scale = 1.8,
		ModelName = "luckyblock_mythic",
		Rewards = {
			{ ItemName = "bombardiro_crocodilo", Weight = 19.6 },
			{ ItemName = "cocofanto_elefanto", Weight = 19.6 },
			{ ItemName = "girafa_celeste", Weight = 19.6 },
			{ ItemName = "gorillo_watermelondrillo", Weight = 19.6 },
			{ ItemName = "illuminato_triangolo", Weight = 19.6 },
			{ ItemName = "chicleteira_bicicleteira", Weight = 0.4 },
			{ ItemName = "chicleteirina_bicicleteirina", Weight = 0.4 },
			{ ItemName = "chillin_chili", Weight = 0.4 },
			{ ItemName = "karkerkar_kurkur", Weight = 0.4 },
			{ ItemName = "la_grande_combinasion", Weight = 0.4 },
		},
	} :: LuckyBlockEntry,
	luckyblock_secret = {
		Id = "luckyblock_secret",
		DisplayName = "SECRET BLOCK",
		Image = "rbxassetid://72804494822487",
		Rarity = "Secret",
		Scale = 1,
		ModelName = "luckyblock_secret",
		Rewards = {
			{ ItemName = "chicleteira_bicicleteira", Weight = 20 },
			{ ItemName = "chicleteirina_bicicleteirina", Weight = 20 },
			{ ItemName = "chillin_chili", Weight = 20 },
			{ ItemName = "karkerkar_kurkur", Weight = 20 },
			{ ItemName = "la_grande_combinasion", Weight = 20 },
		},
	} :: LuckyBlockEntry,
	luckyblock_brainrotgod = {
		Id = "luckyblock_brainrotgod",
		DisplayName = "BRAINROT GOD BLOCK",
		Image = "rbxassetid://122610658176402",
		Rarity = "Brainrotgod",
		Scale = 1,
		ModelName = "luckyblock_brainrotgod",
		Rewards = {
			{ ItemName = "esok_sekolah", Weight = 25 },
			{ ItemName = "matteo", Weight = 25 },
			{ ItemName = "dragon_cannelloni", Weight = 25 },
			{ ItemName = "espresso_signora", Weight = 25 },
		},
	} :: LuckyBlockEntry,
	luckyblock_hacker = {
		Id = "luckyblock_hacker",
		DisplayName = "HACKER BLOCK",
		Image = "rbxassetid://81186916558689",
		Rarity = "Brainrotgod",
		Scale = 2.4,
		ModelName = "luckyblock_hacker",
		Rewards = {
			{ ItemName = "la_grande_combinasion", Weight = 30 },
			{ ItemName = "esok_sekolah", Weight = 25 },
			{ ItemName = "matteo", Weight = 20 },
			{ ItemName = "dragon_cannelloni", Weight = 15 },
			{ ItemName = "espresso_signora", Weight = 10 },
		},
	} :: LuckyBlockEntry,
}

function LuckyBlockConfiguration.GetBlockConfig(blockId: string): LuckyBlockEntry?
	return LuckyBlockConfiguration.Blocks[blockId]
end

function LuckyBlockConfiguration.GetAllBlocks(): { [string]: LuckyBlockEntry }
	return LuckyBlockConfiguration.Blocks
end

return LuckyBlockConfiguration