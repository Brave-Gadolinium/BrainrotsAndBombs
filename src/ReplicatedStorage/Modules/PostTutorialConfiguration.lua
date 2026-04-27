--!strict

local PostTutorialConfiguration = {}

PostTutorialConfiguration.Stages = {
	WaitingForCharacterMoney = 0,
	PromptCharacterUpgrade = 1,
	WaitingForBaseMoney = 2,
	PromptBaseUpgrade = 3,
	Completed = 4,
}

PostTutorialConfiguration.CompletionMessageDuration = 10

PostTutorialConfiguration.PromptTexts = {
}

PostTutorialConfiguration.CompletionTexts = {
	CharacterUpgrade = "Character upgrade complete!",
	BaseUpgrade = "Base upgrade complete!",
}

function PostTutorialConfiguration.ClampStage(stage: number): number
	return math.clamp(
		stage,
		PostTutorialConfiguration.Stages.WaitingForCharacterMoney,
		PostTutorialConfiguration.Stages.Completed
	)
end

return PostTutorialConfiguration
