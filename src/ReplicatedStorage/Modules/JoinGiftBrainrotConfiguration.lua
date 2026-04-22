--!strict

local JoinGiftBrainrotConfiguration = {
	Enabled = true,

	PreviewDelaySeconds = 2,
	AutoPickupDelaySeconds = 3,

	PreviewForwardDistance = 5,
	PreviewMaxActivationDistance = 12,
	PickupDistanceTolerance = 3,
	ZoneClampPadding = 2,

	ZoneName = "Zone0",
	Rarity = "Legendary",
	Mutation = "Normal",
	Level = 1,

	PreviewRaycastHeight = 0,
	PreviewRaycastDepth = 64,

	HighlightFillColor = Color3.fromRGB(255, 214, 72),
	HighlightOutlineColor = Color3.fromRGB(255, 255, 255),
	HighlightOutlineTransparency = 0,
	HighlightPulseSpeed = 3.5,
	HighlightMinFillTransparency = 0.15,
	HighlightMaxFillTransparency = 0.45,
}

return JoinGiftBrainrotConfiguration
