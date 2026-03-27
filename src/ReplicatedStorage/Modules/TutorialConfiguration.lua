--!strict

local TutorialConfiguration = {}

export type TutorialStepDefinition = {
	Text: string,
	TargetType: string,
}

TutorialConfiguration.FinalStep = 9
TutorialConfiguration.CashGoal = 100

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
		Text = "Collect $100 cash",
		TargetType = "WorldCollectButton",
	},
	[7] = {
		Text = "Open the bomb shop",
		TargetType = "GuiShopButton",
	},
	[8] = {
		Text = "Buy the bomb",
		TargetType = "GuiBuyBombButton",
	},
	[9] = {
		Text = "Well done! Upgrade your bomb and search for rare Brainrots in the depths!",
		TargetType = "None",
	},
} :: {[number]: TutorialStepDefinition}

return TutorialConfiguration
