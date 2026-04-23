--!strict

local TutorialConfiguration = {}
local TutorialUiConfiguration = require(script.Parent.TutorialUiConfiguration)

export type TutorialStepDefinition = {
	Text: string,
	TargetType: string,
}

export type TutorialStepPresentation = {
	MaskUi: boolean,
	ShowText: boolean,
	ShowMoney: boolean,
	ShowInventory: boolean,
	ShowBombShopButton: boolean,
	ShowPickaxesFrame: boolean,
	ShowUpgradesFrame: boolean,
	ShowBaseUpgradeSurfaceButton: boolean,
	ShowMobileBombButton: boolean,
	ShowJumpButton: boolean,
	ShowBackButton: boolean,
	BackProxyScale: number,
	UseBlackout: boolean,
}

TutorialConfiguration.FinalStep = 10
TutorialConfiguration.TutorialCharacterUpgradeId = "Speed1"
TutorialConfiguration.TutorialBaseUpgradeMode = "FirstSlotUnlock"
TutorialConfiguration.LegacyCompletedFinalStep = 9
TutorialConfiguration.BaseUpgradeApproachDistance = 20
TutorialConfiguration.PlotSpawnUnlockStep = 5
TutorialConfiguration.CompletionMessageDuration = 10

local DEFAULT_STEP_PRESENTATION: TutorialStepPresentation = {
	MaskUi = false,
	ShowText = false,
	ShowMoney = false,
	ShowInventory = false,
	ShowBombShopButton = false,
	ShowPickaxesFrame = false,
	ShowUpgradesFrame = false,
	ShowBaseUpgradeSurfaceButton = false,
	ShowMobileBombButton = false,
	ShowJumpButton = false,
	ShowBackButton = false,
	BackProxyScale = 1,
	UseBlackout = false,
}

local FULL_UI_STEP_PRESENTATION: TutorialStepPresentation = {
	MaskUi = false,
	ShowText = true,
	ShowMoney = true,
	ShowInventory = false,
	ShowBombShopButton = false,
	ShowPickaxesFrame = false,
	ShowUpgradesFrame = false,
	ShowBaseUpgradeSurfaceButton = false,
	ShowMobileBombButton = false,
	ShowJumpButton = false,
	ShowBackButton = false,
	BackProxyScale = 1,
	UseBlackout = false,
}

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
		Text = "Collect cash from your Brainrot",
		TargetType = "WorldCollectCash",
	},
	[7] = {
		Text = "Upgrade your bomb",
		TargetType = "WorldBombShop",
	},
	[8] = {
		Text = "Buy Venom Bomb",
		TargetType = "GuiBuyBombButton",
	},
	[9] = {
		Text = "",
		TargetType = "None",
	},
	[10] = {
		Text = "Tutorial complete",
		TargetType = "None",
	},
} :: {[number]: TutorialStepDefinition}

TutorialConfiguration.StepPresentations = {
	[1] = {
		MaskUi = true,
		ShowText = true,
		ShowMoney = false,
		ShowInventory = false,
		ShowBombShopButton = false,
		ShowPickaxesFrame = false,
		ShowUpgradesFrame = false,
		ShowBaseUpgradeSurfaceButton = false,
		ShowMobileBombButton = false,
		ShowJumpButton = false,
		ShowBackButton = false,
		BackProxyScale = 1,
		UseBlackout = false,
	},
	[2] = {
		MaskUi = true,
		ShowText = true,
		ShowMoney = false,
		ShowInventory = false,
		ShowBombShopButton = false,
		ShowPickaxesFrame = false,
		ShowUpgradesFrame = false,
		ShowBaseUpgradeSurfaceButton = false,
		ShowMobileBombButton = true,
		ShowJumpButton = true,
		ShowBackButton = false,
		BackProxyScale = 1,
		UseBlackout = false,
	},
	[3] = {
		MaskUi = true,
		ShowText = true,
		ShowMoney = false,
		ShowInventory = false,
		ShowBombShopButton = false,
		ShowPickaxesFrame = false,
		ShowUpgradesFrame = false,
		ShowBaseUpgradeSurfaceButton = false,
		ShowMobileBombButton = true,
		ShowJumpButton = true,
		ShowBackButton = false,
		BackProxyScale = 1,
		UseBlackout = false,
	},
	[4] = {
		MaskUi = true,
		ShowText = true,
		ShowMoney = false,
		ShowInventory = false,
		ShowBombShopButton = false,
		ShowPickaxesFrame = false,
		ShowUpgradesFrame = false,
		ShowBaseUpgradeSurfaceButton = false,
		ShowMobileBombButton = false,
		ShowJumpButton = false,
		ShowBackButton = true,
		BackProxyScale = 1,
		UseBlackout = false,
	},
	[5] = {
		MaskUi = true,
		ShowText = true,
		ShowMoney = false,
		ShowInventory = false,
		ShowBombShopButton = false,
		ShowPickaxesFrame = false,
		ShowUpgradesFrame = false,
		ShowBaseUpgradeSurfaceButton = false,
		ShowMobileBombButton = false,
		ShowJumpButton = false,
		ShowBackButton = false,
		BackProxyScale = 1,
		UseBlackout = false,
	},
	[6] = {
		MaskUi = true,
		ShowText = true,
		ShowMoney = TutorialUiConfiguration.ShouldShowMoney(6),
		ShowInventory = false,
		ShowBombShopButton = false,
		ShowPickaxesFrame = false,
		ShowUpgradesFrame = false,
		ShowBaseUpgradeSurfaceButton = false,
		ShowMobileBombButton = false,
		ShowJumpButton = false,
		ShowBackButton = false,
		BackProxyScale = 1,
		UseBlackout = false,
	},
	[7] = {
		MaskUi = FULL_UI_STEP_PRESENTATION.MaskUi,
		ShowText = FULL_UI_STEP_PRESENTATION.ShowText,
		ShowMoney = TutorialUiConfiguration.ShouldShowMoney(7),
		ShowInventory = FULL_UI_STEP_PRESENTATION.ShowInventory,
		ShowBombShopButton = FULL_UI_STEP_PRESENTATION.ShowBombShopButton,
		ShowPickaxesFrame = FULL_UI_STEP_PRESENTATION.ShowPickaxesFrame,
		ShowUpgradesFrame = FULL_UI_STEP_PRESENTATION.ShowUpgradesFrame,
		ShowBaseUpgradeSurfaceButton = FULL_UI_STEP_PRESENTATION.ShowBaseUpgradeSurfaceButton,
		ShowMobileBombButton = FULL_UI_STEP_PRESENTATION.ShowMobileBombButton,
		ShowJumpButton = FULL_UI_STEP_PRESENTATION.ShowJumpButton,
		ShowBackButton = FULL_UI_STEP_PRESENTATION.ShowBackButton,
		BackProxyScale = FULL_UI_STEP_PRESENTATION.BackProxyScale,
		UseBlackout = FULL_UI_STEP_PRESENTATION.UseBlackout,
	},
	[8] = {
		MaskUi = FULL_UI_STEP_PRESENTATION.MaskUi,
		ShowText = FULL_UI_STEP_PRESENTATION.ShowText,
		ShowMoney = TutorialUiConfiguration.ShouldShowMoney(8),
		ShowInventory = FULL_UI_STEP_PRESENTATION.ShowInventory,
		ShowBombShopButton = FULL_UI_STEP_PRESENTATION.ShowBombShopButton,
		ShowPickaxesFrame = true,
		ShowUpgradesFrame = FULL_UI_STEP_PRESENTATION.ShowUpgradesFrame,
		ShowBaseUpgradeSurfaceButton = FULL_UI_STEP_PRESENTATION.ShowBaseUpgradeSurfaceButton,
		ShowMobileBombButton = FULL_UI_STEP_PRESENTATION.ShowMobileBombButton,
		ShowJumpButton = FULL_UI_STEP_PRESENTATION.ShowJumpButton,
		ShowBackButton = FULL_UI_STEP_PRESENTATION.ShowBackButton,
		BackProxyScale = FULL_UI_STEP_PRESENTATION.BackProxyScale,
		UseBlackout = FULL_UI_STEP_PRESENTATION.UseBlackout,
	},
	[9] = {
		MaskUi = DEFAULT_STEP_PRESENTATION.MaskUi,
		ShowText = DEFAULT_STEP_PRESENTATION.ShowText,
		ShowMoney = DEFAULT_STEP_PRESENTATION.ShowMoney,
		ShowInventory = DEFAULT_STEP_PRESENTATION.ShowInventory,
		ShowBombShopButton = DEFAULT_STEP_PRESENTATION.ShowBombShopButton,
		ShowPickaxesFrame = DEFAULT_STEP_PRESENTATION.ShowPickaxesFrame,
		ShowUpgradesFrame = DEFAULT_STEP_PRESENTATION.ShowUpgradesFrame,
		ShowBaseUpgradeSurfaceButton = DEFAULT_STEP_PRESENTATION.ShowBaseUpgradeSurfaceButton,
		ShowMobileBombButton = DEFAULT_STEP_PRESENTATION.ShowMobileBombButton,
		ShowJumpButton = DEFAULT_STEP_PRESENTATION.ShowJumpButton,
		ShowBackButton = DEFAULT_STEP_PRESENTATION.ShowBackButton,
		BackProxyScale = DEFAULT_STEP_PRESENTATION.BackProxyScale,
		UseBlackout = DEFAULT_STEP_PRESENTATION.UseBlackout,
	},
	[10] = DEFAULT_STEP_PRESENTATION,
} :: {[number]: TutorialStepPresentation}

function TutorialConfiguration.GetStepPresentation(step: number): TutorialStepPresentation
	return TutorialConfiguration.StepPresentations[step] or DEFAULT_STEP_PRESENTATION
end

return TutorialConfiguration
