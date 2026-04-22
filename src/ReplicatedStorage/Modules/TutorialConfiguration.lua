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

TutorialConfiguration.FinalStep = 12
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
		Text = "Upgrade your bomb",
		TargetType = "WorldBombShop",
	},
	[7] = {
		Text = "Buy Venom Bomb",
		TargetType = "GuiBuyBombButton",
	},
	[8] = {
		Text = "Upgrade your character",
		TargetType = "WorldCharacterUpgrade",
	},
	[9] = {
		Text = "Well done! Upgrade your character and become faster!",
		TargetType = "GuiCharacterUpgradeButton",
	},
	[10] = {
		Text = "Upgrade your base",
		TargetType = "GuiBaseUpgradeButton",
	},
	[11] = {
		Text = "Well done! Upgrade your base and get more money!",
		TargetType = "None",
	},
	[12] = {
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
		MaskUi = FULL_UI_STEP_PRESENTATION.MaskUi,
		ShowText = FULL_UI_STEP_PRESENTATION.ShowText,
		ShowMoney = TutorialUiConfiguration.ShouldShowMoney(6),
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
		ShowPickaxesFrame = FULL_UI_STEP_PRESENTATION.ShowPickaxesFrame,
		ShowUpgradesFrame = FULL_UI_STEP_PRESENTATION.ShowUpgradesFrame,
		ShowBaseUpgradeSurfaceButton = FULL_UI_STEP_PRESENTATION.ShowBaseUpgradeSurfaceButton,
		ShowMobileBombButton = FULL_UI_STEP_PRESENTATION.ShowMobileBombButton,
		ShowJumpButton = FULL_UI_STEP_PRESENTATION.ShowJumpButton,
		ShowBackButton = FULL_UI_STEP_PRESENTATION.ShowBackButton,
		BackProxyScale = FULL_UI_STEP_PRESENTATION.BackProxyScale,
		UseBlackout = FULL_UI_STEP_PRESENTATION.UseBlackout,
	},
	[9] = {
		MaskUi = FULL_UI_STEP_PRESENTATION.MaskUi,
		ShowText = FULL_UI_STEP_PRESENTATION.ShowText,
		ShowMoney = TutorialUiConfiguration.ShouldShowMoney(9),
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
	[10] = {
		MaskUi = FULL_UI_STEP_PRESENTATION.MaskUi,
		ShowText = FULL_UI_STEP_PRESENTATION.ShowText,
		ShowMoney = TutorialUiConfiguration.ShouldShowMoney(10),
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
	[11] = {
		MaskUi = FULL_UI_STEP_PRESENTATION.MaskUi,
		ShowText = FULL_UI_STEP_PRESENTATION.ShowText,
		ShowMoney = TutorialUiConfiguration.ShouldShowMoney(11),
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
	[12] = DEFAULT_STEP_PRESENTATION,
} :: {[number]: TutorialStepPresentation}

function TutorialConfiguration.GetStepPresentation(step: number): TutorialStepPresentation
	return TutorialConfiguration.StepPresentations[step] or DEFAULT_STEP_PRESENTATION
end

return TutorialConfiguration
