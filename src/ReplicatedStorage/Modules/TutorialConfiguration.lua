--!strict

local TutorialConfiguration = {}

export type TutorialStepDefinition = {
	Text: string,
	TargetType: string,
}

TutorialConfiguration.FinalStep = 13
TutorialConfiguration.CashGoal = 50
TutorialConfiguration.TutorialCharacterUpgradeId = "Speed1"
TutorialConfiguration.TutorialBaseUpgradeMode = "FirstSlotUnlock"
TutorialConfiguration.LegacyCompletedFinalStep = 9
TutorialConfiguration.BaseUpgradeApproachDistance = 20
TutorialConfiguration.CompletionMessageDuration = 10

TutorialConfiguration.Steps = {
	[1] = {
		Text = "Walk to the mining zone",
		TargetType = "WorldMineZone",
	},
	[2] = {
		Text = "Throw a bomb to find Brainrots",
		TargetType = "GuiEquippedBomb",
	},
	[3] = {
		Text = "Pick up the Brainrot",
		TargetType = "WorldBrainrot",
	},
	[4] = {
		Text = "Go to the surface",
		TargetType = "GuiBackButton",
	},
	[5] = {
		Text = "Place Brainrot on your base",
		TargetType = "HybridInventoryOrSlot",
	},
	[6] = {
		Text = "Collect $50 cash",
		TargetType = "WorldCollectButton",
	},
	[7] = {
		Text = "Upgrade your bomb",
		TargetType = "GuiShopButton",
	},
	[8] = {
		Text = "Buy Venom Bomb",
		TargetType = "GuiBuyBombButton",
	},
	[9] = {
		Text = "Upgrade your character",
		TargetType = "WorldCharacterUpgrade",
	},
	[10] = {
		Text = "Well done! Upgrade your character and become faster!",
		TargetType = "GuiCharacterUpgradeButton",
	},
	[11] = {
		Text = "Make base upgrade",
		TargetType = "WorldBaseUpgrade",
	},
	[12] = {
		Text = "Well done! Upgrade your base and get more money!",
		TargetType = "GuiBaseUpgradeButton",
	},
	[13] = {
		Text = "Well done! Upgrade your bomb and search for rare Brainrots in the depths!",
		TargetType = "None",
	},
} :: {[number]: TutorialStepDefinition}

return TutorialConfiguration
