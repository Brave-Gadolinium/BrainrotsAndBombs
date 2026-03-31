--!strict

local PostTutorialConfiguration = {}

PostTutorialConfiguration.Stages = {
	WaitingForCharacterMoney = 0,
	PromptCharacterUpgrade = 1,
	WaitingForBaseMoney = 2,
	PromptBaseUpgrade = 3,
	Completed = 4,
}

PostTutorialConfiguration.CharacterUpgradeMoneyThreshold = 10000
PostTutorialConfiguration.BaseUpgradeMoneyThreshold = 20000
PostTutorialConfiguration.CompletionMessageDuration = 10

PostTutorialConfiguration.PromptTexts = {
	[PostTutorialConfiguration.Stages.PromptCharacterUpgrade] = "Upgrade your character",
	[PostTutorialConfiguration.Stages.PromptBaseUpgrade] = "Make base upgrade",
}

PostTutorialConfiguration.CompletionTexts = {
	CharacterUpgrade = "Well done! Upgrade your character and become faster!",
	BaseUpgrade = "Well done! Upgrade your base and get more money!",
}

function PostTutorialConfiguration.ClampStage(stage: number): number
	return math.clamp(
		stage,
		PostTutorialConfiguration.Stages.WaitingForCharacterMoney,
		PostTutorialConfiguration.Stages.Completed
	)
end

return PostTutorialConfiguration
