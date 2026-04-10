--!strict
-- LOCATION: ReplicatedStorage/Modules/XrayBonusConfiguration

local notificationText = utf8.char(
	1058, 1099, 32, 1074, 1079, 1103, 1083, 32,
	88, 45, 114, 97, 121, 32, 1080, 32,
	1090, 1077, 1087, 1077, 1088, 1100, 32,
	1074, 1080, 1076, 1080, 1096, 1100, 32,
	1095, 1077, 1088, 1077, 1079, 32, 1079, 1077, 1084, 1083, 1102
)

local XrayBonusConfiguration = {
	Enabled = true,
	HighlightRadius = 20,
	SpawnChancePerRound = 1,
	InitialSpawnDelaySeconds = 12,
	RetryDelaySecondsWhenNoEligiblePlayers = 6,
	SpawnRetryWindowSeconds = 75,
	SpawnDistanceMin = 8,
	SpawnDistanceMax = 16,
	MaxSpawnPositionAttempts = 12,
	SpawnRaycastHeight = 10,
	SpawnRaycastDepth = 32,
	PickupMaxDistance = 12,
	PromptActionText = "Pick Up",
	PromptObjectText = "X-ray",
	HighlightFillColor = Color3.fromRGB(98, 240, 255),
	HighlightOutlineColor = Color3.fromRGB(255, 255, 255),
	HighlightFillTransparency = 0.45,
	HighlightOutlineTransparency = 0,
	HighlightRefreshInterval = 0.2,
	UseNearestBeam = true,
	NotificationText = notificationText,
}

return XrayBonusConfiguration
