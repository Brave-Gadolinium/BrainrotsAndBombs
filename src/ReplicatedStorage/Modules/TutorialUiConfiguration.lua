--!strict

local TutorialUiConfiguration = {}

export type TutorialUiTargetKey =
	"Money"
	| "MobileBombButton"
	| "JumpButton"
	| "BombBuyButton"
	| "CharacterUpgradeButton"
	| "BaseUpgradeSurfaceButton"

TutorialUiConfiguration.PersistentMoneyStartStep = 6

local RETRY_TARGETS_BY_STEP: {[number]: {TutorialUiTargetKey}} = {
	[2] = {"MobileBombButton", "JumpButton"},
	[3] = {"MobileBombButton", "JumpButton"},
	[6] = {"Money"},
	[7] = {"Money"},
	[8] = {"Money", "BombBuyButton"},
	[9] = {"Money"},
	[10] = {"Money", "CharacterUpgradeButton"},
	[11] = {"Money", "BaseUpgradeSurfaceButton"},
	[12] = {"Money"},
}

local PRESERVE_ORIGINAL_VISIBILITY_TARGETS: {[TutorialUiTargetKey]: boolean} = {
	BaseUpgradeSurfaceButton = true,
}

function TutorialUiConfiguration.ShouldShowMoney(step: number): boolean
	return step >= TutorialUiConfiguration.PersistentMoneyStartStep
end

function TutorialUiConfiguration.GetRetryTargets(step: number): {TutorialUiTargetKey}
	return RETRY_TARGETS_BY_STEP[step] or {}
end

function TutorialUiConfiguration.ShouldPreserveOriginalVisibility(targetKey: TutorialUiTargetKey): boolean
	return PRESERVE_ORIGINAL_VISIBILITY_TARGETS[targetKey] == true
end

return TutorialUiConfiguration
